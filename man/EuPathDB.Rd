% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/eupathdb.R
\docType{package}
\name{EuPathDB}
\alias{EuPathDB-package}
\alias{EuPathDB}
\title{EuPathDB: Access EuPathDB annotations using AnnotationHub}
\description{
EuPathDB provides an R interface for retrieving annotation resources from
the EuPathDB databases: AmoebaDB, CryptoDB, FungiDB, GiardiaDB,
MicrosporidiaDB, PiroplasmaDB, PlasmoDB, ToxoDB, TrichDB, and TriTrypDB
using the Bioconductor AnnotationHub framework.
}
\details{
There are currently two types of Bioconductor resources which can be
retrieved for 194 supported organisms from the various EuPathDB databases:

\itemize{
\item OrgDB resources
\item GRanges resources
}

The OrgDB resources provides gene level information including chromosome,
location, name, description, orthologs, and associated GO terms.

The GRanges resources provide transcript-level information such as known
exons and their corresponding locations.

Each of these resources are generated using information obtained from the
EuPathDB GFF files along with queries made through the various EuPathDB web
APIs.

For examples of how EuPathDB can be used to query and interact with
EuPathDB.org resources, take a look at the vignette:
\code{browseVignettes(package="EuPathDB")}

Use \code{availableEuPathDB()} to get a vector of available organisms.
}
\seealso{
\code{\link{AnnotationHub}}

\code{\link{GRanges}}

\url{http://eupathdb.org/eupathdb/}
}
\author{
Keith Hughitt and Ashton Belew
}
