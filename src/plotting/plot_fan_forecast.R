# plot_fan_forecast.R
#
# Fan plots: the forecast ensemble (median + percentile bands) against the true
# case trajectory, one panel per state. Built for the reviewer comment asking to
# *see* model output vs real cases.
#
# The default figure is the one the paper argues: columns = the four states, rows
# = the flights x commuting factorial, a single forecast lead. One fan per panel,
# with the observed trajectory repeated in every row as a fixed reference, so the
# effect of dropping flights or of patch-vs-network commuting is read down a column.
# Set FACET_ROWS/COLOR_BY to "lead" and give FORECAST_LEADS several values for the
# other view: one model, several horizons.
#
# Everything is aligned on the ONSET WEEK — the first week the observed series
# reaches ONSET_THRESHOLD weekly new cases per 100,000 — which is the target the
# paper forecasts throughout (100/100k for the synthetic truths, 50/100k for the
# reported data). Forecasts are selected by their lead relative to that week
#   lead = forecast_week - onset_week      (negative = issued before onset)
# which is the same sign convention as the "-8 to -6 / -5 to -3 / -2 to 0"
# windows in plot_rel_bars_real.R. Each fan stops at the onset week.
#
# Units are weekly NEW cases per 100,000 — the same transform every other
# metric in the repo uses (see src/forecast/make_forecast_metrics.m).
#
# Input : results/csv/fan_forecast_<dataset>.csv
#         results/csv/fan_truth_<dataset>.csv     (both written by export_fan_data.m)
# Output: results/figures/fan_<dataset>_<OUT_TAG>.{pdf,png}
#
# The onset week is derived here, from the truth CSV, so changing the threshold
# needs no MATLAB re-run.
#
#   Rscript src/plotting/plot_fan_forecast.R
#   ...or just source/step through it in RStudio; everything you need to change
#   is in the CONFIG block.

library(ggplot2)
library(dplyr)
library(scales)
library(viridis)

# ── PROJECT ROOT ─────────────────────────────────────────────────────────────
# Resolved from this script's own location, so it runs from any working
# directory (Rscript, source(), or line-by-line in RStudio).
# Set ROOT_OVERRIDE to skip the search, e.g.
#   ROOT_OVERRIDE <- "/Users/matteoperini/Library/CloudStorage/Box-Box/Matteo Perini/13_NA-returns/Model/NA_SEIR-EAKF_forecast"
ROOT_OVERRIDE <- ""

ROOT <- if (nzchar(ROOT_OVERRIDE)) ROOT_OVERRIDE else local({
  f <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  d <- if (length(f)) {
    # Rscript mangles spaces in the script path as "~+~"
    dirname(normalizePath(gsub("~\\+~", " ", sub("^--file=", "", f[1]))))
  } else if (!is.null(sys.frames()[[1]]$ofile)) {
    dirname(normalizePath(sys.frames()[[1]]$ofile))
  } else if (requireNamespace("rstudioapi", quietly = TRUE) && rstudioapi::isAvailable()) {
    dirname(normalizePath(rstudioapi::getSourceEditorContext()$path))
  } else {
    getwd()
  }
  while (!file.exists(file.path(d, "run_pipeline.m")) && dirname(d) != d) d <- dirname(d)
  if (!file.exists(file.path(d, "run_pipeline.m")))
    stop("Could not find the project root (run_pipeline.m). Set ROOT_OVERRIDE.")
  d
})

# ══════════════════════════════════════════════════════════════════════════════
# 0. CONFIG — everything below this block is machinery
# ══════════════════════════════════════════════════════════════════════════════

DATASET <- "real"          # "real" (reported COVID-19) or "synth" (synthetic truths)
OUT_TAG <- "reviewer"      # goes into the output filename

# --- input / output paths ----------------------------------------------------
FORECAST_CSV <- file.path(ROOT, "results", "csv", paste0("fan_forecast_", DATASET, ".csv"))
TRUTH_CSV    <- file.path(ROOT, "results", "csv", paste0("fan_truth_",    DATASET, ".csv"))
OUT_PDF      <- file.path(ROOT, "results", "figures",
                          paste0("fan_", DATASET, "_", OUT_TAG, ".pdf"))
OUT_PNG      <- file.path(ROOT, "results", "figures",
                          paste0("fan_", DATASET, "_", OUT_TAG, ".png"))

