check_orgdb_args <- function(orgdb_args, tables) {
  for (t in seq_len(length(tables))) {
    table <- tables[[t]]
    name <- names(tables)[t]
    if (is.null(table)) {
      message(" ", name, " is null, not adding to the orgdb_args.")
    } else if (nrow(table) > 0) {
      orgdb_args[[name]] <- table
    }
  }
  return(orgdb_args)
}

clean_orgdb_args <- function(orgdb_args) {
  ## Make sure no duplicated stuff snuck through, or makeOrgPackage throws an error.
  ## Make sure that every GID field is character, too
  ## -- otherwise you get 'The type of data in the 'GID'
  ## columns must be the same for all data.frames.'
  used_columns <- c()
  for (i in seq_len(length(orgdb_args))) {
    argname <- names(orgdb_args)[i]
    if (class(orgdb_args[[i]])[1] == "data.frame") {
      ## Make sure that the column names in this data frame are unique.
      ## This starts at 2 because the first column should _always_ by 'GID'
      for (cn in seq(from = 2, to = length(colnames(orgdb_args[[i]])))) {
        colname <- colnames(orgdb_args[[i]])[cn]
        if (colname %in% used_columns) {
          new_colname <- glue("{toupper(argname)}_{colname}")
          colnames(orgdb_args[[i]])[cn] <- new_colname
          used_columns <- c(used_columns, new_colname)
        } else {
          used_columns <- c(used_columns, colname)
        }
      }
      ## This should no longer be needed
      ## First swap out NA to ""
      na_tmp <- orgdb_args[[i]]
      na_set <- is.na(na_tmp)
      na_tmp[na_set] <- ""
      orgdb_args[[i]] <- na_tmp

      orgdb_dups <- duplicated(orgdb_args[[i]])
      if (sum(orgdb_dups) > 0) {
        tmp <- orgdb_args[[i]]
        tmp <- tmp[!orgdb_dups, ]
        orgdb_args[[i]] <- tmp
      }
      ## Finally, make sure all GID columns are characters
      orgdb_args[[i]][["GID"]] <- as.character(orgdb_args[[i]][["GID"]])
    } ## End checking for data.frames
  }
  return(orgdb_args)
}

download_eupath_tables <- function(table_names, entry, working_species,
                                   overwrite, gene_ids, gene_columns,
                                   gene_table) {
  tables <- list()
  for (t in table_names) {
    name <- glue("{t}_table")
    table <- data.frame()
    if (t == "go") {
      table <- try(post_eupath_go_table(entry, working_species,
                                        overwrite = overwrite))
    } else if (t == "goslim") {
      table <- try(post_eupath_goslim_table(entry, working_species,
                                            overwrite = overwrite))
    } else if (t == "interpro") {
      table <- try(post_eupath_interpro_table(entry, working_species,
                                              overwrite = overwrite))
    } else if (t == "linkout") {
      table <- try(post_eupath_linkout_table(entry, working_species,
                                             overwrite = overwrite))
    } else if (t == "ortholog") {
      if ("ANNOT_GENE_ORTHOMCL_NAME" %in% gene_columns) {
        table <- gene_table[, c("GID", "ANNOT_GENE_ORTHOMCL_NAME")]
        colnames(table) <- c("GID", "ORTHOLOGS_GROUP_ID")
      } else {
        table <- as.data.frame("GID" = gene_ids)
        table[["ORTHOLOGS_GROUP_ID"]] <- ""
      }
      table <- try(post_eupath_ortholog_table(entry, working_species,
                                              ortholog_table = table,
                                              gene_ids = gene_ids,
                                              overwrite = overwrite))
    } else if (t == "pathway") {
      table <- try(post_eupath_pathway_table(entry, working_species,
                                             overwrite = overwrite))
    } else if (t == "pdb") {
      table <- try(post_eupath_pdb_table(entry, working_species,
                                         overwrite = overwrite))
    } else if (t == "pubmed") {
      table <- try(post_eupath_pubmed_table(entry, working_species,
                                            overwrite = overwrite))
    }

    add_table <- TRUE
    if ("try-error" %in% class(table)) {
      add_table <- FALSE
    } else if (is.null(table)) {
      add_table <- FALSE
    } else if (nrow(table) == 0) {
      add_table <- FALSE
    }

    if (isTRUE(add_table)) {
      tables[[name]] <- table
    }
  }
  return(tables)
}

