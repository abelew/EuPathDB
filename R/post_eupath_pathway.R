#' Use the post interface to get pathway data.
#'
#' @param entry The full annotation entry.
#' @param build_dir Location to which to save intermediate savefile.
#' @param overwrite If trying again, overwrite the savefile?
#' @return A big honking table.
post_eupath_pathway_table <- function(entry = NULL, build_dir = "EuPathDB", overwrite = FALSE) {
  if (is.null(entry)) {
    stop("  Need a eupathdb entry.")
  }
  rdadir <- file.path(build_dir, "rda")
  if (!file.exists(rdadir)) {
    created <- dir.create(rdadir, recursive = TRUE)
  }
  savefile <- file.path(rdadir, glue::glue("{entry[['Genome']]}_pathway_table.rda"))
  if (file.exists(savefile)) {
    if (isTRUE(overwrite)) {
      removed <- file.remove(savefile)
    } else {
      message("  Delete the file ", savefile, " to regenerate.")
      result <- new.env()
      load(savefile, envir = result)
      result <- result[["result"]]
      return(result)
    }
  }

  result <- post_eupath_table(entry, tables = "MetabolicPathways", table_name = "pathway")
  colnames(result) <- gsub(x=colnames(result), pattern="^PATHWAY_PATHWAY$",
                           replacement="PATHWAY_ID")
  colnames(result) <- gsub(x=colnames(result), pattern="PATHWAY_PATHWAY",
                           replacement="PATHWAY")
  message("  Saving ", savefile, " with ", nrow(result), " rows.")
  save(result, file=savefile)
  return(result)
}
