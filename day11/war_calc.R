library(Lahman)
library(dplyr)

data("People")
data("Batting")
data("Pitching")

batting_war <- Batting %>%
  group_by(playerID) %>%
  summarise(bWAR = sum(WAR, na.rm = TRUE), .groups = "drop")

pitching_war <- Pitching %>%
  group_by(playerID) %>%
  summarise(pWAR = sum(WAR, na.rm = TRUE), .groups = "drop")

career_war <- batting_war %>%
  full_join(pitching_war, by = "playerID") %>%
  mutate(
    bWAR      = replace(bWAR, is.na(bWAR), 0),
    pWAR      = replace(pWAR, is.na(pWAR), 0),
    total_war = bWAR + pWAR
  )

top5 <- People %>%
  filter(!is.na(weight), !is.na(debut), weight > 100, weight < 400) %>%
  mutate(
    debut_year   = as.integer(substr(debut, 1, 4)),
    decade       = floor(debut_year / 10) * 10,
    decade_label = paste0(decade, "s")
  ) %>%
  filter(decade >= 1980, decade <= 2020) %>%
  left_join(career_war, by = "playerID") %>%
  group_by(decade_label) %>%
  slice_max(order_by = total_war, n = 5) %>%
  ungroup() %>%
  select(decade_label, nameFirst, nameLast, weight, total_war) %>%
  arrange(decade_label, desc(total_war))

print(top5, n = 25)