# plot_rel_bars_real.R
#
# Bar plots of the relative forecast skill for the real-incidence runs.
# Pois-only, country-aggregated.
# Layout per target row (4 columns):
#   Col 1: "all" window, mean_mae  — own y scale, y-axis shown, rotated
#   Col 2: "all" window, mean_wis  — own y scale, y-axis hidden
#   Col 3: {m8m6,m5m3,m2p0}, mean_mae — own y scale, y-axis shown, rotated
#   Col 4: {m8m6,m5m3,m2p0}, mean_wis — own y scale, y-axis hidden
# Column widths: c(1, 1, 3, 3)
#
# Input : results/csv/rel_bars_real.csv   (written by make_csv_real.m)
# Output: results/figures/rel_bars_real_<target>2.{pdf,png}
#
#   Rscript src/plotting/plot_rel_bars_real.R

library(ggplot2)
library(ggpattern)
library(dplyr)
library(patchwork)
library(cowplot)
library(viridis)

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

selected_target <- "all" # Options: "onset50", "onset100", or "all"


csv_path  <- file.path(ROOT, "results", "csv", "rel_bars_real.csv")

out_pdf        <- file.path(ROOT, "results", "figures",
                            paste0("rel_bars_real_", selected_target, "2.pdf"))
out_png        <- file.path(ROOT, "results", "figures",
                            paste0("rel_bars_real_", selected_target, "2.png"))


time_window_labels <- c(
  "all"  = "-8 to 0",
  "m8m6" = "-8 to -6",
  "m5m3" = "-5 to -3",
  "m2p0" = "-2 to 0"
)

bar_cap        <- 1.5
pdf_width      <- 26
pdf_height     <- 12 #good for 2 onsets (2 row grid)
#pdf_height     <- 9 #good for 1 onset  (1 row grid)
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

shade_adjust <- 0.30

darken_hex <- function(hex, amount) {
  rgb_vals <- col2rgb(hex) / 255
  rgb_vals <- pmax(rgb_vals - amount, 0)
  rgb(rgb_vals[1], rgb_vals[2], rgb_vals[3])
}

tw_present     <- names(time_window_labels)[names(time_window_labels) %in% unique(df$time_window)]
n_windows      <- length(tw_present)
#tw_colors_base <- setNames(c("#E69F00", "#56B4D9", "#009E73", "#CC79A7"), tw_present)
tw_colors_base <- setNames(c("#E69F00",viridis::viridis(n_windows-1, begin = 0.6, end = 0.92)), tw_present)
df <- df %>%
  mutate(
    base_color    = tw_colors_base[time_window],
    fill_color    = ifelse(flights == "nf",
                           mapply(darken_hex, base_color, shade_adjust),
                           base_color),
    tw_flight_key = paste(time_window, flights, sep = ":")
  )

tw_flight_map <- setNames(df$fill_color, df$tw_flight_key)
tw_flight_map <- tw_flight_map[!duplicated(names(tw_flight_map))]

# ── 3. FACTOR ORDERING ───────────────────────────────────────────────────────

df$nickname    <- factor(df$nickname,    levels = unique(df$nickname))
df$time_window <- factor(df$time_window, levels = tw_present)

# ── 4. DERIVED AESTHETIC COLUMNS ─────────────────────────────────────────────

df <- df %>%
  mutate(
    bar_pattern  = ifelse(commuting == "n", "stripe", "none"),
    rel_val_plot = pmin(rel_val, bar_cap),
    capped       = ifelse(rel_val > bar_cap, 1, 0)
  )

# ── 5. PANEL FACTORY ─────────────────────────────────────────────────────────
# `is_left`      : TRUE  → "all" sub-panel (single x label, bars dodged)
#                  FALSE → fixed-baseline sub-panel (3 x groups)
# `show_y`       : whether to show y-axis numbers and ticks
# `show_title`   : whether to print the metric title above
# `vals_range`   : c(min, max) from THIS panel's data only

