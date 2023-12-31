library(devtools)
library(tidyverse)

################################################################################
################################################################################
# 00-Sensitivity.R
################################################################################
################################################################################

library(httk)

rm(list = ls())

set.seed(2345)

MC_iter <- 10
n_chem <- 2
n_county <- 5

##########
# Data
load("~/dev/GeoTox/data/age_by_county_20220228.RData")
load("~/dev/GeoTox/data/obesity_by_county_20220228.RData")

age.by.county <- lapply(age.by.county[1:n_county], \(x) x[1:MC_iter])
obesity.by.county <- lapply(obesity.by.county[1:n_county], \(x) x[1:MC_iter])

in_chems <- c(
  "98-86-2", "92-87-5", "92-52-4", "117-81-7", "133-06-2", "532-27-4",
  "133-90-4", "57-74-9", "510-15-6", "94-75-7", "64-67-5", "132-64-9",
  "106-46-7", "111-44-4", "79-44-7", "131-11-3", "77-78-1", "119-90-4",
  "121-14-2", "534-52-1", "51-28-5", "121-69-7", "107-21-1", "51-79-6",
  "76-44-8", "822-06-0", "77-47-4", "123-31-9", "72-43-5", "101-77-9",
  "56-38-2", "82-68-8", "87-86-5", "1120-71-4", "114-26-1", "91-22-5",
  "96-09-3", "95-80-7", "584-84-9", "95-95-4", "1582-09-8"
)[1:n_chem]

########################################
# Define population demographics for httk simulation
pop_demo <- cross_join(
  tibble(
    age_group = list(
      c(0, 2), c(3, 5), c(6, 10), c(11, 15), c(16, 20), c(21, 30),
      c(31, 40), c(41, 50), c(51, 60), c(61, 70), c(71, 100)
    )
  ),
  tibble(
    weight = c("Normal", "Obese")
  )
) %>%
  rowwise() %>%
  mutate(age_min = age_group[1]) %>%
  ungroup()

########################################
# Create wrapper function around httk steps
simulate_css <- function(chem.cas, agelim_years, weight_category, samples) {

  cat(
    chem.cas,
    paste0("(", paste(agelim_years, collapse = ", "), ")"),
    weight_category,
    "\n"
  )

  httkpop <- list(
    method = "vi",
    gendernum = NULL,
    agelim_years = agelim_years,
    agelim_months = NULL,
    weight_category = weight_category,
    reths = c(
      "Mexican American",
      "Other Hispanic",
      "Non-Hispanic White",
      "Non-Hispanic Black",
      "Other"
    )
  )

  mcs <- create_mc_samples(
    chem.cas = chem.cas,
    samples = samples,
    httkpop.generate.arg.list = httkpop,
    suppress.messages = TRUE
  )

  css <- calc_analytic_css(
    chem.cas = chem.cas,
    parameters = mcs,
    model = "3compartmentss",
    suppress.messages = TRUE
  )

  list(css)
}

########################################
# Simulate Css values
simulated_css <- lapply(in_chems, function(casrn) {
  pop_demo %>%
    rowwise() %>%
    mutate(
      css = simulate_css(.env$casrn, age_group, weight, .env$MC_iter)
    ) %>%
    ungroup()
})
simulated_css <- setNames(simulated_css, in_chems)

########################################
# Compute median Css values for different strata

# Get median Css values for each age_group
simulated_css <- lapply(
  simulated_css,
  function(cas_df) {
    cas_df %>%
      nest(.by = age_group) %>%
      mutate(
        age_median_css = sapply(data, function(df) median(unlist(df$css)))
      ) %>%
      unnest(data)
  }
)

# Get median Css values for each weight
simulated_css <- lapply(
  simulated_css,
  function(cas_df) {
    cas_df %>%
      nest(.by = weight) %>%
      mutate(
        weight_median_css = sapply(data, function(df) median(unlist(df$css)))
      ) %>%
      unnest(data) %>%
      arrange(age_min, weight)
  }
)

########################################
# Create sensitivity data objects

