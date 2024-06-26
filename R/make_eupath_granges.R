#' Generate a GRanges rda savefile from a gff file.
#'
#' There is not too much else to say. This uses import.gff from rtracklayer.
#' I should probably steal my code from hpgltools to make this work for any
#' version of a gff file, but the eupathdb is good about keeping consistent on
#' this front.
#'
#' @param entry Metadatum entry.
#' @param build_dir Place to put the resulting file(s).
#' @param eu_version Optionally request a specific version of the gff file.
#' @param copy_s3 Copy the 2bit file into an s3 staging directory for copying to AnnotationHub?
#' @export
make_eupath_granges <- function(entry, eu_version = NULL, copy_s3 = FALSE) {
  versions <- get_versions(eu_version = eu_version)
  eu_version <- versions[["eu_version"]]
  taxa <- make_taxon_names(entry)
  pkgnames <- get_eupath_pkgnames(entry, eu_version = eu_version)
  pkgname <- pkgnames[["txdb"]]

  input_gff <- file.path(build_dir, "gff", glue::glue("{pkgname}.gff"))
  if (!file.exists(input_gff)) {
    gff_url <- gsub(pattern = "^http:", replacement = "https:", x = entry[["SourceUrl"]])
    tt <- download.file(url = gff_url, destfile = input_gff,
                        method = "curl", quiet = FALSE)
  }

  chr_entries <- read.delim(file = input_gff, header = FALSE, sep = "")
  chromosomes <- chr_entries[["V1"]] == "##sequence-region"
  chromosomes <- chr_entries[chromosomes, c("V2", "V3", "V4")]
  colnames(chromosomes) <- c("ID", "start", "end")
  chromosome_info <- data.frame(
    "chrom" = chromosomes[["ID"]],
    "length" = as.numeric(chromosomes[["end"]]),
    "is_circular" = NA,
    stringsAsFactors = FALSE)
  rownames(chromosome_info) <- make.names(chromosome_info[["chrom"]], unique = TRUE)

  ## Dump a granges object and save it as an rda file.
  granges_result <- rtracklayer::import.gff3(input_gff)
  name_order <- names(GenomeInfoDb::seqinfo(granges_result))
  chromosome_info <- chromosome_info[name_order, ]
  length_vector <- chromosome_info[["length"]]

  GenomeInfoDb::seqlengths(granges_result) <- length_vector
  granges_name <- pkgnames[["granges"]]
  granges_env <- new.env()
  granges_variable <- gsub(pattern = "\\.rda$", replacement = "", x = granges_name)
  granges_env[[granges_variable]] <- granges_result
  granges_file <- file.path(build_dir, granges_name)
  save_result <- save(list = ls(envir = granges_env),
                      file = granges_file,
                      envir = granges_env)

  if (isTRUE(copy_s3)) {
    s3_file <- entry[["GrangesFile"]]
    copied <- copy_s3_file(src_dir = granges_file, type = "granges",
                           s3_file = s3_file, move = TRUE)
  }

  ## import.gff3 appears to be opening 2 connections to the gff file, both are read only.
  ## It is not entirely clear to me, given the semantics of import.gff3, how to close these
  ## connections cleanly, ergo the following.  Note, if you do not check this, R will very quickly
  ## run out of the total number of open files allowed.
  extra_connections <- rownames(showConnections())
  for (con in extra_connections) {
    closed <- try(close(getConnection(con)), silent = TRUE)
  }

  message("Finished creation of GRanges ", pkgname, ".")
  retlist <- list(
    "name" = granges_name,
    "type" = "granges",
    "variable" = gsub(x = granges_name, pattern = "\\.rda$", replacement = ""),
    "rda" = granges_file)
  return(retlist)
}
