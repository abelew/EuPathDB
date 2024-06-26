% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/make_eupath_orgdb.R
\name{make_eupath_orgdb}
\alias{make_eupath_orgdb}
\title{Create an orgdb SQLite database from the tables in eupathdb.}
\usage{
make_eupath_orgdb(
  entry,
  install = TRUE,
  reinstall = FALSE,
  overwrite = FALSE,
  verbose = FALSE,
  copy_s3 = FALSE,
  godb_source = NULL,
  split = 13,
  build = TRUE,
  build_dir = "build"
)
}
\arguments{
\item{entry}{If not provided, then species will get this, it contains all the information.}

\item{install}{Install the resulting package?}

\item{reinstall}{Re-install an already existing orgdb?}

\item{overwrite}{Overwrite a partial installation?}

\item{verbose}{talky talky}

\item{copy_s3}{Copy the 2bit file into an s3 staging directory for copying to AnnotationHub?}

\item{godb_source}{Which table to use for the putative union of the GO tables.}

\item{build_dir}{Where to put all the various temporary files.}
}
\value{
Currently only the name of the installed package.  This should
 probably change.
}
\description{
This function has passed through multiple iterations as the preferred
method(s) for accessing data in the eupathdb has changed.  It currently uses
my empirically defined set of queries against the eupathdb webservices.  As a
result, I have made some admittedly bizarre choices when creating the
queries.  Check through eupath_webservices.r for some amusing examples of how
I have gotten around the idiosyncrasies in the eupathdb.  Final note, I confirmed
with Cristina that it is not possible to acquire data specific to a given version
of the eupathdb.
}
\author{
Keith Hughitt with significant modifications by atb.
}