# --- which states (row index into data/statecodes.csv), in panel order --------
# New York is exported too ("55" = "New York (US)") but left out by default: it is
# where the real epidemic started, so its own onset gives the model almost nothing
# to assimilate first, and the full model overshoots it hardest.
STATES <- c(
  "84" = "Texas (US)",
  "10" = "California (US)",
  "66" = "Ontario (CA)",
  "22" = "Estado de Mexico (MX)"
)

# --- onset alignment ---------------------------------------------------------
# Onset week = first week the truth reaches this many weekly new cases per 100k.
# Computed per state, and per truth for the synthetic runs.
ONSET_THRESHOLD <- if (DATASET == "real") 50 else 100

# Which forecasts to draw, by lead relative to that onset week.
# One lead keeps the configuration contrast clean; give it several (e.g. c(-8, -2))
# and they are drawn together, coloured by lead.
# Not every lead exists everywhere: forecasting starts at week 2, so a state whose
# onset is at week 4 has no forecast at lead -8. Missing combinations are listed
# on the console rather than silently dropped.
FORECAST_LEADS <- c(-8, -4)

TRUNCATE_AT_ONSET <- TRUE   # fans stop at the onset week (the forecast target)
WEEKS_PAST_ONSET  <- 0      # ...or run this many weeks past it
SHOW_ONSET_LINE   <- TRUE   # vertical rule at the onset week, one per panel

# --- which model configurations ----------------------------------------------
# The flights x commuting factorial the paper is about, as <flights>_<commuting>:
#   f_n  flights + network commuting   (the full model)
#   nf_n no flights + network commuting
#   f_p  flights + patch commuting
#   nf_p no flights + patch commuting
# Same four for real and synthetic; NULL = everything in the CSV.
CONFIGS <- c("f_n", "nf_n", "f_p", "nf_p")
STOCH   <- "pois"    # "pois" or "det"

# --- which truths ------------------------------------------------------------
# Synthetic only: which strains (force of infection). NULL = all in the CSV.
# One strain when the panels are configurations. "lo" (beta = 1) is the pick:
# seeded in GA its onset lands at week 15-16 in all four states, so a -6 or -8
# lead actually exists. me/hi/hs onset at weeks 6-8 and cap the usable lead at
# about -4; ls (beta = 0.8) has lead to spare but is so slow that every
# configuration forecasts it well, so it does not discriminate.
STRAINS <- "lo"

# Synthetic only: seeding state of the truth. NULL = all in the CSV.
# Keep this OFF the four plotted states — a truth seeded in a state you also plot puts
# that state's onset at week 2, leaving no lead time to forecast it. Both NY and GA
# satisfy that now that New York is not plotted, and they perform about equally for
# the full model; NY is the default because the four configurations separate more
# under it (spread in median error at lead -8: 1.39 for NY against 0.85 for GA).
SEED_LOCS <- "NY"

# --- layout ------------------------------------------------------------------
# Panels are always states in columns. FACET_ROWS adds a second dimension.
FACET_ROWS   <- "config"         # "none" | "config" | "strain" | "lead" | "run"
COLOR_BY     <- if (length(FORECAST_LEADS) > 1) "lead" else "config"
                                 # "config" | "lead" | "strain" | "run"
LINETYPE_BY  <- "none"           # "none" | "config" | "lead" | "run"
PANEL_SCALES <- "fixed"          # "fixed"     one y scale everywhere
                                 # "free_y"    one y scale per facet ROW
                                 # "free_each" one y scale per PANEL (needs the
                                 #             ggh4x package; falls back to free_y)
# Keep this "fixed" whenever the ROWS are the thing being compared: "free_y" gives
# each row its own y scale, which is precisely what you must not do when the point
# is to compare configurations down a column. "free_y" is right when the rows are
# strains or leads, whose magnitudes genuinely differ.

# --- band --------------------------------------------------------------------
BAND_OUTER      <- c("q05", "q95")   # 5th-95th percentile of the 150-member ensemble
BAND_INNER      <- c("q25", "q75")   # set to NULL for a single band
CENTRAL_LINE    <- "q50"             # "q50" (median) or "mean".
                                     # The ensemble is strongly right-skewed - a few
                                     # members blow up while the bulk decays - so the
                                     # mean often sits ABOVE the 95th percentile and
                                     # reads as a plotting bug. The median does not.
