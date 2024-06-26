% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/get_all_metadata.R
\name{get_all_metadata}
\alias{get_all_metadata}
\title{Invoke download_eupathdb_metadata() using all the sub-projects of the EuPathDB.}
\usage{
get_all_metadata(
  overwrite = TRUE,
  bioc_version = NULL,
  eu_version = NULL,
  verbose = FALSE,
  build_dir = "build"
)
}
\arguments{
\item{...}{Arguments passed from above.}
}
\value{
Dataframe of the various species metadata.
}
\description{
This just iterates over a list of existing EuPathDB web resources and
attempts to download the metadata from them.
}