#' Create an orgdb SQLite database from the tables in eupathdb.
#'
#' This function has passed through multiple iterations as the preferred
#' method(s) for accessing data in the eupathdb has changed.  It currently uses
#' my empirically defined set of queries against the eupathdb webservices.  As a
#' result, I have made some admittedly bizarre choices when creating the
#' queries.  Check through eupath_webservices.r for some amusing examples of how
#' I have gotten around the idiosyncrasies in the eupathdb.  Final note, I confirmed
#' with Cristina that it is not possible to acquire data specific to a given version
#' of the eupathdb.
#'
#' @param entry If not provided, then species will get this, it contains all the information.
#' @param build_dir Where to put all the various temporary files.
#' @param install Install the resulting package?
#' @param reinstall Re-install an already existing orgdb?
#' @param overwrite Overwrite a partial installation?
#' @param verbose talky talky
#' @param copy_s3 Copy the 2bit file into an s3 staging directory for copying to AnnotationHub?
#' @param godb_source Which table to use for the putative union of the GO tables.
#' @return Currently only the name of the installed package.  This should
#'  probably change.
#' @author Keith Hughitt with significant modifications by atb.
#' @import glue
#' @export
make_eupath_orgdb <- function(entry, install = TRUE, reinstall = FALSE, overwrite = FALSE,
                              verbose = FALSE, copy_s3 = FALSE, godb_source = NULL, split = 13,
                              build = TRUE, build_dir = "build") {
  ## Pull out the metadata for this species.
  if ("character" %in% class(entry)) {
    entry <- get_eupath_entry(entry)
  }
  taxa <- make_taxon_names(entry)
  ## Figure out the package name to use: (e.g. "org.Cbaileyi.TAMU.09Q1.v46.eg.db")
  pkgnames <- get_eupath_pkgnames(entry)
  pkgname <- pkgnames[["orgdb"]]

  ## I think it is no longer necessary to do stuff like this, but instead get the information from
  ## the entry[['OrgDbFile']] or whatever...
  orgdb_path <- file.path(build_dir, pkgname)
  if (isTRUE(pkgnames[["orgdb_installed"]]) && !isTRUE(reinstall)) {
    sqlite_file <- basename(gsub(x = orgdb_path, pattern = "db$", replacement = "sqlite"))
    db_path <- system.file(file.path("extdata", sqlite_file), package = pkgname)
    message(" ", pkgname, " is already installed and a copy should be found at: ", db_path, ".")
    retlist <- list(
      "orgdb_name" = pkgname,
      "db_path" = db_path)
    return(retlist)
  }
  message("Starting creation of ", pkgname, ".")
  ## Create working directory if necessary

  ## The place to stick the orgdb upon completion.
  org_path <- file.path(build_dir, "orgdb")
  if (!file.exists(org_path)) {
    tt <- dir.create(org_path, recursive = TRUE)
  }

  ## I am almost certain that wrapping these in a try() is no longer necessary.
  gene_table <- try(post_eupath_annotations(entry, overwrite = overwrite, split = split))
  working_species <- attr(gene_table, "species")
  if ("try-error" %in% class(gene_table) || is.null(gene_table) ||
        nrow(gene_table) == 0) {
    gene_table <- data.frame()
    warning(" Unable to create an orgdb for this species.")
    return(NULL)
  }

  ## I do not think you can disable this, the package creation later fails horribly without it.
  ## At some point we should be able to remove this, because post_*() try pretty hard to get
  ## rid of spurious NAs in the returned data.
  gene_table <- remove_eupath_nas(gene_table, "annot")
  table_names <- c("go", "goslim", "interpro", "linkout",
                   "ortholog", "pathway", "pdb", "pubmed")
  gene_ids <- gene_table[["GID"]]
  gene_columns <- colnames(gene_table)
  tables <- download_eupath_tables(table_names, entry, working_species,
                                   overwrite, gene_ids, gene_columns, gene_table)

  ## Create the baby table of chromosomes
  chromosome_table <- gene_table[, c("GID", "ANNOT_SEQUENCE_ID")]
  colnames(chromosome_table) <- c("GID", "CHR_ID")
  chromosome_table[["CHR_ID"]] <- as.factor(chromosome_table[["CHR_ID"]])
  type_table <- gene_table[, c("GID", "ANNOT_GENE_TYPE")]
  colnames(type_table) <- c("GID", "GENE_TYPE")

  ## Compile list of arguments for makeOrgPackage call
  pkg_version_string <- format(Sys.time(), "%Y.%m")
  orgdb_args <- list(
    "version" = pkg_version_string,
    "maintainer" = entry[["Maintainer"]],
    "author" = entry[["Maintainer"]],
    "outputDir" = build_dir,
    "tax_id" = as.character(entry[["TaxonomyID"]]),
    "genus" = taxa[["genus"]],
    "species" = glue("{taxa[['species_strain']]}.v{entry[['SourceVersion']]}"),
    "goTable" = "godb_xref",
    "gene_info" = gene_table,
    "chromosome" = chromosome_table,
    "type" = type_table)
  ## Add to the orgdb args the non-empty tables.
  orgdb_args <- check_orgdb_args(orgdb_args, tables)
  ## Do a final pass for weird stuff in them.
  orgdb_args <- clean_orgdb_args(orgdb_args)

  ## I am reading the AnnotationForge documentation and learning some ways to improve this.
  ## Here is one interesting section (arguments for makeOrgPackage()):
  ## goTable: By default, this is NULL, but if one of your ... data.frames has GO
  ## annotations, then this name will be the name of that argument. When you specify this,
  ## makeOrgPackage will process that data.frame to remove extra GO terms (that
  ## are too new for the current GO.db) and also will generate a table for GOALL
  ## data (based on ancestor terms for each mapping from GO.db). This table will
  ## also be checked to make sure that it has exactly THREE columns, that must be
  ## named GID, GO and EVIDENCE. These must correspond to the gene IDs, GO
  ## IDs and evidence codes respectively. GO IDs should be formatted like this to
  ## work with other DBs in the project: 'GO:XXXXXXX'.
  ##
  ## It appears to me that this is pretty much perfect for the goslim data.
  godb_table <- data.frame()
  if (is.null(godb_source)) {
    message("Setting the godb source to the union of go and goslim.")
    if (nrow(tables[["goslim_table"]]) > 0) {
        godb_table <- tables[["goslim_table"]][, c("GID", "GOSLIM_GO_ID")]
        godb_table[["EVIDENCE"]] <- "GOSlim"
      colnames(godb_table) <- c("GID", "GO", "EVIDENCE")
    }
    if (nrow(tables[["go_table"]]) > 0) {
      tmp_table <- tables[["go_table"]][, c("GID", "GO_ID", "GO_EVIDENCE_CODE")]
      colnames(tmp_table) <- c("GID", "GO", "EVIDENCE")
      godb_table <- rbind(godb_table, tmp_table)
    }
  } else if (godb_source == "goslim") {
    if (nrow(tables[["goslim_table"]]) > 0) {
        godb_table <- tables[["goslim_table"]][, c("GID", "GOSLIM_GO_ID")]
        godb_table[["EVIDENCE"]] <- "GOSlim"
      colnames(godb_table) <- c("GID", "GO", "EVIDENCE")
    }
  } else {
    if (nrow(tables[["go_table"]]) > 0) {
      godb_table <- tables[["go_table"]][, c("GID", "GO_ID", "GO_EVIDENCE_CODE")]
      colnames(godb_table) <- c("GID", "GO", "EVIDENCE")
      godb_table <- rbind(godb_table, tmp_table)
    }
  }
  ## We have made as complete a godb table as possible.  Likely comprised of the
  ## concatenation of the goslim and go tables.  No clean it up.
  if (nrow(godb_table) > 0) {
    godb_idx <- order(godb_table[["GID"]])
    godb_table <- godb_table[godb_idx, ]
    dup_idx <- duplicated(godb_table)
    godb_table <- godb_table[!dup_idx, ]
    godb_table[["EVIDENCE"]] <- as.factor(godb_table[["EVIDENCE"]])
    message("Adding the goTable argument with: ", nrow(godb_table), " rows.")
    orgdb_args[["godb_xref"]] <- godb_table
  }

  ## FIXME: I think this got messed up when rebasing, I had a little logic
  ## to back up partially created directories.
  ## The following lines are because makeOrgPackage fails stupidly if the directory exists.
  if (file.exists(orgdb_path)) {
    message(orgdb_path, " already exists, deleting it.")
    ## Something which bit me in the ass for file operations in R, always
    ## set a return value and check it.
    ret <- unlink(orgdb_path, recursive = TRUE)
  }

  ## Now lets finally make the package!
  lib_result <- requireNamespace("AnnotationForge")
  att_result <- try(attachNamespace("AnnotationForge"), silent = TRUE)
  message("Calling makeOrgPackage() for ", entry[["TaxonUnmodified"]])

  built_orgdb_path <- NULL
  if (isTRUE(verbose)) {
    built_orgdb_path <- try(do.call("makeOrgPackage", orgdb_args))
  } else {
    built_orgdb_path <- suppressMessages(try(do.call("makeOrgPackage", orgdb_args)))
  }
  if (class(built_orgdb_path)[1] == "try-error") {
    return(NULL)
  }
  if (orgdb_path != built_orgdb_path) {
    warning("Something is funky with the expected and actual orgdb build path.")
  }

  ## Fix name in sqlite metadata table
  dbpath <- file.path(
    orgdb_path, "inst", "extdata", sub(".db", ".sqlite", basename(orgdb_path)))
  ## make sqlite database editable
  Sys.chmod(dbpath, mode = "0644")
  db <- RSQLite::dbConnect(RSQLite::SQLite(), dbname = dbpath)
  ## update SPECIES field
  query <- glue('UPDATE metadata SET value = "{entry[["TaxonUnmodified"]]}" WHERE name = "SPECIES";')
  sq_result <- RSQLite::dbSendQuery(conn = db, query)
  cleared <- RSQLite::dbClearResult(sq_result)
  ## update ORGANISM field
  query <- glue('UPDATE metadata SET value = "{entry[["TaxonUnmodified"]]}" WHERE name = "ORGANISM";')
  sq_result <- RSQLite::dbSendQuery(conn = db, query)
  cleared <- RSQLite::dbClearResult(sq_result)
  ## lock it back down
  Sys.chmod(dbpath, mode = "0444")
  closed <- RSQLite::dbDisconnect(db)

  ## Clean up any strangeness in the DESCRIPTION file
  orgdb_path <- clean_pkg(orgdb_path)

  ## The following 2 lines are only for Tcuzi Esmeraldo-like and NonEsmeraldo-like
  ## Since writing them, I have improved the logic in make_taxon_names() above,
  ## I therefore suspect these lines are not necessary.
  ## FIXME: See if you can remove the following two lines!
  ## orgdb_path <- clean_pkg(orgdb_path, removal = "_", replace = "")
  ## orgdb_path <- clean_pkg(orgdb_path, removal = "_like", replace = "like")

  if (isTRUE(copy_s3)) {
    s3_file <- entry[["OrgdbFile"]]
    if (file.exists(s3_file)) {
      removed <- file.remove(s3_file)
    }
    copied <- copy_s3_file(src_dir = orgdb_path, type = "orgdb", s3_file = s3_file)
    if (isTRUE(copied)) {
      message(" Successfully copied the orgdb sqlite database to the s3 staging directory.")
    } else {
      stop(" Could not copy S3 data.")
    }
  }

  ## And install the resulting package.
  ## I think installing the package really should be optional, but in the case of orgdb/txdb,
  ## without them there is no organismdbi, which makes things confusing.
  built <- NULL
  workedp <- FALSE
  if (isTRUE(build)) {
    built <- try(suppressWarnings(devtools::build(orgdb_path, quiet = TRUE)))
    workedp <- ! "try-error" %in% class(built)
  }
  if (isTRUE(install)) {
    install_path <- file.path(getwd(), orgdb_path)
    inst <- suppressWarnings(try(devtools::install_local(install_path)))
    workedp <- ! "try-error" %in% class(inst)
  }

  final_paths <- list()
  if (isTRUE(workedp)) {
    final_paths <- move_final_orgdb_package(pkgnames, build_dir = build_dir)
    orgdb_path <- final_paths[["data_path"]]
    rda_files <- get_rda_filename(entry, "all")
    for (rda in rda_files) {
      deleted <- unlink(x = rda, force = TRUE)
    }
  }

  message("Finished creation of ", pkgname, ".")
  ## Probably should return something more useful/interesting than this, perhaps
  ## the dimensions of the various tables in the orgdb?
  sqlite_file <- basename(gsub(x = orgdb_path, pattern = "db$", replacement = "sqlite"))
  db_file <- file.path(orgdb_path, "inst", "extdata", sqlite_file)
  retlist <- list(
    "pkgname" = pkgname,
    "db_path" = db_file)
  if (!is.null(final_paths[["package_path"]])) {
    retlist[["package_file"]] <- final_paths[["package_path"]]
  }
  if (!is.null(final_paths[["data_path"]])) {
    retlist[["data_path"]] <- final_paths[["data_path"]]
  }
  class(retlist) <- "eupath_orgdb"
  return(retlist)
}