DROP_PRE_FORECAST <- FALSE           # TRUE = start each fan exactly at forecast_week.
                                     # FALSE keeps one observed week so the fan attaches
                                     # to the truth line. Careful: that observed week is
                                     # the 7-day smoothed series the filter assimilates,
                                     # so it sits slightly off the raw weekly truth.

# --- axes / scales -----------------------------------------------------------
X_AXIS <- "onset_rel"    # "onset_rel" weeks from onset, every panel aligned at 0
                         # "week"      absolute epidemiological week
                         # "date"      calendar date (real runs only)
X_LIMITS <- if (X_AXIS == "onset_rel") c(-14, 12) else NULL
CROP_DATA_TO_X <- TRUE   # TRUE  drop data outside X_LIMITS, so the y scale fits the
                         #       window (the truth's later peak stops dominating it)
                         # FALSE keep it and just zoom
Y_LOG   <- TRUE          # log10 y. Recommended: the pre-onset run-up spans orders of
                         # magnitude, and the early forecasts overshoot by ~2 more.
Y_FLOOR <- 0.5           # zeros are clamped to this before taking the log
DATE_BREAKS <- "4 months"

# --- cosmetics ---------------------------------------------------------------
RIBBON_ALPHA_OUTER <- 0.20
RIBBON_ALPHA_INNER <- 0.32
LINE_WIDTH_FORECAST <- 1.0
LINE_WIDTH_TRUTH    <- 1.1
TRUTH_COLOUR        <- "black"   # "black", any colour, or "match" to colour the
                                 # truth by strain (only sensible when COLOR_BY="strain")
ONSET_LINE_COLOUR   <- "grey30"
ONSET_LINE_TYPE     <- "dashed"
ONSET_LINE_WIDTH    <- 0.7
STRIP_FILL          <- "white"   # facet strip background; "grey93" for the shaded look
BASE_TEXT_SIZE <- 18
PDF_WIDTH      <- 20
PDF_HEIGHT     <- NULL   # NULL = 3.6 in per facet row + 2; or set a number

# ══════════════════════════════════════════════════════════════════════════════
# 1. PALETTES  (kept in the family of src/plotting/plot_rel_bars_*.R)
# ══════════════════════════════════════════════════════════════════════════════

# plot_rel_bars_synth.R
strain_levels <- c("ls", "lo", "me", "hi", "hs")
strain_colors <- c(
  ls = rgb(144, 103, 167, maxColorValue = 255),
  lo = rgb(114, 147, 203, maxColorValue = 255),
  me = rgb(132, 186,  91, maxColorValue = 255),
  hi = rgb(237, 177,  32, maxColorValue = 255),
  hs = rgb(211,  94,  96, maxColorValue = 255)
)
strain_labels <- c(ls = "beta==0.8", lo = "beta==1", me = "beta==2",
                   hi = "beta==3",   hs = "beta==4")

# plot_rel_bars_real.R uses "nf" = the same colour darkened by 0.30
shade_adjust <- 0.30
darken_hex <- function(hex, amount) {
  v <- col2rgb(hex) / 255
  v <- pmax(v - amount, 0)
  rgb(v[1], v[2], v[3])
}

LEAD_PALETTE <- "contrast"  # "contrast" slate then brick — a blue/red pair with a large
                            #            hue separation, so two overlapping translucent
                            #            fans stay legible, and far enough from both the
                            #            strain reds and the window ambers to not be read
                            #            against them. Similar lightness, so neither fan
                            #            visually dominates the other.
                            # "slate"    shades of one slate: subtle, only worth it for
                            #            many leads where hues would run out
                            # "horizon"  amber + viridis 0.60-0.92, the same colours
                            #            plot_rel_bars_real.R gives its time windows
lead_contrast <- c("#3C5A73", "#B4442E", "#4E7A5A", "#8A6BA1")  # slate, brick, moss, plum
lead_palette <- function(n) {
  switch(LEAD_PALETTE,
    horizon = if (n <= 1) "#E69F00"
              else c("#E69F00", viridis::viridis(n - 1, begin = 0.6, end = 0.92)),
    slate   = if (n <= 1) config_slate
              else colorRampPalette(c("#16283A", "#93B2C8"))(n),   # earliest = darkest
    if (n <= length(lead_contrast)) lead_contrast[seq_len(n)]
    else colorRampPalette(lead_contrast)(n)
  )
}

