# plot_maps_NA.R
#
# Figure 1: daily commuting-to-work matrix and annual air passenger travel
# matrix drawn on a map of North America.
#
# Inputs : data/gis/shape/...          North American political boundaries
#          data/gis/coordinatesNAE.csv
#          data/statecodes.csv
#          data/raw/final_commuting_matrix_Oct2023.csv
#          data/raw/Matrix-air-flow-sep04.csv
# Output : results/figures/plot_NAR_5070_legend.{pdf,png}
#
#   Rscript src/plotting/plot_maps_NA.R
#
# The boundary .shp is not stored in the repository; data/gis/shape/README.md
# has the download link.

library(sf)
library(ggplot2)
library(dplyr)
library(patchwork)
#library(rmapshaper)

# ── PROJECT ROOT ─────────────────────────────────────────────────────────────
# Resolved from this script's own location, so the script runs from any working
# directory (Rscript, source(), or line-by-line in RStudio).
ROOT <- local({
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
    stop("Could not find the project root (run_pipeline.m). Set ROOT manually.")
  d
})

shapefile_path <- file.path(ROOT, "data", "gis", "shape",
                            "politicalboundaries_shapefile", "NA_PoliticalDivisions",
                            "data", "boundaries_p_2021_v3.shp")
if (!file.exists(shapefile_path))
  stop("Shapefile not found: ", shapefile_path,
       "\nSee data/gis/shape/README.md for the download link.")

# ── 0. Load data ───────────────────────────────────────────────────────────────
NAR <- st_read(shapefile_path)
NAR <- NAR[!(NAR$NAME_En %in% c("Puerto Rico", "United States Virgin Islands","Hawaii")), ]
NAR_5070 <- st_transform(NAR, crs = 5070)
#NAR_5070 <- ms_simplify(NAR_5070, keep = 0.05)
NAR_5070 <- st_simplify(NAR_5070, dTolerance = 5000)


coordinates_df <- read.csv(file.path(ROOT, "data", "gis", "coordinatesNAE.csv"))
statecodes      <- read.csv(file.path(ROOT, "data", "statecodes.csv"))
statecodes[1]   <- NULL
colnames(statecodes) <- c("name", "country", "color")
coordinates_df  <- merge(coordinates_df, statecodes, by.x = "Statecodes", by.y = "name", all = TRUE)

commuting_df <- read.csv(file.path(ROOT, "data", "raw", "final_commuting_matrix_Oct2023.csv"),
                         check.names = FALSE)
rownames(commuting_df) <- colnames(commuting_df)




flights_df <- read.csv(file.path(ROOT, "data", "raw", "Matrix-air-flow-sep04.csv"),
                       check.names = FALSE, header = FALSE)
rownames(flights_df) <- rownames(commuting_df)
colnames(flights_df) <- colnames(commuting_df)


