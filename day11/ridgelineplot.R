# MLB Player Weight by Debut Decade — Ridgeline Plot
# =====================================================
# install.packages(c("Lahman", "ggridges", "showtext", "dplyr", "ggplot2"))

library(Lahman)
library(dplyr)
library(ggplot2)
library(ggridges)
library(showtext)

showtext_auto()
font_add_google("Lato", "lato")

# ── 1. Pull and clean data ────────────────────────────────────
data("People")

players <- People %>%
  filter(!is.na(weight), !is.na(debut), weight > 100, weight < 400) %>%
  mutate(
    debut_year   = as.integer(substr(debut, 1, 4)),
    decade       = floor(debut_year / 10) * 10,
    decade_label = paste0(decade, "s")
  ) %>%
  filter(decade >= 1980, decade <= 2020) %>%
  mutate(
    decade_label = factor(decade_label,
                          levels = c("2020s","2010s","2000s","1990s","1980s"))
  )

# ── 2. Medians ────────────────────────────────────────────────
medians <- players %>%
  group_by(decade_label) %>%
  summarise(
    med_weight = median(weight),
    n          = n(),
    .groups    = "drop"
  ) %>%
  mutate(
    decade_num = as.numeric(factor(decade_label,
                                   levels = c("2020s","2010s","2000s","1990s","1980s")))
  )

cat("\nSummary:\n")
print(medians %>% select(decade_label, n, med_weight))

# ── 3. Colors ─────────────────────────────────────────────────
decade_colors <- c(
  "1980s" = "#c7e9b4",
  "1990s" = "#7fcdbb",
  "2000s" = "#41b6c4",
  "2010s" = "#2c7fb8",
  "2020s" = "#253494"
)

# ── 4. Plot ───────────────────────────────────────────────────
p <- ggplot(players, aes(
  x     = weight,
  y     = decade_label,
  fill  = decade_label,
  color = decade_label
)) +
  
  geom_density_ridges(
    alpha          = 0.75,
    scale          = 1.0,
    bandwidth      = 8,
    linewidth      = 0.5,
    rel_min_height = 0.005
  ) +
  
  # Tall median lines
  geom_segment(
    data = medians,
    aes(
      x    = med_weight,
      xend = med_weight,
      y    = decade_num,
      yend = decade_num + 0.5
    ),
    color       = "#0f0e0c",
    alpha = 0.7,
    linewidth   = 0.8,
    inherit.aes = FALSE,
    linetype = 2
  ) +
  
  # Median labels above the line
  geom_text(
    data = medians,
    aes(
      x     = med_weight,
      y     = decade_num + 0.53,
      label = paste0(round(med_weight), " lbs")
    ),
    color       = "#0f0e0c",
    size        = 6.5,
    family      = "lato",
    fontface    = "bold",
    vjust       = 0,
    hjust       = 0.5,
    inherit.aes = FALSE
  ) +
  
  scale_fill_manual(values  = decade_colors) +
  scale_color_manual(values = decade_colors) +
  
  scale_x_continuous(
    limits = c(140, 295),
    breaks = seq(150, 280, by = 25),
    labels = function(x) paste0(x, " lbs")
  ) +
  
  labs(
    title    = "MLB Players Have Gotten Heavier Since the 1980s",
    subtitle = "Distribution of player weight by debut decade · Vertical bar marks the median weight",
    x        = NULL,
    y        = NULL,
    caption  = paste0(
      "Source: Lahman Baseball Database.\n",
      "Notes: Includes all MLB players with recorded weight who debuted 1980–2024. ",
      "Weight values are self-reported at debut registration. ",
      "Each player counted once at debut."
    )
  ) +
  
  theme_ridges(font_family = "lato", font_size = 16) +
  theme(
    plot.background        = element_rect(fill = "#f5f2eb", color = NA),
    panel.background       = element_rect(fill = "#f5f2eb", color = NA),
    plot.title             = element_text(size = 22, face = "bold", color = "#0f0e0c", margin = margin(b = 6)),
    plot.subtitle          = element_text(size = 14, color = "#696969", margin = margin(b = 20)),
    plot.caption           = element_text(size = 11, color = "#696969", hjust = 0, lineheight = 1.4, margin = margin(t = 14)),
    plot.caption.position  = "plot",
    axis.text.x            = element_text(size = 22, color = "#696969"),
    axis.text.y            = element_text(size = 22, color = "#0f0e0c", face = "bold"),
    plot.margin            = margin(20, 30, 20, 20),
    legend.position        = "none",
    panel.grid.major.x     = element_line(color = "#e0dbd0", linewidth = 0.4),
    panel.grid.major.y     = element_blank()
  )

print(p)

ggsave(
  "mlb_weight_ridgeline.png",
  plot   = p,
  width  = 10,
  height = 8,
  units  = "in",
  dpi    = 200,
  bg     = "#f5f2eb"
)

cat("Saved → mlb_weight_ridgeline.png\n")