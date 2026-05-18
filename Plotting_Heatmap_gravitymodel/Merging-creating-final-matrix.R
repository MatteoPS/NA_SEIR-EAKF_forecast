library(dplyr)
library(reshape2)
library(ggplot2)
library(viridis)
library(geosphere)  # for great-circle distance (Haversine)
library(tidygeocoder)

CA_US <- read.csv("Input/CA_state_pair_tot.csv")
#doubling it to consider also US_CA (assuming mirrored flow)
CA_US$Total_Passengers = CA_US$Total_Passengers*2

MX_MX_US_CA <-read.csv("Input/MX_state_pair_tot.csv")
MX_MX_US_CA$Number_of_Routes = NULL

US_US <- read.csv("Input/US_bidirectional_state_flows.csv")
US_US$Country1 <- "United States"
US_US$Country2 <- "United States"


  

#To get CA_MX and US_MX I am doubling the passengers reported in the Mexican dataset  (assuming mirrored flow)
MX_MX_US_CA$Total_Passengers=ifelse(MX_MX_US_CA$Country1 != MX_MX_US_CA$Country2, MX_MX_US_CA$Total_Passengers*2,MX_MX_US_CA$Total_Passengers) 



Tot_no_CA_CA <-
  bind_rows(MX_MX_US_CA,US_US,CA_US)%>%
  #Set Canadian treshold. 
  filter(Total_Passengers>4000) %>%
  #remove Porto Rico and Hawaii
  filter(State1 != "Puerto Rico") %>%
  filter(State2 != "Puerto Rico") %>%
  filter(State1 != "Hawaii") %>%
  filter(State2 != "Hawaii") 



# #modify some name to be the same as the previous paper (avoids accents and stuff)
name_mapping <- c(
  "Mexico City" = "Distrito Federal",
  "State of Mexico" = "Estado de Mexico",
  "Coahuila" = "Coahuila de Zaragoza",
  "Michoacán" = "Michoacan de Ocampo",
  "Nuevo León" = "Nuevo Leon",
  "Querétaro" = "Queretaro",
  "San Luis Potosí" = "San Luis Potosi",
  "Veracruz" = "Veracruz de Ignacio de la Llave",
  "Yucatán" = "Yucatan" 
)

Tot_no_CA_CA <- Tot_no_CA_CA %>%
  mutate(
    State1 = recode(State1, !!!name_mapping),
    State2 = recode(State2, !!!name_mapping)
  )

write.csv(Tot_no_CA_CA ,"Output/tmp_all_but_CA_CA.csv",row.names = F)


### need to create CA_CA by using population density and american numbers
#Try a gravity model to infer the Total_passengers for CA-CA


