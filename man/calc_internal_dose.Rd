% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/calc_internal_dose.R
\name{calc_internal_dose}
\alias{calc_internal_dose}
\title{Calculate internal chemical dose}
\usage{
calc_internal_dose(C_ext, IR, time = 1, BW = 1)
}
\arguments{
\item{C_ext}{ambient chemical concentration in \eqn{\frac{mg}{m^3}}}

\item{IR}{inhalation rate in \eqn{\frac{m^3}{day}}}

\item{time}{total time in \eqn{days}}

\item{BW}{body weight in \eqn{kg}}
}
\value{
internal chemical dose in \eqn{\frac{mg}{kg}}
}
\description{
Estimate the internal dose from inhalation of a chemical given inhalation rate, time, and body weight
}
\details{
TODO Additional details...
\deqn{D_{int} = \frac{C_{ext} \,\times\, IR \,\times\, time}{BW}}
}
