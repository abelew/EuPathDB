% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/move_final_package.R
\name{make_move_retlist}
\alias{make_move_retlist}
\title{Define the final locations for built packages and databases.}
\usage{
make_move_retlist(pkgnames, build_dir = build, type = "orgdb")
}
\arguments{
\item{build_dir}{toplevel dirname of the intermediate/final files.}

\item{type}{Type of package containing the final outputs.}

\item{pkglist}{Result from the package builder,
bsgenome/orgdb/txdb/granges/orgdbi.}
}
\description{
I am hoping to make the organization of the final outputs more
consistent.  This function is intended to put those locations in
place.
}