# The seven states a synthetic truth can be seeded in, and their statecodes row
seed_names <- c(NY = "New York", WA = "Washington", CA = "California", TX = "Texas",
                GA = "Georgia",  ON = "Ontario",    MX = "Estado de Mexico")
seed_rows  <- c(NY = 55, WA = 90, CA = 10, TX = 84, GA = 24, ON = 66, MX = 22)

run_labels <- c(
  "601" = "no flights, network",
  "602" = "flights, network",
  "603" = "no flights, patch",
  "604" = "flights, patch"
)

# flights x commuting.
# Deliberately OUTSIDE the two palettes above: strain (purple/blue/green/amber/red)
# and lead (amber + viridis) already carry meaning in the other paper figures, and
# reusing either hue here would imply a link that does not exist. This is a single
# neutral slate instead. Configurations never share a panel with strains or leads,
# so no information is lost.
config_levels <- c("f_n", "nf_n", "f_p", "nf_p")
config_labels <- c(
  f_n  = "flights + network  (full model)",
  nf_n = "no flights + network",
  f_p  = "flights + patch",
  nf_p = "no flights + patch"
)

CONFIG_PALETTE <- "mono"   # "mono"   one slate for all four - the row strip already
                           #          names the configuration, so colour is redundant
                           #          and a flat colour reads as "same model family"
                           # "shades" four steps of that slate, for when you overlay
                           #          configurations in one panel
config_slate <- "#3C5A73"
config_colors <- if (CONFIG_PALETTE == "shades") {
  setNames(colorRampPalette(c("#22384A", "#8FAEC6"))(4), config_levels)
} else {
  setNames(rep(config_slate, 4), config_levels)
}

# ══════════════════════════════════════════════════════════════════════════════
# 2. LOAD, FIND THE ONSET, FILTER
# ══════════════════════════════════════════════════════════════════════════════

for (f in c(FORECAST_CSV, TRUTH_CSV))
  if (!file.exists(f)) stop("Missing input: ", f, "\nRun src/plotting/export_fan_data.m first.")

fc <- read.csv(FORECAST_CSV, stringsAsFactors = FALSE)
tr <- read.csv(TRUTH_CSV,    stringsAsFactors = FALSE)

fc$run_num <- sprintf("%03d", as.integer(fc$run_num))
state_rows <- as.integer(names(STATES))

fc <- fc %>% filter(loc_row %in% state_rows)
tr <- tr %>% filter(loc_row %in% state_rows)

# flights x commuting, the axis the figure contrasts
fc$config <- paste(fc$flights, fc$commuting, sep = "_")

if (!is.null(STOCH))   fc <- fc %>% filter(stoch %in% STOCH)
if (!is.null(CONFIGS)) {
  fc <- fc %>% filter(config %in% CONFIGS)
  absent <- setdiff(CONFIGS, unique(fc$config))
  if (length(absent))
    message("Not in the CSV, so not drawn: ", paste(absent, collapse = ", "),
            " — re-export with them in P.synth_configs / P.real_runs.")
}
fc$config <- factor(fc$config, levels = config_levels[config_levels %in% fc$config])

if (!is.null(STRAINS) && DATASET == "synth") {
  fc <- fc %>% filter(strain %in% STRAINS)
  tr <- tr %>% filter(strain %in% STRAINS)
}
if (!is.null(SEED_LOCS) && DATASET == "synth") {
  fc <- fc %>% filter(seed_loc %in% SEED_LOCS)
  tr <- tr %>% filter(seed_loc %in% SEED_LOCS)
  if (!nrow(fc)) stop("No runs seeded in ", paste(SEED_LOCS, collapse = "/"),
                      " — re-export with that seed in P.synth_seed_locs.")
}

# --- onset week per truth x state --------------------------------------------
onset <- tr %>%
  group_by(truth_id, loc_row) %>%
  summarise(onset_week = if (any(truth_100k >= ONSET_THRESHOLD))
                           min(week[truth_100k >= ONSET_THRESHOLD]) else NA_integer_,
            .groups = "drop")

if (all(is.na(onset$onset_week)))
  stop("No state ever reaches ", ONSET_THRESHOLD, " per 100k — lower ONSET_THRESHOLD.")

cat(sprintf("Onset = first week the truth reaches %d per 100k\n", ONSET_THRESHOLD))
print(as.data.frame(
  onset %>%
    left_join(tr %>% distinct(truth_id, loc_row, loc_name, nick), by = c("truth_id", "loc_row")) %>%
    select(truth = nick, state = loc_name, onset_week) %>%
    arrange(truth, state)
), row.names = FALSE)