css_sensitivity_age <- lapply(age.by.county, function(county_age) {
  do.call(cbind, lapply(simulated_css, function(cas_df) {
    # Get age_median_css for corresponding county_age
    age_df <- cas_df %>% distinct(age_min, age_median_css)
    idx <- sapply(
      county_age,
      function(age) tail(which(age >= age_df$age_min), 1)
    )
    age_df$age_median_css[idx]
  }))
})

css_sensitivity_obesity <- lapply(obesity.by.county, function(county_weight) {
  do.call(cbind, lapply(simulated_css, function(cas_df) {
    # Get weight_median_css for corresponding county_weight
    weight_df <- cas_df %>% distinct(weight, weight_median_css)
    weight_df$weight_median_css[match(county_weight, weight_df$weight)]
  }))
})

css_sensitivity_httk <- lapply(age.by.county, function(county_age) {
  # TODO why round the median?
  median_county_age <- round(median(county_age))
  do.call(cbind, lapply(simulated_css, function(cas_df) {
    # Sample from "Normal" weight css values
    css <- cas_df %>%
      filter(
        weight == "Normal",
        median_county_age >= age_min
      ) %>%
      slice_tail(n = 1) %>%
      pull(css) %>% unlist()
    sample(css, length(county_age), replace = TRUE)
  }))
})

# TODO setNames to county FIPS for css_sensitivity_*

#===============================================================================
# Compare to GeoToxMIE
#===============================================================================

# modify lines 134-136 from "ncol = 41" to "ncol = length(in.chems)"
# modify line 159 from "j in 1:41" to "j in 1:length(in.chem)"

set.seed(2345)

MC.iter <- MC_iter
in.chems <- in_chems

# Run lines 37-60, 66-120

all.equal(
  css.list,
  lapply(
    lapply(simulated_css, "[[", "css"),
    function(css) do.call(cbind, css)
  )
)

# Run lines 128-200

all.equal(
  css.sensitivity.age,
  css_sensitivity_age,
  check.attributes = FALSE
)

all.equal(
  css.sensitivity.obesity,
  css_sensitivity_obesity,
  check.attributes = FALSE
)

all.equal(
  css.sensitivity.httk,
  css_sensitivity_httk,
  check.attributes = FALSE
)

################################################################################
################################################################################
# [01-05]-Sensitivity.R
################################################################################
################################################################################

rm(list = ls())
load_all()

set.seed(2345)

MC_iter <- 10 # Max 1000 when using pre-generated C_ss values

step <- 1 # vary age
# step <- 2 # vary obesity
# step <- 3 # vary httk
# step <- 4 # vary dose-response params
# step <- 5 # vary external concentration

##########
# Data
load("~/dev/GeoTox/data/county_cyp1a1_up_20220201.RData")
age.data <- read.csv("~/dev/GeoTox/data/cc-est2019-alldata.csv")
if (step == 1) {
  load("~/dev/GeoTox/data/css_by_county_sensitivity_age_20220228.RData")
  css.sensitivity.age <- lapply(css.sensitivity.age, function(mat) mat[1:MC_iter, ])
  C_ss <- css.sensitivity.age
} else if (step == 2) {
  load("~/dev/GeoTox/data/css_by_county_sensitivity_obesity_20220228.RData")
  css.sensitivity.obesity <- lapply(css.sensitivity.obesity, function(mat) mat[1:MC_iter, ])
  C_ss <- css.sensitivity.obesity
} else if (step == 3) {
  load("~/dev/GeoTox/data/css_by_county_sensitivity_httk_20220228.RData")
  css.sensitivity.httk <- lapply(css.sensitivity.httk, function(mat) mat[1:MC_iter, ])
  C_ss <- css.sensitivity.httk
} else if (step == 4 | step == 5) {
  # TODO 04 uses 20220201, 05 uses 20220228
  if (step == 4) {
    load("~/dev/GeoTox/data/css_by_county_20220201.RData")
  } else {
    load("~/dev/GeoTox/data/css_by_county_20220228.RData")
  }
  # Replace missing values with mean
  for (i in 1:length(css.by.county)) {
    for (j in 1:ncol(css.by.county[[i]])) {
      idx <- is.na(css.by.county[[i]][, j])
      if (any(idx)) {
        css.by.county[[i]][idx, j] <- mean(css.by.county[[i]][!idx, j])
      }
    }
  }
  # Use median values
  # TODO why mean-impute then use median?
  #      why not just use median of non-NA values?
  C_ss <- lapply(
    css.by.county,
    function(x) rep(median(x), length.out = MC_iter)
  )
}

