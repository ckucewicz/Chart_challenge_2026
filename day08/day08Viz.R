library(dplyr)
library(lubridate)
library(ggplot2)
library(showtext)
library(patchwork)

showtext_auto()
font_add_google("Lato", "lato")

# ── Data ──────────────────────────────────────────────────────
hourly_avg <- pm25_raw %>%
  dplyr::mutate(hour = lubridate::hour(datetime)) %>%
  dplyr::group_by(site_number, hour) %>%
  dplyr::summarise(site_hour_mean = mean(pm25_ugm3, na.rm = TRUE), .groups = "drop") %>%
  dplyr::group_by(hour) %>%
  dplyr::summarise(avg_pm25 = mean(site_hour_mean, na.rm = TRUE), .groups = "drop") %>%
  dplyr::arrange(hour)

hour_labels <- c(
  "12am","1am","2am","3am","4am","5am",
  "6am","7am","8am","9am","10am","11am",
  "12pm","1pm","2pm","3pm","4pm","5pm",
  "6pm","7pm","8pm","9pm","10pm","11pm"
)
hourly_avg$label <- hour_labels
hourly_avg$x_pos <- hourly_avg$hour + 0.5
BASE        <- round(min(hourly_avg$avg_pm25) - 0.4, 2)
ANNUAL_MEAN <- 8.55

# ── Reference rings ───────────────────────────────────────────
ring_vals <- c(8, 9, 10)

rings_df <- do.call(rbind, lapply(ring_vals, function(rv) {
  data.frame(x = seq(0, 24, length.out = 500), y = rv - BASE, ring = as.character(rv))
}))

mean_ring_df <- data.frame(x = seq(0, 24, length.out = 500), y = ANNUAL_MEAN - BASE)

ring_labels_df <- data.frame(
  x = 16.75, y = ring_vals - BASE, label = paste0(ring_vals, " µg/m³")
)

green_palette <- c("#1b7837", "#7fbf7b", "#d9ef8b", "#fee08b", "#fc8d59")

# ── Chart — output at 8x8 inches, 150 DPI = 1200px ────────────
# At this size, size=6 in geom_text ≈ readable, axis size=14 ≈ readable
p <- ggplot() +
  
  geom_path(
    data = rings_df,
    aes(x = x, y = y, group = ring),
    color = "#d2d2d2", linewidth = 0.5
  ) +
  
  geom_col(
    data = hourly_avg,
    aes(x = x_pos, y = avg_pm25 - BASE, fill = avg_pm25),
    width = 0.85, color = "#f5f2eb", linewidth = 0.2
  ) +
  
  geom_path(
    data = mean_ring_df,
    aes(x = x, y = y),
    color = "#c94a2a", linewidth = 1.2, linetype = "dashed"
  ) +
  
  geom_text(
    data = ring_labels_df,
    aes(x = x, y = y, label = label),
    size = 6, color = "#696969", family = "lato",
    hjust = 1.1, vjust = 0.4
  ) +
  
  coord_polar(start = -pi / 24) +
  scale_fill_gradientn(colors = green_palette) +
  scale_x_continuous(
    limits = c(0, 24),
    breaks = seq(0.5, 23.5, by = 1),
    labels = hour_labels
  ) +
  
  theme_void() +
  theme(
    text            = element_text(family = "lato"),
    axis.text.x     = element_text(size = 14, color = "#696969"),
    plot.background = element_rect(fill = "#f5f2eb", color = NA),
    plot.margin     = margin(20, 20, 0, 20),
    legend.position = "none"
  )

# ── Legend ────────────────────────────────────────────────────
p_legend <- ggplot() +
  annotate("segment",
           x = 0.02, xend = 0.09, y = 0.5, yend = 0.5,
           color = "#c94a2a", linewidth = 1.5, linetype = "dashed"
  ) +
  xlim(0, 1) + ylim(0, 1) +
  theme_void() +
  theme(
    plot.background = element_rect(fill = "#f5f2eb", color = NA),
    plot.margin     = margin(0, 20, 10, 20)
  )

# ── Combine and save at 8x9 inches, 150 DPI ───────────────────
bg <- theme(plot.background = element_rect(fill = "#f5f2eb", color = NA))
p        <- p        + bg
p_legend <- p_legend + bg
p_source <- p_source + bg

final <- p / p_legend / p_source +
  plot_layout(heights = c(16, 1.5, 4))

ggsave(
  "pm25_circular_2024.png",
  plot   = final,
  width  = 8,
  height = 11,
  units  = "in",
  dpi    = 150,
  bg     = "#f5f2eb"
)

cat("Saved → pm25_circular_2024.png\n")