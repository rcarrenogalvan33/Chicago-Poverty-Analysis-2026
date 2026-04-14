# ==============================================================================
# PROJECT: Chicago Socioeconomic Analysis (2026)
# PURPOSE: Predict Community Area Poverty Using Non-Linear GAM Models
# AUTHOR: Rebe
# DATA: ACS 5-Year Estimates by Community Area
# ==============================================================================

# 1. SETUP & LIBRARIES ---------------------------------------------------------

# 'pacman' is a pro-tip: it installs missing packages and loads them automatically
if (!require("pacman")) install.packages("pacman")
pacman::p_load(tidyverse, janitor, mgcv, sf, scales)

# 2. DATA IMPORT ---------------------------------------------------------------

# Using read_csv (from tidyverse) is faster and better at guessing data types 
raw_data <- read.csv("ACS_5_Year_Data_by_Community_Area_20260413.csv", 
                     stringsAsFactors = FALSE)

# 3. DATA CLEANING -------------------------------------------------------------

chicago_clean <- raw_data %>%
  # Standardize column names (removes spaces, makes lowercase)
  clean_names() %>%
  
  # Rename columns for clarity (matching your previous work)
  rename_with(~ str_replace(., "x_", "inc_"), starts_with("x_")) %>%
  rename(inc_under_25k = under_25_000) %>%
  
  # Clean numeric columns: Remove commas and convert to numeric in one go
  # We use 'across' to apply the fix to multiple columns efficiently
  mutate(across(
    c(inc_under_25k, total_population, hispanic_or_latino, black_or_african_american), 
    ~ as.numeric(str_remove_all(., ","))
  )) %>%
  
  # Create our Target Variable: Poverty Rate
  mutate(poverty_rate = (inc_under_25k / total_population) * 100) %>%
  
  # Final string cleaning for the mapping join later
  mutate(community_area = str_to_upper(str_trim(community_area)))

# Quick check to ensure types are correct
glimpse(chicago_clean)

# 4. STATISTICAL MODELING ------------------------------------------------------

# --- Model A: Baseline Linear Regression ---
# We start with OLS to test the linear relationship between demographics and poverty.

model_linear <- lm(poverty_rate ~ hispanic_or_latino + black_or_african_american, 
                   data = chicago_clean)

# Reviewing the baseline:
# Note: Initial OLS showed low R-squared (~20%) and violated several assumptions.
summary(model_linear)

# --- Model B: Advanced Analysis (GAM) ---
# Transitioning to Generalized Additive Models to capture non-linearities 
# and "threshold effects" across Chicago's diverse 77 community areas.

library(mgcv)

model_gam <- gam(poverty_rate ~ s(hispanic_or_latino) + s(black_or_african_american), 
                 data = chicago_clean, 
                 method = "REML")

# Reviewing the upgrade:
# The GAM improved explained deviance to ~37.4%, a significant boost in accuracy.
summary(model_gam)

# 5. ASSUMPTION TESTING --------------------------------------------------------

# Visualizing residuals and basis functions to validate the GAM.
# A critical step for ensuring policy recommendations are based on sound math.

par(mfrow = c(2, 2))
gam.check(model_gam)

# This tells R to show 4 plots at once so we can see the "health" of the model
par(mfrow = c(2, 2)) 

# Step A: Check the Multiple Linear Regression (model_2)
# We do this to show why a linear model WASN'T enough.
# Look for: "Fanning" patterns or curved residuals here.
plot(model_linear) # This is your model_2

# Step B: Transition to GAM
# We use s() to tell R: "Find the best curve for this variable"
# REML is the standard "best fit" method to prevent over-fitting.
model_gam <- gam(poverty_rate ~ s(hispanic_or_latino) + s(black_or_african_american), 
                 data = chicago_clean, 
                 method = "REML")

# Step C: Validate the "Curvy" Results
# This produces 4 diagnostic plots AND a printed report in your console.
# This proves the GAM fixed the issues we saw in plot(model_linear).
gam.check(model_gam)

# Look at the summary to see the 'Effective Degrees of Freedom' (edf)
summary(model_gam)

# 6. GEOSPATIAL VISUALIZATION & MAPPING ----------------------------------------

# --- A. Load Shapefile ---
# Using your simplified name 'chi_map'
chi_shp <- st_read("chi_map") %>%
  mutate(community = str_to_upper(str_trim(community)))

# --- B. Add Predictions and Join ---
# Adding the GAM results to the dataset before joining to the map
chicago_clean$predicted_poverty <- predict(model_gam, type = "response")

map_final <- chi_shp %>%
  left_join(chicago_clean, by = c("community" = "community_area"))

# --- C. Identify Highlight Areas (Top/Bottom 5) ---
# We calculate centroids here so the white-box labels sit perfectly in the center
highlight_points <- map_final %>%
  arrange(desc(predicted_poverty)) %>%
  slice(c(1:5, (n()-4):n())) %>%
  st_centroid() %>%
  mutate(x = st_coordinates(.)[,1],
         y = st_coordinates(.)[,2])

# --- D. Final Map Visual ---
ggplot(data = map_final) +
  geom_sf(aes(fill = predicted_poverty), color = "white", size = 0.2) +
  # Adding the white-background labels you requested
  geom_label(
    data = highlight_points, 
    aes(x = x, y = y, label = community), 
    size = 2.5, 
    fill = "white", 
    color = "black", 
    fontface = "bold",
    label.padding = unit(0.15, "lines")
  ) +
  scale_fill_viridis_c(
    option = "inferno", 
    name = "Predicted %\nInc < $25k",
    labels = label_number(suffix = "%")
  ) +
  theme_minimal() +
  labs(
    title = "Socioeconomic Drivers of Chicago Poverty (2026)",
    subtitle = "Top and bottom 5 areas predicted by GAM analysis",
    caption = "Source: Chicago Data Portal & ACS 2023 | Analysis by Rebe"
  ) +
  theme(
    panel.grid = element_blank(),
    axis.text = element_blank(),
    axis.title = element_blank()
  )