# # Define mapping of your states/provinces to a representative major airport city
# airport_cities <- tribble(
#   ~state,                          ~airport,                                   ~city,
#   "Distrito Federal",               "Benito Juárez International Airport",      "Mexico City, Mexico",
#   "Jalisco",                        "Guadalajara International Airport",        "Guadalajara, Mexico",
#   "California",                     "Los Angeles International Airport",        "Los Angeles, USA",
#   "Baja California",                "Tijuana International Airport",            "Tijuana, Mexico",
#   "Quintana Roo",                   "Cancún International Airport",             "Cancún, Mexico",
#   "Florida",                        "Miami International Airport",              "Miami, USA",
#   "Chihuahua",                      "General Roberto Fierro Airport",           "Chihuahua, Mexico",
#   "Chiapas",                        "Ángel Albino Corzo Airport",               "Tuxtla Gutiérrez, Mexico",
#   "Nuevo Leon",                     "Monterrey International Airport",          "Monterrey, Mexico",
#   "Guerrero",                       "Acapulco International Airport",           "Acapulco, Mexico",
#   "Georgia",                        "Hartsfield–Jackson Atlanta Intl Airport",  "Atlanta, USA",
#   "Ontario",                        "Toronto Pearson International Airport",    "Toronto, Canada",
#   "Illinois",                       "O'Hare International Airport",             "Chicago, USA",
#   "New York",                       "John F. Kennedy International Airport",    "New York, USA",
#   "Coahuila de Zaragoza",           "Torreón International Airport",            "Torreón, Mexico",
#   "Quebec",                         "Montréal–Trudeau International Airport",   "Montreal, Canada",
#   "Campeche",                       "Ing. Alberto Acuña Ongay Airport",         "Campeche, Mexico",
#   "Colorado",                       "Denver International Airport",             "Denver, USA",
#   "New Jersey",                     "Newark Liberty International Airport",     "Newark, USA",
#   "North Carolina",                 "Charlotte Douglas International Airport",  "Charlotte, USA",
#   "Guanajuato",                     "Del Bajío International Airport",          "León, Mexico",
#   "Pennsylvania",                   "Philadelphia International Airport",       "Philadelphia, USA",
#   "Alberta",                        "Calgary International Airport",            "Calgary, Canada",
#   "Aguascalientes",                 "Lic. Jesús Terán Peredo Airport",          "Aguascalientes, Mexico",
#   "Minnesota",                      "Minneapolis–Saint Paul Intl Airport",      "Minneapolis, USA",
#   "Baja California Sur",            "Los Cabos International Airport",          "San José del Cabo, Mexico",
#   "Arizona",                        "Phoenix Sky Harbor International Airport", "Phoenix, USA",
#   "Durango",                        "General Guadalupe Victoria Airport",       "Durango, Mexico",
#   "New Hampshire",                  "Manchester–Boston Regional Airport",       "Manchester, USA",
#   "Michigan",                       "Detroit Metropolitan Airport",             "Detroit, USA",
#   "District of Columbia",           "Ronald Reagan Washington National Airport","Washington, D.C., USA",
#   "Maryland",                       "Baltimore–Washington International",       "Baltimore, USA",
#   "Queretaro",                      "Querétaro International Airport",          "Querétaro, Mexico",
#   "British Columbia",               "Vancouver International Airport",          "Vancouver, Canada",
#   "Colima",                         "Lic. Miguel de la Madrid Airport",         "Colima, Mexico",
#   "Missouri",                       "St. Louis Lambert International Airport",  "St. Louis, USA",
#   "San Luis Potosi",                "Ponciano Arriaga International Airport",   "San Luis Potosí, Mexico",
#   "Puebla",                         "Hermanos Serdán International Airport",    "Puebla, Mexico",
#   "Massachusetts",                  "Logan International Airport",              "Boston, USA",
#   "Ohio",                           "Cleveland Hopkins International Airport",  "Cleveland, USA",
#   "Nevada",                         "McCarran International Airport",           "Las Vegas, USA",
#   "Tamaulipas",                     "General Lucio Blanco International",       "Reynosa, Mexico",
#   "Texas",                          "Dallas/Fort Worth International Airport",  "Dallas, USA",
#   "Manitoba",                       "Winnipeg James Armstrong Richardson",      "Winnipeg, Canada",
#   "Michoacan de Ocampo",            "General Francisco J. Mujica Airport",      "Morelia, Mexico",
#   "Tabasco",                        "Carlos Rovirosa Pérez International",      "Villahermosa, Mexico",
#   "Sinaloa",                        "Culiacán International Airport",           "Culiacán, Mexico",
#   "Nova Scotia",                    "Halifax Stanfield International Airport",  "Halifax, Canada",
#   "Kentucky",                       "Louisville International Airport",         "Louisville, USA",
#   "Oaxaca",                         "Xoxocotlán International Airport",         "Oaxaca, Mexico",
#   "Veracruz de Ignacio de la Llave","General Heriberto Jara International",     "Veracruz, Mexico",
#   "New Brunswick",                  "Greater Moncton International",            "Moncton, Canada",
#   "Nayarit",                        "Tepic International Airport",              "Tepic, Mexico",
#   "Indiana",                        "Indianapolis International Airport",       "Indianapolis, USA",
#   "Louisiana",                      "Louis Armstrong New Orleans Intl",         "New Orleans, USA",
#   "Morelos",                        "General Mariano Matamoros Airport",        "Cuernavaca, Mexico",
#   "Connecticut",                    "Bradley International Airport",            "Hartford, USA",
#   "Estado de Mexico",               "Toluca International Airport",             "Toluca, Mexico",
#   "Tennessee",                      "Nashville International Airport",          "Nashville, USA",
#   "Alaska",                         "Ted Stevens Anchorage International",      "Anchorage, USA",
#   "Oklahoma",                       "Will Rogers World Airport",                "Oklahoma City, USA",
#   "Oregon",                         "Portland International Airport",           "Portland, USA",
#   "New Mexico",                     "Albuquerque International Sunport",        "Albuquerque, USA",
#   "Alabama",                        "Birmingham–Shuttlesworth Intl Airport",    "Birmingham, USA",
#   "Arkansas",                       "Bill and Hillary Clinton Natl Airport",    "Little Rock, USA",
#   "Utah",                           "Salt Lake City International Airport",     "Salt Lake City, USA",
#   "South Carolina",                 "Charleston International Airport",         "Charleston, USA",
#   "Idaho",                          "Boise Airport",                            "Boise, USA",
#   "Montana",                        "Billings Logan International Airport",     "Billings, USA",
#   "Nebraska",                       "Eppley Airfield",                          "Omaha, USA",
#   "Virginia",                       "Richmond International Airport",           "Richmond, USA",
#   "Iowa",                           "Des Moines International Airport",         "Des Moines, USA",
#   "Mississippi",                    "Jackson–Medgar Wiley Evers Intl Airport",  "Jackson, USA",
#   "Kansas",                         "Wichita Dwight D. Eisenhower Airport",     "Wichita, USA",
#   "Maine",                          "Portland International Jetport",           "Portland, USA",
#   "Washington",                     "Seattle–Tacoma International Airport",     "Seattle, USA",
#   "North Dakota",                   "Hector International Airport",             "Fargo, USA",
#   "South Dakota",                   "Sioux Falls Regional Airport",             "Sioux Falls, USA",
#   "Rhode Island",                   "T. F. Green Airport",                      "Providence, USA",
#   "Vermont",                        "Burlington International Airport",         "Burlington, USA",
#   "Newfoundland and Labrador",      "St. John's International Airport",         "St. John's, Canada",
#   "Prince Edward Island",           "Charlottetown Airport",                     "Charlottetown, Canada",
#   "Puerto Rico",                    "Luis Muñoz Marín International Airport",   "San Juan, Puerto Rico",
#   "Saskatchewan",                   "Saskatoon International Airport",          "Saskatoon, Canada",
#   "Wisconsin",                      "Milwaukee Mitchell International Airport", "Milwaukee, USA"
# )
# 
#
# ## Geocode city names (using OpenStreetMap Nominatim via tidygeocoder)
# 
# # commented cause API is slow
# airport_with_coords <- airport_cities %>%
#  geocode(city, method = "osm", lat = latitude , long = longitude)
# write.csv(airport_with_coords,"Input/Airport-city-coords.csv",row.names = F)
# airport_with_coords=read.csv("Input/Airport-city-coords.csv")
# coords_pop = merge(airport_with_coords,pops, by.x="state", by.y = "State")
# write.csv(coords_pop ,"Input/coords_pop.csv",row.names = F)