fc <- fc %>% left_join(onset, by = c("truth_id", "loc_row")) %>%
             mutate(lead = forecast_week - onset_week)
tr <- tr %>% left_join(onset, by = c("truth_id", "loc_row"))

# --- keep only the requested leads -------------------------------------------
asked <- fc %>% distinct(nickname, truth_id, loc_row, loc_name, onset_week)
asked <- do.call(rbind, lapply(FORECAST_LEADS, function(L) { asked$lead <- L; asked }))

fc <- fc %>% filter(!is.na(lead), lead %in% FORECAST_LEADS)

missing <- asked %>%
  anti_join(fc %>% distinct(nickname, loc_row, lead), by = c("nickname", "loc_row", "lead"))
if (nrow(missing)) {
  cat("\nNo forecast at these lead / state combinations",
      "(forecasting starts at week 2, so leads earlier than 2 - onset_week do not exist):\n")
  print(as.data.frame(missing %>% select(run = nickname, state = loc_name, onset_week, lead) %>%
                        arrange(run, state, lead)), row.names = FALSE)
}

if (!nrow(fc)) stop("No forecast rows left — check FORECAST_LEADS / ONSET_THRESHOLD / RUNS.")

# --- trim each fan at the onset week -----------------------------------------
if (TRUNCATE_AT_ONSET) fc <- fc %>% filter(week <= onset_week + WEEKS_PAST_ONSET)
if (DROP_PRE_FORECAST) fc <- fc %>% filter(is_forecast == 1)

# state panels, in the order given by STATES. For the synthetic runs, say which
# truth we are looking at: the strain and the state the epidemic was seeded in.
# If that seeded state is itself one of the panels, flag it — its epidemic does not
# arrive from elsewhere, so the model has nothing to import and its onset is early.
seed_codes <- if (DATASET == "synth") sort(unique(as.character(fc$seed_loc))) else character(0)

STATE_LABELS <- STATES
if (length(seed_codes)) {
  seeded <- as.character(seed_rows[seed_codes])
  hit <- names(STATE_LABELS) %in% seeded
  STATE_LABELS[hit] <- paste0(STATE_LABELS[hit], "  [seeded]")
}

truth_note <- if (length(seed_codes)) {
  sprintf("\nsynthetic truth: beta = %s, seeded in %s",
          paste(sort(unique(fc$beta)), collapse = " / "),
          paste(ifelse(seed_codes %in% names(seed_names),
                       sprintf("%s (%s)", seed_names[seed_codes], seed_codes), seed_codes),
                collapse = " / "))
} else ""

state_lab <- function(d) factor(STATE_LABELS[as.character(d$loc_row)],
                                levels = unname(STATE_LABELS))
fc$state <- state_lab(fc)
tr$state <- state_lab(tr)

# --- x variable ---------------------------------------------------------------
# export_fan_data.m writes ISO dates; older exports used MATLAB's dd-MMM-yyyy.
parse_week_date <- function(v) {
  v <- ifelse(v %in% c("", "NaT", "NA"), NA_character_, as.character(v))
  d <- tryCatch(as.Date(v), error = function(e) rep(as.Date(NA), length(v)))
  if (all(is.na(d)) && any(!is.na(v)))
    d <- suppressWarnings(as.Date(v, format = "%d-%b-%Y"))
  d
}

if (X_AXIS == "date") {
  fc$x <- parse_week_date(fc$week_date)
  tr$x <- parse_week_date(tr$week_date)
  if (all(is.na(fc$x)))
    stop('X_AXIS = "date" but the CSV has no dates (synthetic runs have none).')
} else if (X_AXIS == "onset_rel") {
  fc$x <- fc$week - fc$onset_week
  tr$x <- tr$week - tr$onset_week
} else {
  fc$x <- fc$week
  tr$x <- tr$week
}
tr <- tr %>% filter(!is.na(x))

# Cropping (rather than zooming) lets the y scale fit the plotted window.
if (!is.null(X_LIMITS) && CROP_DATA_TO_X) {
  pad <- if (inherits(fc$x, "Date")) 7 else 1
  lo  <- X_LIMITS[1] - pad
  hi  <- X_LIMITS[2] + pad
  fc  <- fc %>% filter(x >= lo, x <= hi)
  tr  <- tr %>% filter(x >= lo, x <= hi)
}

