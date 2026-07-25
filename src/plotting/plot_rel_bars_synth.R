# plot_rel_bars_synth.R
#
# Bar plots of the relative forecast skill for the synthetic runs.
# Input : results/csv/rel_bars_synth.csv   (written by make_csv_synth.m)
# Output: results/figures/rel_bars_synth_<target>.{pdf,png}
#
#   Rscript src/plotting/plot_rel_bars_synth.R

library(ggplot2)
library(ggpattern)
library(dplyr)
library(patchwork)
library(cowplot)

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

# ── 0. CONFIG ────────────────────────────────────────────────────────────────

selected_target <- "onset100" # Options: "onset150", "onset100", or "all"


csv_path       <- file.path(ROOT, "results", "csv", "rel_bars_synth.csv")
out_pdf        <- file.path(ROOT, "results", "figures",
                            paste0("rel_bars_synth_", selected_target, ".pdf"))
out_png        <- file.path(ROOT, "results", "figures",
                            paste0("rel_bars_synth_", selected_target, ".png"))
# Strain x-axis labels (parsed as expressions by scale_x_discrete)

strain_levels <- c("ls", "lo", "me", "hi", "hs")
strain_labels <- c(
  ls = "beta==0.8",
  lo = "beta==1",
  me = "beta==2",
  hi = "beta==3",
  hs = "beta==4"
)

bar_cap        <- 1.5
pdf_width      <- 26
#pdf_height     <- 12 #good for 2 onsets
pdf_height     <- 9 #good for 1 onset
base_text_size <- 24
bar_text_size  <- 6
linewidth_leg  <- 2.2

# ── 1. LOAD & PREPARE DATA ───────────────────────────────────────────────────

df <- read.csv(csv_path, stringsAsFactors = FALSE)
df <- df %>% filter(!is.nan(rel_val) & !is.na(rel_val))

if (selected_target != "all") {
  df <- df %>% filter(target == selected_target)
}

# ── 2. COLOUR PALETTE ────────────────────────────────────────────────────────

strain_base_colors <- c(
  ls = rgb(144, 103, 167, maxColorValue = 255),
  lo = rgb(114, 147, 203, maxColorValue = 255),
  me = rgb(132, 186,  91, maxColorValue = 255),
  hi = rgb(237, 177,  32, maxColorValue = 255),
  hs = rgb(211,  94,  96, maxColorValue = 255)
)
shade_adjust <- 0.30

darken_hex <- function(hex, amount) {
  rgb_vals <- col2rgb(hex) / 255
  rgb_vals <- pmax(rgb_vals - amount, 0)
  rgb(rgb_vals[1], rgb_vals[2], rgb_vals[3])
}

# fill keyed by group_id (strain + flight combo drives the colour)
df <- df %>%
  mutate(
    base_color = strain_base_colors[strain],
    fill_color = ifelse(flights == "nf",
                        mapply(darken_hex, base_color, shade_adjust),
                        base_color)
  )

fill_map <- setNames(df$fill_color, df$group_id)
fill_map <- fill_map[!duplicated(names(fill_map))]

# ── 3. FACTOR ORDERING ───────────────────────────────────────────────────────

df$group_id <- factor(df$group_id, levels = unique(df$group_id))
df$strain   <- factor(df$strain,   levels = strain_levels)

# ── 4. DERIVED AESTHETIC COLUMNS ─────────────────────────────────────────────

df <- df %>%
  mutate(
    bar_pattern  = ifelse(commuting == "n", "stripe", "none"),
    rel_val_plot = pmin(rel_val, bar_cap),
    capped       = ifelse(rel_val > bar_cap, 1, 0)
  )

# ── 5. PANEL FACTORY ─────────────────────────────────────────────────────────
# x = strain  (group label centered naturally under dodged bars)
# dodge by group_id  (individual model bars within each strain)
# show_y       : show y-axis numbers and ticks
# show_y_label : show y-axis title
# show_title   : show metric title above panel

make_panel <- function(data_sub, target_name, metric_name,
                       show_y, show_y_label, show_title, vals_range) {
  
  plot_min   <- vals_range[1]
  plot_max   <- vals_range[2]
  range_span <- max(plot_max - plot_min, 0.1)
  y_upper    <- plot_max + range_span * 0.05
  
  local_fill <- fill_map[levels(data_sub$group_id)]
  local_fill <- local_fill[!is.na(local_fill)]
  
  # Format metric title
  metric_title <- gsub("mean_", "Mean ", metric_name)
  metric_title <- gsub("mae", "MAE", gsub("wis", "WIS", metric_title))
  
  # Wider dodge gap (0.9) keeps bars close within a strain;
  # the natural gap between strain factor levels separates groups.
  dodge <- position_dodge(width = 0.9)
  
  p <- ggplot(data_sub,
              aes(x       = strain,
                  y       = rel_val_plot,
                  fill    = group_id,
                  group   = group_id,
                  pattern = bar_pattern)) +
    
    geom_hline(yintercept = 1, linetype = "dotted",
               colour = "black", linewidth = 0.8) +
    
    geom_bar_pattern(
      stat            = "identity",
      position        = dodge,
      linewidth       = 0.7,
      colour          = "white",
      pattern_colour  = "gray80",
      pattern_fill    = "gray80",
      pattern_density = 0.30,
      pattern_spacing = 0.04,
      pattern_angle   = 45,
      width           = 0.85
    ) +

    geom_label(aes(y = plot_min + 0.001, label = round(n_samples)),
               position = dodge,
               vjust = 0.5, hjust = 0.5, angle = 90,
               size  = bar_text_size, color = "black",
               fill  = alpha("white", 0.5),
               label.size = 0, label.padding = unit(0.1, "lines")) +
    
    geom_point(
      data        = filter(data_sub, capped == 1),
      aes(x = strain, y = bar_cap, group = group_id),
      inherit.aes = FALSE,
      position    = dodge,
      shape = 25, size = 2, fill = "black", colour = "black"
    ) +
    
    scale_fill_manual(values = local_fill, guide = "none") +
    scale_pattern_manual(values = c("stripe" = "stripe", "none" = "none"), guide = "none") +
    
    # Parsed beta expressions centered under each strain group automatically
    scale_x_discrete(labels = parse(text = strain_labels[strain_levels])) +
    
    coord_cartesian(ylim = c(plot_min, y_upper)) +
    
    labs(
      x     = NULL,
      y     = if (show_y_label) sub("onset(\\d+)", "Week of onset \\1 per 100k",
                                    target_name, perl = TRUE) else NULL,
      title = if (show_title) metric_title else NULL
    ) +
    theme_bw(base_size = base_text_size) +
    theme(
      panel.border       = element_blank(),
      panel.grid.major.x = element_blank(),
      axis.ticks.x       = element_blank(),
      legend.position    = "none",
      plot.title         = element_text(size = base_text_size + 2, face = "bold", hjust = 0.5),
      axis.title.y       = element_text(size = base_text_size),
      axis.text.y        = if (show_y) element_text(size = base_text_size * 0.8, angle = 90,
                                                    vjust = 0.5, hjust = 0.5)
      else element_blank(),
      axis.ticks.y       = if (show_y) element_line() else element_blank(),
      axis.text.x        = element_text(size = base_text_size * 0.85)
    )
  p
}