coords_pop<-read.csv("Input/coords_pop.csv")

#getting the population info from previous paper for gravity model
pops<-read.csv("Input/statecodes_population.csv") 


# ---- Prepare training data (all non-CA–CA flows) ----
train_df <- Tot_no_CA_CA %>%
  select(State1, State2, Total_Passengers, Country1, Country2) %>%
  # join populations + coords for both endpoints
  left_join(coords_pop %>%
              select(state, Population, latitude, longitude, CountryCode),
            by = c("State1" = "state")) %>%
  rename(pop_a = Population, lat_a = latitude, lon_a = longitude,
         country_a = CountryCode) %>%
  left_join(coords_pop %>%
              select(state, Population, latitude, longitude, CountryCode),
            by = c("State2" = "state")) %>%
  rename(pop_b = Population, lat_b = latitude, lon_b = longitude,
         country_b = CountryCode) %>%
  mutate(
    # undirected distance (km) between city centroids
    dist_km = distHaversine(
      p1 = cbind(lon_a, lat_a),
      p2 = cbind(lon_b, lat_b)
    ) / 1000
  ) %>%
  # keep only valid positive entries
  filter(Total_Passengers > 0,
         pop_a > 0, pop_b > 0,
         dist_km > 0)

# ---- Fit log-linear gravity model ----
fit <- lm(
  log(Total_Passengers) ~ log(pop_a) + log(pop_b) + log(dist_km),
  data = train_df
)