# one drawn fan = one run x one lead x one state
fc$fan_id <- paste(fc$run_num, fc$forecast_week, fc$loc_row, sep = "|")

# ══════════════════════════════════════════════════════════════════════════════
# 3. AESTHETIC KEYS
# ══════════════════════════════════════════════════════════════════════════════

# option name -> column name in the CSV
col_of <- function(key) switch(key, run = "run_num", key)
key_title <- function(key) switch(key,
  run = "Model run", config = "Model", lead = "Weeks from onset",
  strain = "Strain", key)

lead_lab <- function(v) sprintf("%+d", v)

# --- colour ------------------------------------------------------------------
if (COLOR_BY == "config") {
  lv <- levels(droplevels(fc$config))
  fc$col_key <- factor(fc$config, levels = lv)
  col_values <- config_colors[lv]
  col_labels <- setNames(config_labels[lv], lv)
  col_title  <- "Model"

} else if (COLOR_BY == "lead") {
  lv <- sort(unique(fc$lead))
  fc$col_key <- factor(fc$lead, levels = lv)
  col_values <- setNames(lead_palette(length(lv)), lv)
  col_labels <- setNames(lead_lab(lv), lv)
  col_title  <- "Weeks from onset"

} else if (COLOR_BY == "strain") {
  lv <- strain_levels[strain_levels %in% unique(fc$strain)]
  fc$col_key <- factor(fc$strain, levels = lv)
  col_values <- strain_colors[lv]
  col_labels <- parse(text = strain_labels[lv])
  col_title  <- "Strain"

} else if (COLOR_BY == "run") {
  lv <- sort(unique(fc$run_num))
  base <- lead_palette(length(lv))
  # keep the plot_rel_bars convention: "no flights" is the darker shade
  fl <- fc$flights[match(lv, fc$run_num)]
  col_values <- setNames(ifelse(fl == "nf", mapply(darken_hex, base, shade_adjust), base), lv)
  fc$col_key <- factor(fc$run_num, levels = lv)
  col_labels <- setNames(ifelse(lv %in% names(run_labels),
                                paste0(lv, ": ", run_labels[lv]), lv), lv)
  col_title <- "Model run"

} else stop("COLOR_BY must be one of: config, lead, strain, run")

# --- linetype ----------------------------------------------------------------
lt_values <- NULL
if (LINETYPE_BY != "none") {
  lt_col <- col_of(LINETYPE_BY)
  lt_lv  <- sort(unique(fc[[lt_col]]))
  fc$lt_key  <- factor(fc[[lt_col]], levels = lt_lv)
  lt_values  <- setNames(rep(c("solid", "22", "42", "1343"), length.out = length(lt_lv)), lt_lv)
  lt_labels  <- switch(LINETYPE_BY,
                       lead   = lead_lab(lt_lv),
                       config = unname(config_labels[as.character(lt_lv)]),
                       as.character(lt_lv))
  lt_title   <- key_title(LINETYPE_BY)
} else {
  fc$lt_key <- factor("a")
}

# --- facet rows --------------------------------------------------------------
# The truth does not depend on run or lead, so it has to be repeated across
# those facet rows.
repeat_across <- function(d, labs_) {
  do.call(rbind, lapply(labs_, function(l) { d$row_key <- factor(l, levels = labs_); d }))
}

if (FACET_ROWS == "none") {
  fc$row_key <- factor("")
  tr$row_key <- factor("")
  facet_f <- . ~ state
  row_labeller <- ggplot2::label_value

} else if (FACET_ROWS == "strain") {
  lv <- strain_levels[strain_levels %in% unique(fc$strain)]
  fc$row_key <- factor(fc$strain, levels = lv, labels = strain_labels[lv])
  tr <- tr %>% filter(strain %in% lv)
  tr$row_key <- factor(tr$strain, levels = lv, labels = strain_labels[lv])
  facet_f <- row_key ~ state
  row_labeller <- ggplot2::label_parsed

} else if (FACET_ROWS %in% c("config", "run", "lead")) {
  row_col <- col_of(FACET_ROWS)
  lv <- if (FACET_ROWS == "config") levels(droplevels(fc$config))
        else sort(unique(fc[[row_col]]))
  labs_ <- switch(FACET_ROWS,
    config = unname(config_labels[lv]),
    run    = ifelse(lv %in% names(run_labels), paste0(lv, ": ", run_labels[lv]), lv),
    lead   = sprintf("%+d weeks from onset", lv))
  fc$row_key <- factor(fc[[row_col]], levels = lv, labels = labs_)
  tr <- repeat_across(tr, labs_)
  facet_f <- row_key ~ state
  row_labeller <- ggplot2::label_value

} else stop("FACET_ROWS must be one of: none, config, strain, lead, run")

