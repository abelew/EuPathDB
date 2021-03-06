#' Shortcut for loading annotation data from a eupathdb-based orgdb.
#'
#' Every time I go to load the annotation data from an orgdb for a parasite, it
#' takes me an annoyingly long time to get the darn flags right.  As a result I
#' wrote this to shortcut that process.  Ideally, one should only need to pass
#' it a species name and get out a nice big table of annotation data.
#'
#' @param query String containing a unique portion of the desired species.
#' @param webservice Which eupath webservice is desired?
#' @param eu_version Gather data from a specific eupathdb version?
#' @param wanted_fields If not provided, this will gather all columns starting
#'  with 'annot'.
#' @return Big huge data frame of annotation data.
#' @export
load_eupath_annotations <- function(query, webservice = "tritrypdb",
                                    eu_version = NULL, wanted_fields = NULL) {
  pkg <- NULL
  entry <- NULL
  if ("OrgDb" %in% class(query)) {
    pkg <- query
  } else if ("character" %in% class(query)) {
    entry <- get_eupath_entry(species = query, webservice = webservice)
    pkg_names <- get_eupath_pkgnames(entry = entry, eu_version = eu_version)
    pkg_installedp <- pkg_names[["orgdb_installed"]]
    if (isFALSE(pkg_installedp)) {
      stop("The required package is not installed.")
    }
    pkg <- as.character(pkg_names[["orgdb"]])
  } else if ("data.frame" %in% class(query)) {
    entry <- query
    pkg_names <- get_eupath_pkgnames(entry = entry, eu_version = eu_version)
    pkg_installedp <- pkg_names[["orgdb_installed"]]
    if (isFALSE(pkg_installedp)) {
      stop("The required package is not installed.")
    }
    pkg <- as.character(pkg_names[["orgdb"]])
  }

  if (is.null(wanted_fields)) {
    if ("character" %in% class(pkg)) {
      org_pkgstring <- glue("library({pkg}); pkg <- {pkg}")
      eval(parse(text = org_pkgstring))
    }
    all_fields <- AnnotationDbi::keytypes(x = pkg)
    annot_fields_idx <- grepl(pattern="^ANNOT", x = all_fields)
    annot_fields <- all_fields[annot_fields_idx]
    wanted_fields <- c("gid", annot_fields)
    message("Returning fields which start with 'annot'")
  }

  org <- load_orgdb_annotations(pkg, keytype = "gid", fields = wanted_fields)[["genes"]]
  colnames(org) <- gsub(pattern = "^annot_", replacement = "", x = colnames(org))
  kept_columns <- !duplicated(colnames(org))
  org <- org[, kept_columns]
  return(org)
}