# Bias correction for log-normal back-transform
sigma2 <- summary(fit)$sigma^2

# ---- Generate all possible CA–CA pairs ----
can_nodes <- coords_pop %>%
  filter(CountryCode == "CA") %>%
  select(state, Population, latitude, longitude)

ca_pairs <- t(combn(can_nodes$state, 2)) %>%
  as.data.frame() %>%
  rename(State1 = V1, State2 = V2)

# Add populations and coords
pred_df <- ca_pairs %>%
  left_join(can_nodes, by = c("State1" = "state")) %>%
  rename(pop_a = Population, lat_a = latitude, lon_a = longitude) %>%
  left_join(can_nodes, by = c("State2" = "state")) %>%
  rename(pop_b = Population, lat_b = latitude, lon_b = longitude) %>%
  mutate(
    dist_km = distHaversine(
      p1 = cbind(lon_a, lat_a),
      p2 = cbind(lon_b, lat_b)
    ) / 1000
  )

# ---- Predict CA–CA flows ----
linpred <- predict(fit, newdata = pred_df)
flow_pred <- exp(linpred + sigma2 / 2)  # bias-corrected mean

pred_out <- pred_df %>%
  mutate(pred_flow = as.numeric(flow_pred)) %>%
  select(State1, State2, pop_a, pop_b, dist_km, pred_flow)


cat("\nGravity model coefficients:\n")
print(coef(summary(fit)))



train_df <- train_df %>%
  mutate(
    log_flow_obs = log(Total_Passengers),
    log_flow_pred = predict(fit, newdata = train_df)
  )
# extract coefficients and R2
coefs <- coef(summary(fit))
r2 <- summary(fit)$r.squared

# build annotation text with p-values
note_text <- sprintf(
  "γ_0 = %.2f (p = %.3g)\nγ_1 = %.2f (p = %.3g)\nγ_2 = %.2f (p = %.3g)\nγ_3 = %.2f (p = %.3g)\nR² = %.3f",
  coefs["(Intercept)", "Estimate"], coefs["(Intercept)", "Pr(>|t|)"],
  coefs["log(pop_a)", "Estimate"], coefs["log(pop_a)", "Pr(>|t|)"],
  coefs["log(pop_b)", "Estimate"], coefs["log(pop_b)", "Pr(>|t|)"],
  coefs["log(dist_km)", "Estimate"], coefs["log(dist_km)", "Pr(>|t|)"],
  r2
)

plot_fit=ggplot(train_df, aes(x = log_flow_pred, y = log_flow_obs)) +
  geom_point(alpha = 0.5) +
  geom_abline(slope = 1, intercept = 0, color = "red", linetype = "dashed") +
  #annotate(
  #  "text",
  #  x = min(train_df$log_flow_pred), y = max(train_df$log_flow_obs),
  #  label = note_text, hjust = 0, vjust = 1, size = 3.5
  #) +
  labs(
    x = "Predicted log(travels)",
    y = "Observed log(travels)",
 #   title = "Gravity Model Fit: Observed vs Predicted"
  ) +
  theme_minimal()

ggsave("Output/GravitiyModel_loglog.png", plot_fit,width = 16*1.2, height = 9*1.2, units = "cm", bg = "white",dpi = 400)


pred_out_processed <- pred_out %>%
  mutate(
    State_Pair = paste(State1, State2, sep = "-"),
    Total_Passengers = pred_flow,
    Country1 = "Canada",
    Country2 = "Canada"
  ) %>%
  select(State_Pair, State1, State2, Country1, Country2, Total_Passengers)

tot_pairs=bind_rows(Tot_no_CA_CA,pred_out_processed)