# Filter age to desired year
age <- age.data %>%
  filter(YEAR == 7) %>% # 7/1/2014 Census population
  mutate(FIPS = as.numeric(sprintf("%d%03d", STATE, COUNTY))) %>%
  select(FIPS, AGEGRP, TOT_POP) %>%
  # Update FIPS: https://www.ddorn.net/data/FIPS_County_Code_Changes.pdf
  mutate(FIPS = if_else(FIPS == 46102, 46113, FIPS)) %>%
  filter(FIPS %in% unique(.env$county_cyp1a1_up$FIPS))

# Span of 6 FIPS in census.age.overlap ("age" in this script) are out of order
plot(unique(age$FIPS)[2378:2385])
# These are later multiplied by css.sensitivity.age
# order of css.sensitivity.age?
# load("~/dev/GeoTox/data/css_by_county_sensitivity_age_20220228.RData")
# same as order of age.by.county?
# load("~/dev/GeoTox/data/age_by_county_20220228.RData")
# unsure where age.by.county comes from, but maybe same FIPS order as census.age.overlap?

########################################
# cyp1a1
cyp1a1 <- split(county_cyp1a1_up, ~FIPS)

########################################
# age
age_split <- split(age, ~FIPS)

# Adjust order due to changing FIPS 46102 to 46113
# TODO does this adjustment line up with other input data, e.g. C_ss?
idx <- 1:length(age_split)
idx[2379:2384] <- c(2384, 2379:2383)
age_split <- age_split[idx]

# Simulate ages
simulated_age <- lapply(age_split, simulate_age, n = MC_iter)
if (step != 1) {
  simulated_age <- lapply(
    simulated_age,
    function(x) rep(median(x), length.out = MC_iter)
  )
}

########################################
# inhalation rate
simulated_IR <- lapply(simulated_age, simulate_inhalation_rate)

########################################
# exposure
if (step != 5) {
  simulated_exposure <- lapply(
    lapply(cyp1a1, "[[", "concentration_mean"),
    simulate_exposure,
    n = MC_iter
  )
} else {
  simulated_exposure <- mapply(
    simulate_exposure,
    mean = lapply(cyp1a1, "[[", "concentration_mean"),
    sd = lapply(cyp1a1, "[[", "concentration_sd"),
    n = MC_iter,
    SIMPLIFY = FALSE
  )
}

########################################
# internal dose
internal_dose <- mapply(
  calc_internal_dose,
  C_ext = lapply(simulated_exposure, function(x) x / 1000),
  IR = simulated_IR,
  SIMPLIFY = FALSE
)

########################################
# in vitro concentration
invitro_concentration <- mapply(
  calc_invitro_concentration,
  D_int = internal_dose,
  C_ss = C_ss,
  SIMPLIFY = FALSE
)

########################################
# concentration response
concentration_response <- mapply(
  calc_concentration_response,
  resp = cyp1a1,
  concentration = invitro_concentration,
  tp_b_mult = ifelse(step == 4, 1.2, 1.5),
  fixed = step != 4,
  SIMPLIFY = FALSE
)

# saveRDS(
#   concentration_response,
#   paste0("~/dev/GeoTox/outputs/conc_resp_", step, ".rds")
# )

# TODO correction of age carried to simulated_IR, but others are original order
idx <- 2379:2384
as.data.frame(cbind(
  "cyp1a1" = names(cyp1a1)[idx],
  "sim_age" = names(simulated_age)[idx],
  "sim_IR" = names(simulated_IR)[idx],
  "sim_exposure" = names(simulated_exposure)[idx],
  "internal_dose" = names(internal_dose)[idx],
  "invitro_conc" = names(invitro_concentration)[idx],
  "conc_resp" = names(concentration_response)[idx]
))