# ── 1. Helper: build sf lines, carrying country/color for both endpoints ───────
# Cross-country segments are colored "goldenrod3",
# same-country segments use the country color from coordinates_df
build_segments_sf <- function(list_df, coords, value_filter) {
  
  # -- first merge: get start coords + country/color for "from"
  seg <- merge(list_df, coords, by.x = "from", by.y = "Statecodes", all = TRUE)
  colnames(seg)[colnames(seg) == "Latitude"]  <- "start_lat"
  colnames(seg)[colnames(seg) == "Longitude"] <- "start_long"
  colnames(seg)[colnames(seg) == "country"]   <- "from_country"
  colnames(seg)[colnames(seg) == "color"]     <- "from_color"
  seg <- seg[, c("from", "to", "value", "start_lat", "start_long", "from_country", "from_color")]
  
  # -- second merge: get end coords + country/color for "to"
  seg <- merge(seg, coords, by.x = "to", by.y = "Statecodes", all.x = TRUE)
  colnames(seg)[colnames(seg) == "Latitude"]  <- "end_lat"
  colnames(seg)[colnames(seg) == "Longitude"] <- "end_long"
  colnames(seg)[colnames(seg) == "country"]   <- "to_country"
  colnames(seg)[colnames(seg) == "color"]     <- "to_color"
  seg <- seg[, c("from", "to", "value",
                 "start_lat", "start_long", "from_country", "from_color",
                 "end_lat",   "end_long",   "to_country",   "to_color")]
  
  # -- filter
  seg <- seg[!is.na(seg$value) & seg$value > value_filter, ]
  seg <- seg[!is.na(seg$start_long) & !is.na(seg$end_long), ]
  
  # -- assign segment color: same country → country color, different → goldenrod3
  seg$seg_color <- ifelse(
    !is.na(seg$from_country) & !is.na(seg$to_country) & seg$from_country == seg$to_country,
    seg$from_color,   # both same country: use that country's color
    "goldenrod3"      # cross-country
  )
  
  # -- assign alpha: cross-country → 1, same-country → 0.5
  seg$seg_alpha <- ifelse(seg$seg_color == "goldenrod3", 1, 0.5)
  
  # -- build linestrings
  lines_list <- lapply(1:nrow(seg), function(i) {
    st_linestring(matrix(
      c(seg$start_long[i], seg$start_lat[i],
        seg$end_long[i],   seg$end_lat[i]),
      ncol = 2, byrow = TRUE
    ))
  })
  
  st_sf(seg, geometry = st_sfc(lines_list, crs = 4326)) |>
    st_transform(crs = 5070)
}


# ── 2. Commuting – average bidirectional, build sf ────────────────────────────
list_commute <- as.data.frame(as.table(as.matrix(commuting_df)))
colnames(list_commute) <- c("from", "to", "value")
list_commute <- list_commute[list_commute$from != "Hawaii" & list_commute$to != "Hawaii", ]

list_avg_segment <- list_commute |>
  rowwise() |>
  mutate(pair = paste(sort(c(as.character(from), as.character(to))), collapse = "_")) |>
  group_by(pair) |>
  summarise(
    from  = first(sort(c(as.character(from), as.character(to)))),
    to    = last(sort(c(as.character(from), as.character(to)))),
    value = mean(value),
    .groups = "drop"
  ) |>
  select(from, to, value) |>
  filter(from != to, value >= 11)

segments_sf <- build_segments_sf(list_avg_segment, coordinates_df, value_filter = 500)
segments_sf$line_dimension <- pmin(segments_sf$value/1059180*log2(segments_sf$value) * 5, 4)

# ── 3. Flights – already symmetric, keep upper triangle, build sf ─────────────
list_flights <- as.data.frame(as.table(as.matrix(flights_df)))
colnames(list_flights) <- c("from", "to", "value")
list_flights$value <- as.numeric(list_flights$value)
list_flights <- list_flights[list_flights$from != "Hawaii" & list_flights$to != "Hawaii", ]

list_flights_upper <- list_flights |>
  filter(from != to, value > 1) |>
  rowwise() |>
  mutate(pair = paste(sort(c(as.character(from), as.character(to))), collapse = "_")) |>
  group_by(pair) |>
  slice(1) |>
  ungroup() |>
  select(from, to, value)

flights_sf <- build_segments_sf(list_flights_upper, coordinates_df, value_filter = 40000)
flights_sf$line_dimension <- pmin((flights_sf$value / 5000000)^2 * 4, 4)
# ── 5. Legend setup ─────────────────────────────────────────────────────────────

# Define the raw mathematical values instead of guessing line widths
commute_legend_df <- data.frame(
  value = c(50000, 30000, 20000, 10000, 1000),
  label = c("> 50K",  "30K", "20K", "10K", "1K" )
)

flights_legend_df <- data.frame(
  value = c(5000000, 4000000, 3000000, 2000000,1000000),
  label = c("> 5M",   "4M",  "3M", "2M", "1M")
)

# Apply the exact same formulas used on the actual map data
commute_legend_df$line_dimension <- pmin(commute_legend_df$value/1059180*log2(commute_legend_df$value) * 5, 4)
flights_legend_df$line_dimension <- pmin((flights_legend_df$value / 5000000)^2 * 4, 4)