# ── 6. BUILD PANEL GRID ───────────────────────────────────────────────────────
# MAE and WIS share the same y scale within each target row.
# The two onset rows (onset50, onset100) can have different scales.

targets <- unique(df$target)
metrics <- unique(df$metric)

# One y-range per target, computed across both metrics
yr_by_target <- lapply(targets, function(t) {
  vals <- df %>% filter(target == t) %>% pull(rel_val_plot)
  c(max(0, min(vals, na.rm = TRUE) - 0.05),
    min(max(vals, na.rm = TRUE), bar_cap))
})
names(yr_by_target) <- targets

panels <- list()
for (ti in seq_along(targets)) {
  for (mi in seq_along(metrics)) {
    sub <- df %>% filter(target == targets[ti], metric == metrics[mi])
    
    panels[[length(panels) + 1]] <- make_panel(
      sub, targets[ti], metrics[mi],
      show_y       = (mi == 1),
      show_y_label = (mi == 1),
      show_title   = (ti == 1),
      vals_range   = yr_by_target[[targets[ti]]]
    )
  }
}

main_grid <- wrap_plots(panels, nrow = length(targets), ncol = length(metrics))

# ── 7. BUILD THE LEGEND ───────────────────────────────────────────────────────

dummy_df <- data.frame(
  Strain  = factor(c("ls", "lo", "me", "hi", "hs"), levels = strain_levels),
  Flights = factor(c("nf", "f",  "nf", "f",  "nf"), levels = c("nf", "f")),
  Comm    = factor(c("p",  "n",  "p",  "n",  "p"),  levels = c("p", "n"))
)

legend_plot <- ggplot(dummy_df, aes(x = Strain, y = 1)) +
  geom_bar_pattern(aes(fill    = Strain),  stat = "identity") +
  geom_bar_pattern(aes(alpha   = Flights), stat = "identity") +
  geom_bar_pattern(aes(pattern = Comm),    stat = "identity") +
  
  scale_fill_manual(
    name   = "Strain",
    values = strain_base_colors,
    breaks = strain_levels,
    labels = expression(beta == 0.8, beta == 1, beta == 2, beta == 3, beta == 4),
    guide  = guide_legend(order = 1,
                          override.aes = list(pattern = "none", colour = NA,
                                              linewidth = linewidth_leg))
  ) +
  scale_alpha_manual(
    name   = "Flights",
    values = c("nf" = 1, "f" = 0.99),
    labels = c("nf" = "No Flight", "f" = "Flight"),
    guide  = guide_legend(order = 2,
                          override.aes = list(fill = c("gray50", "gray80"),
                                              alpha = 1, colour = NA,
                                              pattern = "none",
                                              linewidth = linewidth_leg))
  ) +
  scale_pattern_manual(
    name   = "Commuting",
    values = c("p" = "none", "n" = "stripe"),
    labels = c("p" = "Patch", "n" = "Network"),
    guide  = guide_legend(order = 3,
                          override.aes = list(fill = "gray80", colour = NA,
                                              pattern_fill    = "gray50",
                                              pattern_density = 0.3,
                                              pattern_spacing = 0.05,
                                              linewidth = 0))
  ) +
  scale_linetype_manual(values = c("solid"), guide = "none") +
  theme_void() +
  theme(
    legend.position = "right",
    legend.box      = "vertical",
    legend.title    = element_text(face = "bold", size = base_text_size * 0.9),
    legend.text     = element_text(size = base_text_size * 0.9),
    legend.key.size = unit(1.2, "cm")
  )

leg_grob <- cowplot::get_legend(legend_plot)


# ── 8. ASSEMBLE & SAVE ───────────────────────────────────────────────────────

# Lock the main_grid into a single element before attaching the legend
final_plot <- wrap_elements(full = main_grid) | leg_grob
final_plot <- final_plot + plot_layout(widths = c(10, 1))

ggsave(out_pdf, final_plot,
       width  = pdf_width,
       height = pdf_height,
       device = "pdf")
cat("Saved:", out_pdf, "\n")

ggsave(out_png, final_plot,
       width  = pdf_width,
       height = pdf_height,
       device = "png",
       dpi = 300)
cat("Saved:", out_png, "\n")