#===============================================================================
# Compare to GeoToxMIE
#===============================================================================

library(truncnorm)
source("~/github/GeoToxMIE/helper_functions/census-age-sim.R")
source("~/github/GeoToxMIE/helper_functions/sim-IR-BW.R")
source("~/github/GeoToxMIE/helper_functions/GCA-obj.R")
source("~/github/GeoToxMIE/helper_functions/tcplHillConc_v2.R")
source("~/github/GeoToxMIE/helper_functions/IA-Pred.R")
source("~/github/GeoToxMIE/helper_functions/tcplHillVal_v2.R")
source("~/github/GeoToxMIE/helper_functions/ECmix-obj.R")

set.seed(2345)

MC.iter <- MC_iter

########################################
# cyp1a1

# Run lines
# 01: 51
# 02: 45
# 03: 43
# 04: 44
# 05: 42

all.equal(cyp1a1_up.by.county, cyp1a1)

########################################
# age

# Run lines
# 01: 59-75
# 02: 53-72
# 03: 48-67
# 04: 49-68
# 05: 47-66

if (step != 1) {
  age.by.county <- age.by.county.median
}

all.equal(census.age.overlap, age)
all.equal(age.by.county, simulated_age)

########################################
# inhalation rate

# Run lines
# 01: 82
# 02: 76
# 03: 71
# 04: 72
# 05: 70

all.equal(IR.by.county, simulated_IR)

# Note for steps with fixed age
# only index 2384 (FIPS 46113) has median ages in different IR age groups
if (step != 1) {
  cbind(
    sapply(age.by.county.median[2379:2384], "[", 1),
    sapply(simulated_age[2379:2384], "[", 1)
  )
}

########################################
# exposure

# Run lines
# 01: 88-128
# 02: 80-119
# 03: 76-115
# 04: 77-116
# 05: 75-114

all.equal(external.dose.by.county, simulated_exposure)

########################################
# internal dose

# Run lines
# 01: 130-135
# 02: 121-126
# 03: 118-123
# 04: 119-124
# 05: 117-122

all.equal(inhalation.dose.by.county, internal_dose)

########################################
# in vitro concentration

if (step == 4 | step == 5) {
  css.by.county.median <- C_ss
}

# Run lines
# 01: 145-151
# 02: 136-142
# 03: 134-140
# 04: 152-158
# 05: 150-156

all.equal(invitro.conc.by.county, invitro_concentration)

########################################
# concentration response

# Run lines
# 01: 154-246
# 02: 148-239
# 03: 145-236
# 04: 163-257
# 05: 161-255

all.equal(final.response.by.county, concentration_response)

################################################################################
################################################################################
# 06-Sensitivity.R
################################################################################
################################################################################

library(ggridges)
library(ggpubr)

rm(list = ls())

##########
# Data
if (FALSE) {

  MC_iter <- 50
  n_county <- 20

  load("~/dev/GeoTox/data/sensitivity_results_age_20220901.RData")
  sensitivity.age <- final.response.by.county
  load("~/dev/GeoTox/data/sensitivity_results_obesity_20220901.RData")
  sensitivity.obesity <- final.response.by.county
  load("~/dev/GeoTox/data/sensitivity_results_httk_20220901.RData")
  sensitivity.httk <- final.response.by.county
  load("~/dev/GeoTox/data/sensitivity_results_conc_resp_20220901.RData")
  sensitivity.conc.resp <- final.response.by.county
  load("~/dev/GeoTox/data/sensitivity_results_ext_conc_20220901.RData")
  sensitivity.ext.conc <- final.response.by.county
  load("~/dev/GeoTox/data/final_response_by_county_20220901.RData")
  baseline <- final.response.by.county

  rm(final.response.by.county)

  get_subset <- function(x) {
    lapply(x[1:n_county], \(df) df[1:MC_iter, ])
  }

  sensitivity.age       <- get_subset(sensitivity.age)
  sensitivity.obesity   <- get_subset(sensitivity.obesity)
  sensitivity.httk      <- get_subset(sensitivity.httk)
  sensitivity.conc.resp <- get_subset(sensitivity.conc.resp)
  sensitivity.ext.conc  <- get_subset(sensitivity.ext.conc)
  baseline              <- get_subset(baseline)

  save(
    MC_iter,
    n_county,
    sensitivity.age,
    sensitivity.obesity,
    sensitivity.httk,
    sensitivity.conc.resp,
    sensitivity.ext.conc,
    baseline,
    file = "~/dev/GeoTox/outputs/sensitivity.RData"
  )
} else {
  load("~/dev/GeoTox/outputs/sensitivity.RData")
}