# --- onset rules, one per panel ----------------------------------------------
# Taken from the truth, so it lands on the right x whatever X_AXIS is.
onset_lines <- tr %>%
  filter(week == onset_week) %>%
  distinct(row_key, state, x)

# ══════════════════════════════════════════════════════════════════════════════
# 4. BUILD THE PLOT
# ══════════════════════════════════════════════════════════════════════════════

y_of <- function(v) if (Y_LOG) pmax(v, Y_FLOOR) else v

p <- ggplot()

# --- onset rule (behind everything) ------------------------------------------
if (SHOW_ONSET_LINE && nrow(onset_lines)) {
  p <- p + geom_vline(data = onset_lines, aes(xintercept = x),
                      colour = ONSET_LINE_COLOUR, linetype = ONSET_LINE_TYPE,
                      linewidth = ONSET_LINE_WIDTH)
}

# --- outer band ---------------------------------------------------------------
p <- p + geom_ribbon(
  data = fc,
  aes(x = x, ymin = y_of(.data[[BAND_OUTER[1]]]), ymax = y_of(.data[[BAND_OUTER[2]]]),
      group = fan_id, fill = col_key),
  alpha = RIBBON_ALPHA_OUTER, colour = NA
)

# --- inner band ---------------------------------------------------------------
if (!is.null(BAND_INNER)) {
  p <- p + geom_ribbon(
    data = fc,
    aes(x = x, ymin = y_of(.data[[BAND_INNER[1]]]), ymax = y_of(.data[[BAND_INNER[2]]]),
        group = fan_id, fill = col_key),
    alpha = RIBBON_ALPHA_INNER, colour = NA
  )
}

# --- ensemble central line ----------------------------------------------------
p <- p + geom_line(
  data = fc,
  aes(x = x, y = y_of(.data[[CENTRAL_LINE]]), group = fan_id,
      colour = col_key, linetype = lt_key),
  linewidth = LINE_WIDTH_FORECAST
)

# --- truth (drawn last so it stays visible on top of the fans) ----------------
if (identical(TRUTH_COLOUR, "match") && COLOR_BY == "strain") {
  tr$col_key <- factor(tr$strain, levels = levels(fc$col_key))
  p <- p + geom_line(data = tr,
                     aes(x = x, y = y_of(truth_100k), colour = col_key,
                         group = interaction(row_key, loc_row, strain)),
                     linewidth = LINE_WIDTH_TRUTH)
} else {
  p <- p + geom_line(data = tr,
                     aes(x = x, y = y_of(truth_100k),
                         group = interaction(row_key, loc_row, truth_id)),
                     colour = if (identical(TRUTH_COLOUR, "match")) "black" else TRUTH_COLOUR,
                     linewidth = LINE_WIDTH_TRUTH)
}

# --- scales -------------------------------------------------------------------
# A monochrome configuration legend would be four identical swatches, and the row
# strips already name them, so drop it.
colour_legend <- !(COLOR_BY == "config" && CONFIG_PALETTE == "mono" &&
                   FACET_ROWS == "config")

p <- p +
  scale_colour_manual(name = col_title, values = col_values, labels = col_labels,
                      guide = if (colour_legend) "legend" else "none") +
  scale_fill_manual(  name = col_title, values = col_values, labels = col_labels,
                      guide = if (colour_legend) "legend" else "none")

if (LINETYPE_BY != "none") {
  p <- p + scale_linetype_manual(name = lt_title, values = lt_values, labels = lt_labels)
} else {
  p <- p + scale_linetype_manual(values = c(a = "solid"), guide = "none")
}

if (Y_LOG) {
  p <- p + scale_y_log10(labels = label_number(accuracy = 1, big.mark = ","))
} else {
  p <- p + scale_y_continuous(labels = label_number(accuracy = 1, big.mark = ","))
}

if (X_AXIS == "date") {
  p <- p + scale_x_date(date_breaks = DATE_BREAKS, date_labels = "%b %Y")
} else if (X_AXIS == "onset_rel") {
  p <- p + scale_x_continuous(breaks = pretty_breaks(6))
}