# --- Legend anchor: x0,y0 = left end of the TOP segment ----------------------
# (Keep the rest of your legend positioning code exactly the same below)
commute_leg <- list(x0 = -3500000, y0 = 700000, spacing = -200000, seg_length = 200000)
flights_leg <- list(x0 = -3500000, y0 = 700000, spacing = -200000, seg_length = 200000)


label_nudge_x <- 50000   # gap between right end of segment and label

# --- Helper -------------------------------------------------------------------
make_legend_sf <- function(df, x0, y0, spacing, seg_length, nudge_x) {
  n  <- nrow(df)
  ys <- y0 + (seq_len(n) - 1L) * spacing
  
  # each legend symbol: a short horizontal linestring
  segs_sf <- st_sf(
    df,
    geometry = st_sfc(
      lapply(ys, \(y) st_linestring(matrix(c(x0, y, x0 + seg_length, y),
                                           ncol = 2, byrow = TRUE))),
      crs = 5070
    )
  )
  
  # labels sit just to the right of the segment's end
  labels_sf <- st_sf(
    df,
    geometry = st_sfc(
      lapply(ys, \(y) st_point(c(x0 + seg_length + nudge_x, y))),
      crs = 5070
    )
  )
  
  list(segs = segs_sf, labels = labels_sf)
}

commute_leg_layers <- make_legend_sf(commute_legend_df,
                                     commute_leg$x0, commute_leg$y0,
                                     commute_leg$spacing, commute_leg$seg_length,
                                     label_nudge_x)
flights_leg_layers <- make_legend_sf(flights_legend_df,
                                     flights_leg$x0, flights_leg$y0,
                                     flights_leg$spacing, flights_leg$seg_length,
                                     label_nudge_x)


# ── 4. Plot ───────────────────────────────────────────────────────────────────
plot_commuting <- ggplot() +
  geom_sf(data = NAR_5070, fill = "gray90", color = "gray35", linewidth = 0.35) +
  geom_sf(data = segments_sf,
          aes(linewidth = line_dimension, color = seg_color, alpha = seg_alpha),
          lineend = "round") +
  geom_sf(data = commute_leg_layers$segs,
          aes(linewidth = line_dimension), color = "gray40",
          lineend = "round", show.legend = FALSE) +
  geom_sf_text(data  = commute_leg_layers$labels,
               aes(label = label),
               hjust  = 0,
               size   = 10,
               color  = "gray40",
               family = "sans") +
  scale_linewidth_identity() +
  scale_color_identity() +
  scale_alpha_identity() +
  ggtitle("Daily work commuting") +
  theme_void() +
  theme(plot.title = element_text(size = 50, hjust = 0.5, face = "bold"))

plot_flights <- ggplot() +
  geom_sf(data = NAR_5070, fill = "gray90", color = "gray35", linewidth = 0.35) +
  geom_sf(data = flights_sf,
          aes(linewidth = line_dimension, color = seg_color, alpha = seg_alpha),
          lineend = "round") +
  geom_sf(data = flights_leg_layers$segs,
          aes(linewidth = line_dimension), color = "gray40",
          lineend = "round", show.legend = FALSE) +
  geom_sf_text(data  = flights_leg_layers$labels,
               aes(label = label),
               hjust  = 0,
               size   = 10,
               color  = "gray40",
               family = "sans") +
  scale_linewidth_identity() +
  scale_color_identity() +
  scale_alpha_identity() +
  ggtitle("Annual air passenger travel") +
  theme_void() +
  theme(plot.title = element_text(size = 50, hjust = 0.5, face = "bold"))

plot_combined <- plot_commuting + plot_flights

out_pdf <- file.path(ROOT, "results", "figures", "plot_NAR_5070_legend.pdf")
out_png <- file.path(ROOT, "results", "figures", "plot_NAR_5070_legend.png")

ggsave(out_pdf, plot_combined, width = 40, height = 20, units = "in")
# needs ImageMagick on the PATH
system(sprintf("magick -density 150 %s %s", shQuote(out_pdf), shQuote(out_png)))