########################################
# Create useful functions

gather_results <- function(param) {
  baseline_param <- switch(
    param,
    "GCA.Eff"  = "GCA",
    "IA.eff"   = "IA",
    "IA.HQ.10" = "HQ.10"
  )
  colnames <- c(
    "External Concentration",
    "Toxicokinetic Parameters",
    "Obesity",
    "Age",
    "Concentration-Response",
    "Baseline"
  )
  out <- cbind(
    unlist(lapply(sensitivity.ext.conc, "[[", param)),
    unlist(lapply(sensitivity.httk, "[[", param)),
    unlist(lapply(sensitivity.obesity, "[[", param)),
    unlist(lapply(sensitivity.age, "[[", param)),
    unlist(lapply(sensitivity.conc.resp, "[[", param)),
    unlist(lapply(baseline, "[[", baseline_param))
  )
  colnames(out) <- colnames
  as.data.frame(out) %>%
    pivot_longer(cols = everything()) %>%
    mutate(name = factor(name, levels = colnames))
}

plot_gathered_results <- function(df, xlab = "", ylab = "", scale_x = TRUE) {
  p <- df %>%
    ggplot(aes(x = value, y = name, fill = name)) +
    stat_density_ridges(
      geom = "density_ridges_gradient",
      calc_ecdf = TRUE,
      quantiles = 4,
      quantile_lines = FALSE
    ) +
    scale_fill_viridis_d(option = "C") +
    theme(legend.position = "none") +
    xlab(xlab) +
    ylab(ylab) +
    theme_minimal() +
    coord_cartesian(clip = "off") +
    theme(
      text = element_text(size = 14),
      legend.position="none",
      axis.text = element_text(size = 14),
      axis.title = element_text(size = 14)
    )
  if (scale_x) {
    p + scale_x_log10(labels = scales::label_math(10^.x, format = log10))
  } else {
    p
  }
}

plot_gathered_results2 <- function(df, y = "y", xlab = "", ylab = "") {
  df %>%
    ggplot(aes(x = value, y = .env$y, fill = NA, color = name)) +
    stat_density_ridges(
      calc_ecdf = TRUE,
      quantiles = 4,
      quantile_lines = FALSE,
      fill = NA,
      linewidth = 1
    ) +
    scale_x_log10(labels = scales::label_math(10^.x, format = log10)) +
    scale_color_brewer(palette="Set2") +
    theme(legend.position = "none") +
    xlab(xlab) +
    ylab(ylab) +
    labs(color = 'Varying Parameter') +
    theme_minimal() +
    coord_cartesian(clip = "off") +
    theme(
      text = element_text(size = 14),
      axis.text = element_text(size = 14),
      axis.title = element_text(size = 14)
    )
}

########################################
# First set of plots

df1 <- gather_results("GCA.Eff")
p1 <- plot_gathered_results(
  df1,
  xlab = paste(
    "Z-score of Median Predicted Log2 Fold",
    "Change mRNA Expression CYP1A1",
    sep = "\n"
  ),
  ylab = "Varying Parameter"
)

df2 <- gather_results("IA.eff")
p2 <- plot_gathered_results(
  df2,
  xlab = paste(
    "Z-score of Median Predicted Log2 Fold",
    "Change mRNA Expression CYP1A1",
    sep = "\n"
  )
) + theme(axis.text.y = element_blank())