if (!is.null(X_LIMITS)) p <- p + coord_cartesian(xlim = X_LIMITS)

# facet_grid can only free y per row; ggh4x can free it per panel.
if (PANEL_SCALES == "free_each" && requireNamespace("ggh4x", quietly = TRUE)) {
  p <- p + ggh4x::facet_grid2(facet_f, scales = "free_y", independent = "y",
                              labeller = labeller(row_key = row_labeller))
} else {
  if (PANEL_SCALES == "free_each")
    message('PANEL_SCALES = "free_each" needs the ggh4x package; falling back to "free_y".')
  p <- p + facet_grid(facet_f,
                      scales = if (PANEL_SCALES == "fixed") "fixed" else "free_y",
                      labeller = labeller(row_key = row_labeller))
}

x_title <- switch(X_AXIS, onset_rel = "Weeks from onset", week = "Week", date = NULL)

p <- p +
  labs(
    x = x_title,
    y = "Weekly new cases per 100,000",
    title = paste0(
      if (DATASET == "real") "Forecast ensemble vs reported COVID-19 incidence"
      else                   "Forecast ensemble vs synthetic truth",
      if (length(unique(fc$lead)) == 1)
        sprintf(", issued %d weeks before onset", abs(unique(fc$lead)))
      else ", by lead to onset"),
    subtitle = sprintf(paste0("black = observed; coloured line = ensemble %s, bands = %s%s ",
                              "of the 150-member ensemble\n",
                              "dashed rule = onset (first week the observed series reaches ",
                              "%d per 100k); each fan stops at onset", truth_note),
                       if (CENTRAL_LINE == "q50") "median" else "mean",
                       paste0(as.numeric(sub("q", "", BAND_OUTER)), collapse = "-"),
                       if (is.null(BAND_INNER)) "th percentile"
                       else paste0(" and ", paste(as.numeric(sub("q", "", BAND_INNER)),
                                                  collapse = "-"), "th percentile"),
                       ONSET_THRESHOLD)
  ) +
  theme_bw(base_size = BASE_TEXT_SIZE) +
  theme(
    panel.border       = element_rect(colour = "grey70", fill = NA),
    panel.grid.minor   = element_blank(),
    strip.background   = element_rect(fill = STRIP_FILL, colour = NA),
    strip.text         = element_text(face = "bold", size = BASE_TEXT_SIZE * 0.85),
    legend.position    = "right",
    legend.box         = "vertical",
    legend.title       = element_text(face = "bold", size = BASE_TEXT_SIZE * 0.9),
    legend.text        = element_text(size = BASE_TEXT_SIZE * 0.85),
    legend.key.width   = unit(1.6, "cm"),
    plot.title         = element_text(face = "bold", size = BASE_TEXT_SIZE * 1.2),
    plot.subtitle      = element_text(size = BASE_TEXT_SIZE * 0.8, colour = "grey30"),
    axis.text          = element_text(size = BASE_TEXT_SIZE * 0.75),
    axis.text.x        = if (X_AXIS == "date")
      element_text(size = BASE_TEXT_SIZE * 0.75, angle = 45, hjust = 1)
      else element_text(size = BASE_TEXT_SIZE * 0.75)
  ) +
  guides(
    fill   = if (colour_legend) guide_legend(order = 1,
                                             override.aes = list(alpha = 0.5, colour = NA)) else "none",
    colour = if (colour_legend) guide_legend(order = 1,
                                             override.aes = list(linewidth = 2)) else "none"
  )

# ══════════════════════════════════════════════════════════════════════════════
# 5. SAVE
# ══════════════════════════════════════════════════════════════════════════════

dir.create(dirname(OUT_PDF), showWarnings = FALSE, recursive = TRUE)

n_rows <- nlevels(droplevels(fc$row_key))
fig_h  <- if (is.null(PDF_HEIGHT)) 3.6 * max(n_rows, 1) + 2 else PDF_HEIGHT

ggsave(OUT_PDF, p, width = PDF_WIDTH, height = fig_h, device = "pdf", limitsize = FALSE)
cat("Saved:", OUT_PDF, "\n")

ggsave(OUT_PNG, p, width = PDF_WIDTH, height = fig_h, device = "png", dpi = 200,
       limitsize = FALSE)
cat("Saved:", OUT_PNG, "\n")
