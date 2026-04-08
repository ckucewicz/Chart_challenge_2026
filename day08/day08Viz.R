library(dplyr)
library(lubridate)
library(ggplot2)
library(stringr)

# Build hourly averages
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

caption_text <- paste0(
  "Source: U.S. Environmental Protection Agency Air Quality System (AQS) API.\n",
  stringr::str_wrap(
    "Notes: PM2.5 = fine particulate matter ≤2.5 micrometers in diameter. Values are averages across 6 monitoring sites (61,609 hourly observations).",
    width = 95
  )
)

# Reference ring values in actual PM2.5 units
ring_vals <- c(7,8,9,10)

# Data for drawing full circular reference rings
rings_df <- expand.grid(
  hour = factor(0:23, levels = 0:23),
  ring = ring_vals
)

# Data for labeling the rings
# Change hour = 6 to 0, 12, or 18 if you want labels elsewhere
ring_labels_df <- data.frame(
  hour = factor(rep(6, length(ring_vals)), levels = 0:23),
  ring = ring_vals,
  label = as.character(ring_vals)
)

p <- ggplot(hourly_avg, aes(x = factor(hour), y = avg_pm25 - 7.3)) +
  
  # Reference rings
  geom_line(
    data = rings_df,
    aes(
      x = hour,
      y = ring - 7.3,
      group = factor(ring),
      color = factor(ring == 12)
    ),
    inherit.aes = FALSE,
    linewidth = 0.45,
    show.legend = FALSE
  ) +
  
  # Ring labels
  geom_text(
    data = ring_labels_df,
    aes(
      x = hour,
      y = ring - 7.3,
      label = label
    ),
    inherit.aes = FALSE,
    size = 2.7,
    color = "#9a9589",
    family = "mono",
    hjust = -0.3
  ) +
  
  # Bars
  geom_col(
    aes(fill = avg_pm25),
    width = 0.9,
    color = "#f5f2eb",
    linewidth = 0.4
  ) +
  
  coord_polar(start = -pi/24) +
  
  scale_fill_gradientn(
    colors = c("#1D9E75", "#7c6fc4", "#c94a2a")
  ) +
  
  scale_color_manual(
    values = c("FALSE" = "#d8d2c6", "TRUE" = "#9a9589")
  ) +
  
  scale_x_discrete(labels = hour_labels) +
  
  theme_void() +
  theme(
    text                  = element_text(family = "mono"),
    axis.text.x           = element_text(size = 9, color = "#9a9589"),
    plot.background       = element_rect(fill = "#f5f2eb", color = NA),
    plot.margin           = margin(25, 30, 35, 30),
    plot.title            = element_text(
      size = 14,
      hjust = 0.5,
      face = "bold",
      margin = margin(b = 4)
    ),
    plot.subtitle         = element_text(
      size = 9,
      hjust = 0.5,
      color = "#9a9589",
      margin = margin(b = 10)
    ),
    plot.caption          = element_text(
      size = 8,
      color = "#5a5650",
      hjust = 0,
      lineheight = 1.3,
      margin = margin(t = 12)
    ),
    plot.caption.position = "plot",
    legend.position       = "none"
  ) +
  labs(
    title    = "Air Pollution Follows a Daily Cycle",
    subtitle = "Average PM2.5 (µg/m³) by hour of day in Philadelphia, 2024",
    caption  = caption_text
  )

print(p)

ggsave(
  "pm25_circular_2024.png",
  plot = p,
  width = 1500,
  height = 850,
  units = "px",
  dpi = 300,
  bg = "#f5f2eb"
)