df3 <- gather_results("IA.HQ.10")
p3 <- plot_gathered_results(
  df3,
  xlab = paste(
    "Meidan CYP1A1",
    "Summed Risk Quotient",
    sep = "\n"
  ),
  scale_x = FALSE
) + theme(axis.text.y = element_blank())

p1to3 <- ggarrange(
  p1, p2, p3,
  labels = c( "A", "B", "C"),
  vjust = 1,
  align = "h",
  ncol = 3, nrow = 1,
  widths = c(1, 0.5, 0.5),
  font.label = list(size = 20, color = "black", face = "bold"),
  common.legend = FALSE
)

########################################
# Second set of plots

p4 <- plot_gathered_results2(
  df2,
  y = "CA/IA",
  xlab = paste(
    "Median Predicted Log2 Fold Change",
    "mRNA Expression CYP1A1",
    sep = "\n"
  )
)

p5 <- plot_gathered_results2(
  df3,
  y = "RQ",
  xlab = paste(
    "Median CYP1A1",
    "Summed Risk Quotient",
    sep = "\n"
  )
)

p4to5 <- ggarrange(
  p4, p5,
  labels = c("A", "B"),
  vjust = 1,
  align = "h",
  ncol = 2, nrow = 1,
  widths = c(0.5, 0.5),
  font.label = list(size = 20, color = "black", face = "bold"),
  common.legend = TRUE,
  legend = "right"
)

#===============================================================================
# Compare to GeoToxMIE
#===============================================================================

library(reshape2)

# Change scale_x_log10
# comment out:
# scale_x_log10(labels = trans_format("log10", math_format(10^.x)))+
# add line:
# scale_x_log10(labels = scales::label_math(10^.x, format = log10)) +
#
# Comment out any lines referencing "$X2"

# Run lines 32-173

compare_gathered_data <- function(df_orig, df_new) {
  all.equal(
    df_orig %>%
      mutate(name = as.character(Var2), value) %>%
      select(name, value) %>%
      arrange(name, value),
    df_new %>%
      mutate(name = as.character(name), value) %>%
      arrange(name, value),
    check.attributes = FALSE
  )
}

compare_gathered_data(CR.melt, df1)
compare_gathered_data(CR.IA.melt, df2)
compare_gathered_data(HQ.IA.melt, df3)

pdf("~/dev/GeoTox/outputs/temp1.1.pdf"); conc.resp.plot.GCA; invisible(dev.off())
pdf("~/dev/GeoTox/outputs/temp1.2.pdf"); p1; invisible(dev.off())

pdf("~/dev/GeoTox/outputs/temp2.1.pdf"); conc.resp.plot.IA; invisible(dev.off())
pdf("~/dev/GeoTox/outputs/temp2.2.pdf"); p2; invisible(dev.off())

pdf("~/dev/GeoTox/outputs/temp3.1.pdf"); HQ.plot.IA; invisible(dev.off())
pdf("~/dev/GeoTox/outputs/temp3.2.pdf"); p3; invisible(dev.off())

pdf("~/dev/GeoTox/outputs/temp4.1.pdf"); composite; invisible(dev.off())
pdf("~/dev/GeoTox/outputs/temp4.2.pdf"); p1to3; invisible(dev.off())

# Run lines 180-245

pdf("~/dev/GeoTox/outputs/temp5.1.pdf"); combined_plot; invisible(dev.off())
pdf("~/dev/GeoTox/outputs/temp5.2.pdf"); p4; invisible(dev.off())

pdf("~/dev/GeoTox/outputs/temp6.1.pdf"); HQ_plot; invisible(dev.off())
pdf("~/dev/GeoTox/outputs/temp6.2.pdf"); p5; invisible(dev.off())

pdf("~/dev/GeoTox/outputs/temp7.1.pdf"); composite2; invisible(dev.off())
pdf("~/dev/GeoTox/outputs/temp7.2.pdf"); p4to5; invisible(dev.off())