air_matrix<-data.frame(matrix(ncol = 96, nrow = 96))
colnames(air_matrix)=pops$State
rownames(air_matrix)=pops$State


for (a in rownames(tot_pairs)){
  i <- tot_pairs[a,"State1"]
  j <- tot_pairs[a,"State2"]
  air_matrix[i,j] <- tot_pairs[a,"Total_Passengers"]
  air_matrix[j,i] <- tot_pairs[a,"Total_Passengers"]
}

air_matrix[is.na(air_matrix)] <- 0

#assign "Ciudad de Mexico" to "Distrito Federal"
colnames(air_matrix)[colnames(air_matrix) == "Distrito Federal"] <- "Ciudad de Mexico"
rownames(air_matrix)[rownames(air_matrix) == "Distrito Federal"] <- "Ciudad de Mexico"


# Convert the matrix to a data frame and melt it to long format
air_df <- as.data.frame(as.matrix(air_matrix))
air_df$Origin <- rownames(air_df)
air_melted <- melt(air_df, id.vars = "Origin", variable.name = "Destination", value.name = "Value")

# Calculate total flows for each Origin to determine ordering
origin_totals <- air_melted %>%
  group_by(Origin) %>%
  summarize(Total = sum(Value, na.rm = TRUE)) %>%
  arrange(Total)

destination_totals <- air_melted %>%
  group_by(Destination) %>%
  summarize(Total = sum(Value, na.rm = TRUE)) %>%
  arrange(Total)

# Order factors by total flow (lowest to highest)
air_melted$Origin <- factor(air_melted$Origin, levels = rev(origin_totals$Origin))
air_melted$Destination <- factor(air_melted$Destination, levels = rev(destination_totals$Destination))

# Create the heatmap with custom color scale
heat_plot<-ggplot(air_melted, aes(x = Destination, y = Origin, fill = Value)) +
  geom_tile(color = "white", size = 0.1) +
  scale_fill_gradientn(
    #colors = c("white", viridis(9)),
    colors = c("white", colorRampPalette(c(rep("khaki1", 10), "goldenrod3"))(20)),
    values = scales::rescale(c(0, 0.01, 0.1, 1, 10, 100, 1000, 10000, 100000, max(air_melted$Value, na.rm = TRUE))),
    trans = "log10",
    na.value = "white",
    name = "Air Passengers\n(log scale)",
    guide = guide_colorbar(barwidth = 0.8, barheight = 10)
  ) +
  theme_minimal() +
  theme(
    axis.text.x = element_text(angle = 90, hjust = 1, vjust = 0.5, size = 6),
    axis.text.y = element_text(size = 6),
    axis.title = element_blank(),
    plot.title = element_text(face = "bold", hjust = 0.5),
    legend.position = "right",
    panel.grid = element_blank()
  ) +
  coord_fixed()

# 1. Define the order: Least passengers to Most (origin_totals is already Least->Most)
ordered_locs <- origin_totals$Origin

# 2. Order factors: X (Left to Right) = Least to Most, Y (Top to Bottom) = Least to Most
air_melted$Destination <- factor(air_melted$Destination, levels = ordered_locs)
air_melted$Origin <- factor(air_melted$Origin, levels = rev(ordered_locs))

# 3. Create the dataframe for diagonal labels
diag_labels <- data.frame(
  Destination = factor(ordered_locs, levels = ordered_locs),
  Origin = factor(ordered_locs, levels = rev(ordered_locs)),
  Label = ordered_locs
)

# 4. Filter for Lower Triangular (Bottom-Left half)
air_melted_tri <- subset(air_melted, 
                         match(Destination, ordered_locs) <= match(Origin, ordered_locs))

