#' Generate an EuPathDB organism TxDb package.
#'
#' This will hopefully create a txdb package and granges savefile for a single
#' species in the eupathdb.  This depends pretty much entirely on the successful
#' download of a gff file from the eupathdb.
#'
#' @param entry One row from the organism metadata.
#' @param build_dir Base directory for building the package.
#' @param eu_version Which version of the eupathdb to use for creating this package?
#' @param reinstall Overwrite an existing installed package?
#' @param install Install the resulting package?
#' @param copy_s3 Copy the 2bit file into an s3 staging directory for copying to AnnotationHub?
#' @return TxDb instance name.
#' @author Keith Hughitt with significant modifications by atb.
#' @export
make_eupath_txdb <- function(entry = NULL, build_dir = "EuPathDB", eu_version = NULL,
                             reinstall = FALSE, install = TRUE, copy_s3 = FALSE) {
  if (is.null(entry)) {
    stop("Need an entry.")
  }

  taxa <- make_taxon_names(entry)
  pkgnames <- get_eupath_pkgnames(entry, eu_version = eu_version)
  pkgname <- pkgnames[["txdb"]]

  input_gff <- file.path(build_dir, glue::glue("{pkgname}.gff"))
  gff_url <- gsub(pattern = "^http:", replacement = "https:", x = entry[["SourceUrl"]])
  if (isTRUE(pkgnames[["txdb_installed"]]) & !isTRUE(reinstall)) {
    message(" ", pkgname, " is already installed.")
    retlist <- list(
      "gff" = input_gff,
      "txdb_name" = pkgname)
    return(retlist)
  }

  ## check to see if gff file exists
  if (!RCurl::url.exists(gff_url)) {
    warn(sprintf("Cannot create TxDb package for %s %s: GFF file unavailable.",
                 entry[["Species"]], entry[["Strain"]]))
    return(NULL)
  }

  message("Starting creation of ", pkgname, ".")
  downloaded_gff <- try(download.file(url = gff_url, destfile = input_gff,
                                      method = "curl", quiet = FALSE), silent = TRUE)
  if ("try-error" %in% class(downloaded_gff)) {
    stop(" Failed to download the gff file from: ", gff_url, ".")
  }

  ## It appears that sometimes I get weird results from this download.file()
  ## So I will use the later import.gff3 here to ensure that the gff is actually a gff.
  granges_lst <- try(make_eupath_granges(entry = entry, build_dir = build_dir,
                                         copy_s3 = copy_s3), silent = TRUE)
  if ("try-error" %in% class(granges_lst)) {
    warn(sprintf("Cannot create TxDb package for %s %s: failed to create GRanges object.",
                 entry[["Species"]], entry[["Strain"]]))
    return(NULL)
  }
  ## Happily, making a granges from txdb is quite quick and easy in most cases.

  if (isTRUE(install)) {
    final_granges_path <- move_final_package(granges_lst, type = "granges", build_dir = build_dir)
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

  txdb_metadata <- as.data.frame(t(entry))
  txdb_metadata[["name"]] <- rownames(txdb_metadata)
  colnames(txdb_metadata) <- c("value", "name")
  txdb_metadata <- txdb_metadata[, c("name", "value")]
  txdb <- try(GenomicFeatures::makeTxDbFromGFF(
                                   file = input_gff,
                                   format = "gff",
                                   chrominfo = chromosome_info,
                                   dataSource = entry[["SourceUrl"]],
                                   organism = glue::glue("{taxa[['genus']]} {taxa[['species']]}"),
                                   ))
  if ("try-error" %in% class(txdb)) {
    ## Perhaps it is an invalid taxonomy ID?
    txdb <- try(GenomicFeatures::makeTxDbFromGFF(
                                     taxonomyId = 32644, ## 32644 is unidentified according to:
                                     ## https://www.ncbi.nlm.nih.gov/Taxonomy/Browser/wwwtax.cgi?id=32644
                                     file = input_gff,
                                     format = "gff",
                                     chrominfo = chromosome_info,
                                     dataSource = entry[["SourceUrl"]],
                                     organism = glue::glue("{taxa[['genus']]} {taxa[['species']]}"),
                                     ))
  }
  if ("try-error" %in% class(txdb)) {
    message("The txdb creation failed.")
    return(NULL)
  }

  ## Fill in the granges metadata.
  provider <- getMetaDataValue(txdb, "Data source")
  providerVersion <- getTxDbVersion(txdb)
  dbType <- getMetaDataValue(txdb, "Db type")
  authors <- normAuthor(entry[["Maintainer"]], entry[["Maintainer"]])
  template_path <- system.file("txdb-template", package = "GenomicFeatures")
  version_string <- format(Sys.time(), "%Y.%m")
  data_source <- getMetaDataValue(txdb, "Data source")

  ## Fill in the metadata
  symvals <- list(
    "PKGTITLE" = glue::glue("Annotation package for {dbType} object(s)"),
    "PKGDESCRIPTION" = glue::glue("Exposes an annotation databases generated from \\
                             {data_source} by exposing these as {dbType} objects"),
    "PKGVERSION" = version_string,
    "AUTHOR" = paste(authors, collapse = ", "),
    "MAINTAINER" = as.character(getMaintainer(authors)),
    "GFVERSION" = getMetaDataValue(txdb,
                                   "GenomicFeatures version at creation time"),
    "LIC" = "Artistic-2.0",
    "DBTYPE" = dbType,
    "ORGANISM" = getMetaDataValue(txdb, "Organism"),
    "SPECIES" = getMetaDataValue(txdb, "Organism"),
    "PROVIDER" = provider,
    "PROVIDERVERSION" = providerVersion,
    "RELEASEDATE" = getMetaDataValue(txdb, "Creation time"),
    "SOURCEURL" = entry[["SourceUrl"]],
    "ORGANISMBIOCVIEW" = gsub(" ", "_", getMetaDataValue(txdb, "Organism")),
    "TXDBOBJNAME" = pkgname)

  ## Do a little final sanity checking
  if (any(duplicated(names(symvals)))) {
    str(symvals)
    stop(" 'symvals' contains duplicated symbols")
  }
  is_OK <- sapply(symvals, S4Vectors::isSingleString)
  if (!all(is_OK)) {
    bad_syms <- paste(names(is_OK)[!is_OK], collapse = ", ")
    stop(" values for symbols ", bad_syms, " are not single strings")
  }

  ## Assuming we got this far, we should be able to create the txdb package.
  if (!file.exists(build_dir)) {
    tt <- dir.create(build_dir, recursive=TRUE)
  }
  pkg_list <- Biobase::createPackage(pkgname = pkgname, destinationDir = build_dir,
                                     originDir = template_path, symbolValues = symvals,
                                     unlink = TRUE)
  db_dir <- file.path(build_dir, pkgname, "inst", "extdata")
  if (!file.exists(db_dir)) {
    tt <- dir.create(db_dir, recursive = TRUE)
  }
  db_path <- file.path(db_dir, paste(pkgname, "sqlite", sep = "."))

  obj <- try(AnnotationDbi::saveDb(txdb, file = db_path))
  if ("try-error" %in% class(obj)) {
    warning(" Failed to save the txdb object.")
  }
  closed <- try(RSQLite::dbDisconnect(BiocGenerics::dbconn(obj)), silent = TRUE)

  install_dir <- file.path(build_dir, pkgname)
  install_dir <- clean_pkg(install_dir)
  install_dir <- clean_pkg(install_dir, removal = "_", replace = "")
  install_dir <- clean_pkg(install_dir, removal = "_like", replace = "like")

  if (isTRUE(copy_s3)) {
    s3_file <- entry[["TxdbFile"]]
    copied <- copy_s3_file(src_dir = db_dir, type = "txdb", s3_file = s3_file)
    if (isTRUE(copied)) {
      message(" Successfully copied the txdb sqlite to the s3 staging directory.")
    }
  }

  if (isTRUE(install)) {
    inst <- try(devtools::install(install_dir, quiet = TRUE))
    if (! "try-error" %in% class(inst)) {
      built <- try(devtools::build(install_dir, quiet = TRUE))
      if (! "try-error" %in% class(built)) {
        final_path <- move_final_package(pkgname, type = "txdb", build_dir = build_dir)
        final_deleted <- unlink(x = install_dir, recursive = TRUE, force = TRUE)
      }
    }
  }

  info(sprintf("Finished creation of %s...", pkgname))

  retlist <- list(
    "object" = txdb,
    "gff" = input_gff,
    "txdb_name" = pkgname,
    "granges_file" = granges_lst[["name"]],
    "granges_variable" = granges_lst[["variable"]])

  return(retlist)
}
