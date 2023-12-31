% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/simulate_inhalation_rate.R
\name{simulate_inhalation_rate}
\alias{simulate_inhalation_rate}
\title{Simulate inhalation rates}
\usage{
simulate_inhalation_rate(ages, params = NULL)
}
\arguments{
\item{ages}{array of ages.}

\item{params}{data frame with columns "age", "mean" and "sd". The age column
should be in ascending order and represent the lower value of age groups for
the corresponding mean and sd values.}
}
\value{
array of inhalation rates.
}
\description{
Simulate inhalation rates
}
\examples{
simulate_inhalation_rate(c(1, 6, 20))
}