# 5. Generate the plot
heat_plot_tri <- ggplot(air_melted_tri, aes(x = Destination, y = Origin, fill = Value)) +
  geom_tile(color = "white", linewidth = 0.1) + 
  scale_fill_gradientn(
    colors = c("white", colorRampPalette(c(rep("khaki1", 10), "goldenrod3"))(20)),
    values = scales::rescale(c(0, 0.01, 0.1, 1, 10, 100, 1000, 10000, 100000, max(air_melted$Value, na.rm = TRUE))),
    trans = "log10",
    na.value = "white",
    name = "Air Passengers\n(log scale)",
    guide = guide_colorbar(barwidth = 0.8, barheight = 10)
  ) +
  # Adds the labels strictly to the right of the diagonal cells
  geom_text(data = diag_labels, aes(x = Destination, y = Origin, label = Label), 
            inherit.aes = FALSE, nudge_x = 0.5, hjust = 0, size = 2) +
  theme_minimal() +
  theme(
    # Restores default bottom x-axis text formatting
    axis.text.x = element_text(angle = 90, hjust = 1, vjust = 0.5, size = 6), 
    axis.text.y = element_blank(),   
    axis.ticks.y = element_blank(),  
    axis.title = element_blank(),
    plot.title = element_text(face = "bold", hjust = 0.5),
    legend.position = "left",
    panel.grid = element_blank(),
    plot.margin = margin(10, 100, 10, 10) # Preserves right-side space for diagonal labels
  ) +
  coord_fixed(clip = "off") 

# 1. Define the order: Most passengers to Least
ordered_locs_desc <- rev(origin_totals$Origin)

# 2. Order factors: X (Left to Right) = Most to Least, Y (Bottom to Top) = Most to Least
air_melted$Destination <- factor(air_melted$Destination, levels = ordered_locs_desc)
air_melted$Origin <- factor(air_melted$Origin, levels = ordered_locs_desc)

# 3. Create the dataframe for diagonal labels
diag_labels2 <- data.frame(
  Destination = factor(ordered_locs_desc, levels = ordered_locs_desc),
  Origin = factor(ordered_locs_desc, levels = ordered_locs_desc),
  Label = ordered_locs_desc
)

# 4. Filter for Bottom-Right Triangle (Keeps cells where X index >= Y index)
air_melted_tri2 <- subset(air_melted, 
                          match(Destination, ordered_locs_desc) >= match(Origin, ordered_locs_desc))

# 5. Generate the plot
heat_plot_tri2 <- ggplot(air_melted_tri2, aes(x = Destination, y = Origin, fill = Value)) +
  geom_tile(color = "white", linewidth = 0.1) + 
  scale_fill_gradientn(
    colors = c("white", colorRampPalette(c(rep("khaki1", 10), "goldenrod3"))(20)),
    values = scales::rescale(c(0, 0.01, 0.1, 1, 10, 100, 1000, 10000, 100000, max(air_melted$Value, na.rm = TRUE))),
    trans = "log10",
    na.value = "white",
    name = "Air Passengers\n(log scale)",
    guide = guide_colorbar(barwidth = 0.8, barheight = 10)
  ) +
  # nudge_x = -0.5 pushes text to the left edge; hjust = 1 right-aligns the text to end at that edge
  geom_text(data = diag_labels2, aes(x = Destination, y = Origin, label = Label), 
            inherit.aes = FALSE, nudge_x = -0.5, hjust = 1, size = 2) +
  theme_minimal() +
  theme(
    axis.text.x = element_text(angle = 90, hjust = 1, vjust = 0.5, size = 6), 
    axis.text.y = element_blank(),   
    axis.ticks.y = element_blank(),  
    axis.title = element_blank(),
    plot.title = element_text(face = "bold", hjust = 0.5),
    legend.position = "right",
    panel.grid = element_blank(),
    # Swapped margin space to the left side (100) so the bottom-left label isn't clipped
    plot.margin = margin(10, 10, 10, 100) 
  ) +
  coord_fixed(clip = "off") 


#ggsave("Matrix-air-flow.png", heat_plot,width = 22, height = 20, units = "cm", bg = "white")
#ggsave("Matrix-air-flow-tri.png", heat_plot_tri,width = 22, height = 20, units = "cm", bg = "white")
ggsave("Matrix-air-flow-tri2.png", heat_plot_tri2,width = 22, height = 20, units = "cm", bg = "white")
#ggsave("Gravitymodel-fit.png", plot_fit,width = 17, height = 20, units = "cm", bg = "white")








#write.table(air_matrix,"Matrix-air-flow.csv", sep = ",", col.names = FALSE, row.names = FALSE)