make_panel <- function(data_sub, target_name, metric_name,
                       is_left, show_y, show_y_label, show_title, vals_range) {
  
  plot_min   <- vals_range[1]
  plot_max   <- vals_range[2]
  range_span <- max(plot_max - plot_min, 0.1)
  y_upper    <- plot_max + range_span * 0.05
  
  dodge <- position_dodge(width = 0.9)
  
  if (is_left) {
    # ── "all" panel: 4 bars dodged under one x label ─────────────────────────
    data_sub <- data_sub %>% mutate(x_group = "-8 to 0")
    
    p <- ggplot(data_sub,
                aes(x       = x_group,
                    y       = rel_val_plot,
                    fill    = tw_flight_key,
                    group   = nickname,
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
        aes(x = x_group, y = bar_cap, group = nickname),
        inherit.aes = FALSE,
        position    = dodge,
        shape = 25, size = 2, fill = "black", colour = "black"
      ) +
      scale_fill_manual(values = tw_flight_map, guide = "none") +
      scale_pattern_manual(values = c("stripe" = "stripe", "none" = "none"), guide = "none") +
      coord_cartesian(ylim = c(plot_min, y_upper))
    
  } else {
    # ── fixed-baseline panel: 3 x groups, bars dodged ────────────────────────
    p <- ggplot(data_sub,
                aes(x       = time_window,
                    y       = rel_val_plot,
                    fill    = tw_flight_key,
                    group   = nickname,
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
        aes(x = time_window, y = bar_cap, group = nickname),
        inherit.aes = FALSE,
        position    = dodge,
        shape = 25, size = 2, fill = "black", colour = "black"
      ) +
      scale_fill_manual(values = tw_flight_map, guide = "none") +
      scale_pattern_manual(values = c("stripe" = "stripe", "none" = "none"), guide = "none") +
      scale_x_discrete(labels = time_window_labels) +
      coord_cartesian(ylim = c(plot_min, y_upper))
  }
  
  # Format metric title: "mean_mae" → "Mean MAE"
  metric_title <- gsub("mean_", "Mean ", metric_name)
  metric_title <- gsub("mae", "MAE", gsub("wis", "WIS", metric_title))
  
  p <- p +
    labs(
      x     = NULL,
      y = if (show_y_label) sub("onset(\\d+)", "Week of onset \\1 per 100k", target_name, perl = TRUE) else NULL,
      title = if (show_title) metric_title else NULL
    ) +
    theme_bw(base_size = base_text_size) +
    theme(
      panel.border = element_blank(),
      panel.grid.major.x = element_blank(),
      axis.ticks.x       = element_blank(),
      legend.position    = "none",
      plot.title         = element_text(size = base_text_size + 2, face = "bold", hjust = 0.5),
      axis.title.y       = element_text(size = base_text_size),
      axis.text.y        = if (show_y) element_text(size = base_text_size * 0.8, angle = 90,
                                                    vjust = 0.5, hjust = 0.5)
      else element_blank(),
      axis.ticks.y       = if (show_y) element_line() else element_blank()
    )
  p
}

# ── 6. BUILD PANEL GRID ───────────────────────────────────────────────────────
# Layout per target row: [all/mae, all/wis, fix/mae, fix/wis]
# Cols 1+2 share one y scale (all data, both metrics combined).
# Cols 3+4 share one y scale (fix data, both metrics combined).
# Y-axis numbers shown on col 1 and col 3 (leftmost of each pair).
# Y-axis title shown on col 1 only.

targets <- unique(df$target)
metrics <- unique(df$metric)   # expected: c("mean_mae", "mean_wis")

all_panels <- list()

for (ti in seq_along(targets)) {
  target <- targets[ti]
  
  # ── Shared y ranges: computed across BOTH metrics for each side ─────────────
  sub_all_both <- df %>% filter(target == !!target, time_window == "all")
  sub_fix_both <- df %>% filter(target == !!target, time_window != "all")
  
  yr_all_shared <- c(max(0, min(sub_all_both$rel_val_plot, na.rm = TRUE) - 0.05),
                     min(max(sub_all_both$rel_val_plot, na.rm = TRUE), bar_cap))
  yr_fix_shared <- c(max(0, min(sub_fix_both$rel_val_plot, na.rm = TRUE) - 0.05),
                     min(max(sub_fix_both$rel_val_plot, na.rm = TRUE), bar_cap))
  
  for (mi in seq_along(metrics)) {
    metric <- metrics[mi]
    
    sub_all <- df %>% filter(target == !!target, metric == !!metric, time_window == "all")
    sub_fix <- df %>% filter(target == !!target, metric == !!metric, time_window != "all")
    
    show_title       <- (ti == 1)
    show_y_all       <- (mi == 1)   # numbers on col 1 (all/mae) only
    show_y_fix       <- (mi == 1)   # numbers on col 3 (fix/mae) only
    show_y_label_all <- (mi == 1)   # y title on col 1 only
    show_y_label_fix <- FALSE       # never show y title on col 3
    
    all_panels[[length(all_panels) + 1]] <- list(
      p_all = make_panel(sub_all, target, metric,
                         is_left = TRUE,  show_y = show_y_all,
                         show_y_label = show_y_label_all,
                         show_title = show_title, vals_range = yr_all_shared),
      p_fix = make_panel(sub_fix, target, metric,
                         is_left = FALSE, show_y = show_y_fix,
                         show_y_label = show_y_label_fix,
                         show_title = show_title, vals_range = yr_fix_shared),
      target = target,
      metric = metric,
      ti = ti,
      mi = mi
    )
  }
}

# Arrange into rows: per target, columns are [all_mae, all_wis, fix_mae, fix_wis]
row_list <- list()
for (ti in seq_along(targets)) {
  entries <- Filter(function(x) x$ti == ti, all_panels)
  entries <- entries[order(sapply(entries, function(x) x$mi))]
  
  # cols 1,2: all/mae, all/wis  |  cols 3,4: fix/mae, fix/wis
  row_panels <- c(
    lapply(entries, function(x) x$p_all),
    lapply(entries, function(x) x$p_fix)
  )
  
  row_list[[ti]] <- wrap_plots(row_panels, nrow = 1, ncol = 4) +
    plot_layout(widths = c(1, 1, 3, 3))
}

# ── 7. BUILD THE LEGEND ───────────────────────────────────────────────────────

dummy_df <- data.frame(
  TimeWindow = factor(tw_present, levels = tw_present),
  Flights    = factor(c("nf", "f",  rep("nf",  max(0, n_windows - 2))), levels = c("nf", "f")),
  Comm       = factor(c("p",  "n",  rep("p",   max(0, n_windows - 2))), levels = c("p", "n"))
)

legend_plot <- ggplot(dummy_df, aes(x = TimeWindow, y = 1)) +
  geom_bar_pattern(aes(fill    = TimeWindow), stat = "identity") +
  geom_bar_pattern(aes(alpha   = Flights),    stat = "identity") +
  geom_bar_pattern(aes(pattern = Comm),       stat = "identity") +
  
  scale_fill_manual(
    name   = "Horizons",
    values = tw_colors_base,
    breaks = tw_present,
    labels = time_window_labels[tw_present],
    guide  = guide_legend(order = 1, override.aes = list(pattern = "none", colour = NA,
                                                         linewidth = linewidth_leg))
  ) +
  scale_alpha_manual(
    name   = "Flights",
    values = c("nf" = 1, "f" = 0.99),
    labels = c("nf" = "No Flight", "f" = "Flight"),
    guide  = guide_legend(order = 2, override.aes = list(fill = c("gray50", "gray80"),
                                                         alpha = 1, colour = NA,
                                                         pattern = "none",
                                                         linewidth = linewidth_leg))
  ) +
  scale_pattern_manual(
    name   = "Commuting",
    values = c("p" = "none", "n" = "stripe"),
    labels = c("p" = "Patch", "n" = "Network"),
    guide  = guide_legend(order = 3, override.aes = list(fill = "gray80", colour = NA,
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
    #legend.position = "bottom",
    #legend.box      = "horizontal",
    legend.title    = element_text(face = "bold", size = base_text_size * 0.9),
    legend.text     = element_text(size = base_text_size * 0.9),
    legend.key.size = unit(1.2, "cm")
  )

leg_grob <- cowplot::get_legend(legend_plot)

# ── 8. ASSEMBLE FULL FIGURE ──────────────────────────────────────────────────

main_grid <- wrap_plots(row_list, nrow = length(targets), ncol = 1) 

# Lock the main_grid into a single element before attaching the legend
final_plot <- wrap_elements(full = main_grid) | leg_grob
final_plot <- final_plot + plot_layout(widths = c(10, 1))



# ── 9. SAVE ───────────────────────────────────────────────────────────────────

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