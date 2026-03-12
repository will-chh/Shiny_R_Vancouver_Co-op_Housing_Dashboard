# =========================================================
# Vancouver Non-Market Housing Dashboard - Shiny for R
# R translation of the Python app.py
# =========================================================
# ---------------------------
# Libraries
# ---------------------------
library(shiny)
library(bslib)
library(dplyr)
library(plotly)
library(DT)
library(jsonlite)
library(ellmer)
library(querychat)
library(dotenv)

# Load repo-root .env explicitly
if (file.exists("../.env")) {
  dotenv::load_dot_env("../.env")
}

# ---------------------------
# Data layer
# ---------------------------

# Read the raw CSV exactly like the Python app
data <- read.csv(
  "../data/raw/non-market-housing.csv",
  sep = ";",
  check.names = FALSE,
  stringsAsFactors = FALSE
)

# Fix the inconsistent column name if it exists
if ("Clientele- Families" %in% names(data)) {
  names(data)[names(data) == "Clientele- Families"] <- "Clientele - Families"
}

# Keep completed projects only
data <- data %>%
  filter(`Project Status` == "Completed")

# Create the combined clientele label
data$Clientele <- "Mixed"
data$Clientele[
  data$`Clientele - Seniors` == 0 & data$`Clientele - Other` == 0
] <- "Families"
data$Clientele[
  data$`Clientele - Families` == 0 & data$`Clientele - Other` == 0
] <- "Seniors"

# Create bedroom availability flags
room_types <- c("1BR", "2BR", "3BR", "4BR", "Studio")

for (br in room_types) {
  br_cols <- grepl(br, names(data), fixed = TRUE)
  data[[paste0(br, " Available")]] <- as.integer(
    rowSums(data[, br_cols, drop = FALSE], na.rm = TRUE) > 0
  )
}

# Create accessibility availability flags
access_types <- c("Accessible", "Adaptable", "Standard")

for (ac in access_types) {
  ac_cols <- grepl(ac, names(data), fixed = TRUE)
  data[[paste0(ac, " Available")]] <- as.integer(
    rowSums(data[, ac_cols, drop = FALSE], na.rm = TRUE) > 0
  )
}

# Create total units
data$`Total Units` <- 
  data$`Clientele - Families` +
  data$`Clientele - Seniors` +
  data$`Clientele - Other`

# ---------------------------
# QueryChat data for AI tab
# ---------------------------

# Keep the same cleaner AI-facing subset as in Python
ai_data <- data %>%
  select(
    `Index Number`,
    Name,
    Address,
    Operator,
    Clientele,
    `Occupancy Year`,
    `Total Units`,
    `1BR Available`,
    `2BR Available`,
    `3BR Available`,
    `4BR Available`,
    `Studio Available`,
    `Accessible Available`,
    `Adaptable Available`,
    `Standard Available`
  )

# ---------------------------
# AI client setup
# ---------------------------

# Same system prompt idea as Python
chat_client <- ellmer::chat_anthropic(
  model = "claude-sonnet-4-0",
  system_prompt = paste(
    "You help users explore a Vancouver non-market housing dataset.",
    "Translate user questions into correct data queries.",
    "Use only the dataset columns that exist.",
    "Do not invent fields or values."
  )
)

# Same QueryChat object idea as Python
qc <- querychat::QueryChat$new(
  ai_data,
  table_name = "vancouver_non_market_housing",
  client = chat_client,
  greeting = paste(
    "Hello! I'm here to help you explore and analyze the Vancouver non-market housing data. You can ask me to filter, sort, or answer questions about the dataset.",
    "",
    "Here are some ideas to get started:",
    "",
    "Explore the data",
    "* Show me all housing units for seniors",
    "* What is the average number of total units?",
    "",
    "Filter and sort",
    "* Filter to mixed clientele housing with 2BR available",
    "* Sort the housing projects by occupancy year descending",
    sep = "\n"
  )
)

# ---------------------------
# Helper functions
# ---------------------------

# Parse a GeoJSON Point stored in the Geom column
parse_point <- function(x) {
  tryCatch({
    obj <- jsonlite::fromJSON(x)

    # Return missing coords if it is not a Point geometry
    if (is.null(obj$type) || obj$type != "Point") {
      return(c(NA_real_, NA_real_))
    }

    coords <- obj$coordinates

    # Return lon, lat
    c(as.numeric(coords[[1]]), as.numeric(coords[[2]]))
  }, error = function(e) {
    c(NA_real_, NA_real_)
  })
}

# Match the Python zoom helper
zoom_for_bounds <- function(lon_min, lon_max, lat_min, lat_max) {
  lon_range <- max(1e-6, lon_max - lon_min)
  lat_range <- max(1e-6, lat_max - lat_min)
  max_range <- max(lon_range, lat_range)

  if (max_range > 30) return(2)
  if (max_range > 15) return(3)
  if (max_range > 8)  return(4)
  if (max_range > 4)  return(5)
  if (max_range > 2)  return(6)
  if (max_range > 1)  return(7)
  if (max_range > 0.5) return(8)
  if (max_range > 0.25) return(9)
  if (max_range > 0.12) return(10)
  if (max_range > 0.06) return(11)
  if (max_range > 0.03) return(12)

  13
}

# ---------------------------
# UI layer
# ---------------------------

app_ui <- bslib::page_fillable(
  tags$style(HTML("
    #map, #map > div {
      height: 100% !important;
    }

    #map .js-plotly-plot,
    #map .plot-container,
    #map .svg-container {
      height: 100% !important;
    }

    /* AI Explorer layout */
    .ai-explorer-page {
      height: calc(100vh - 140px);
      overflow: hidden;
    }

    .ai-explorer-page .bslib-sidebar-layout {
      height: 100%;
      overflow: hidden;
    }

    .ai-explorer-page .sidebar {
      height: 100%;
      overflow-y: auto;
    }

    .ai-results-col {
      height: 100%;
      min-height: 0;
      overflow: hidden;
      display: flex;
      flex-direction: column;
    }

    .ai-results-col > .row,
    .ai-results-col .col,
    .ai-results-col .card {
      height: 100%;
      min-height: 0;
    }

    .ai-results-col .card {
      display: flex;
      flex-direction: column;
      overflow: hidden;
    }

    .ai-results-col .card-body {
      flex: 1;
      min-height: 0;
      overflow-y: auto;
    }
  ")),

  tags$h2(
    "Non-market Housing Dashboard for the City of Vancouver",
    style = "text-align:center; font-weight:700; font-size:40px;"
  ),

  tags$p(
    "Below are the buildings that match your selections.",
    style = "text-align:center; margin-top:-8px; font-size:24px; color:#666;"
  ),

  bslib::navset_tab(

    # ---------------------------
    # Dashboard tab
    # ---------------------------
    bslib::nav_panel(
      "Dashboard",

      bslib::page_sidebar(
        sidebar = bslib::sidebar(
          tags$h4("Filters"),

          checkboxGroupInput(
            "clientele",
            "Clientele",
            choices = c("Families", "Seniors", "Mixed")
          ),

          selectizeInput(
            "br",
            "Bedrooms",
            choices = c("1BR", "2BR", "3BR", "4BR"),
            multiple = TRUE
          ),

          selectizeInput(
            "accessible",
            "Accessibility",
            choices = c("Standard", "Adaptable", "Accessible"),
            multiple = TRUE
          ),

          dateRangeInput(
            "year",
            "Year",
            start = as.Date("1971-01-01"),
            end = as.Date("2025-12-31"),
            min = as.Date("1971-01-01"),
            max = as.Date("2025-12-31"),
            format = "yyyy",
            startview = "decade"
          ),

          actionButton(
            "reset",
            "Reset Filters",
            class = "btn btn-secondary",
            style = "margin-top: 15px; width: 100%;"
          )
        ),

        div(
          bslib::layout_columns(

            # Total units card
            bslib::card(
              tags$h4(
                "Total Buildings Count",
                style = "color:#ffffff; text-align:center; font-weight:500;"
              ),

              div(
                textOutput("total_units_card"),
                style = paste(
                  "font-size:48px;",
                  "font-weight:bold;",
                  "text-align:center;",
                  "color:#ffffff;",
                  "text-shadow:1px 1px 3px rgba(0,0,0,0.3);"
                )
              ),

              style = paste(
                "background: linear-gradient(135deg, #6c5ce7, #a29bfe);",
                "border-radius:15px;",
                "padding:25px;",
                "height:200px;",
                "box-shadow:0 6px 15px rgba(0,0,0,0.08);"
              )
            ),

            # Buildings summary card
            bslib::card(
              tags$h4(
                "Buildings Summary",
                style = "text-align:center; font-weight:500; color:#2d3436;"
              ),

              div(
                DTOutput("building_table"),
                style = paste(
                  "width:100%;",
                  "max-height:240px;",
                  "overflow-y:auto;",
                  "background-color:#ffffff;",
                  "padding:10px;"
                )
              ),

              style = paste(
                "border-radius:15px;",
                "box-shadow:0 2px 8px rgba(0,0,0,0.08);",
                "background-color:#ffffff;",
                "border:1px solid #dfe6e9;",
                "display:flex;",
                "flex-direction:column;",
                "align-items:center;"
              )
            ),

            col_widths = c(4, 8)
          ),

          bslib::card(
            tags$h4("Map"),

            div(
              plotlyOutput("map", height = "50vh"),
              style = "height:50vh;"
            ),

            style = paste(
              "margin-top:20px;",
              "flex-grow:1;",
              "display:flex;",
              "flex-direction:column;"
            )
          )
        )
      )
    ),

    # ---------------------------
    # AI Explorer tab
    # ---------------------------
    bslib::nav_panel(
      "AI Explorer",

      div(
        bslib::page_sidebar(
          sidebar = qc$sidebar(),

          div(
            bslib::card(
              bslib::card_header(textOutput("ai_title")),

              DTOutput("ai_data_table"),

              downloadButton(
                "download_data",
                "Download Data",
                class = "btn btn-primary"
              ),

              full_screen = TRUE
            ),
            class = "ai-results-col"
          )
        ),
        class = "ai-explorer-page"
      )
    )
  )
)

# ---------------------------
# Server layer
# ---------------------------

server <- function(input, output, session) {

  # Start QueryChat server logic
  qc_vals <- qc$server()

  # AI card title
  output$ai_title <- renderText({
    current_title <- qc_vals$title()

    if (is.null(current_title) || !nzchar(current_title)) {
      "AI-filtered housing dataset"
    } else {
      current_title
    }
  })

  # AI data table
  output$ai_data_table <- DT::renderDT({
    DT::datatable(
      qc_vals$df(),
      options = list(
        pageLength = 10,
        scrollX = TRUE
      ),
      rownames = FALSE
    )
  })

  # Main dashboard reactive filtered dataframe
  df <- reactive({
    filtered_data <- data

    # Filter by clientele
    if (!is.null(input$clientele) && length(input$clientele) > 0) {
      filtered_data <- filtered_data %>%
        filter(Clientele %in% input$clientele)
    }

    # Filter by bedrooms
    if (!is.null(input$br) && length(input$br) > 0) {
      br_list <- paste0(input$br, " Available")

      filtered_data <- filtered_data[
        rowSums(filtered_data[, br_list, drop = FALSE] > 0, na.rm = TRUE) > 0,
        ,
        drop = FALSE
      ]
    }

    # Filter by accessibility
    if (!is.null(input$accessible) && length(input$accessible) > 0) {
      access_list <- paste0(input$accessible, " Available")

      filtered_data <- filtered_data[
        rowSums(filtered_data[, access_list, drop = FALSE] > 0, na.rm = TRUE) > 0,
        ,
        drop = FALSE
      ]
    }

    # Filter by occupancy year range
    if (!is.null(input$year) && length(input$year) == 2) {
      year_start <- as.integer(format(input$year[1], "%Y"))
      year_end <- as.integer(format(input$year[2], "%Y"))

      filtered_data <- filtered_data %>%
        filter(
          `Occupancy Year` >= year_start,
          `Occupancy Year` <= year_end
        )
    }

    filtered_data
  })

  # Total units card
  output$total_units_card <- renderText({
    format(
      sum(df()[["Total Units"]], na.rm = TRUE),
      big.mark = ",",
      scientific = FALSE,
      trim = TRUE
    )
  })

  # Buildings summary table
  output$building_table <- DT::renderDT({
    DT::datatable(
      df() %>%
        select(`Index Number`, Name, `Occupancy Year`) %>%
        arrange(`Occupancy Year`),
      options = list(
        pageLength = 8,
        dom = "t",
        scrollY = "220px",
        scrollCollapse = TRUE
      ),
      rownames = FALSE
    )
  })

  # Extract point coordinates from GeoJSON
  df_points <- reactive({
    d <- df()

    # Return empty data frame if there is no mapable data
    if (nrow(d) == 0 || !"Geom" %in% names(d)) {
      d$lon <- numeric(0)
      d$lat <- numeric(0)
      return(d[0, , drop = FALSE])
    }

    coords <- t(vapply(d$Geom, parse_point, numeric(2)))

    d$lon <- coords[, 1]
    d$lat <- coords[, 2]

    d %>%
      filter(!is.na(lon), !is.na(lat))
  })

  # Map output
  output$map <- plotly::renderPlotly({
    d <- df_points()

    # Vancouver fallback if no rows
    default_center <- list(lat = 49.2827, lon = -123.1207)
    default_zoom <- 10

    token <- Sys.getenv("MAPBOX_TOKEN")
    has_token <- nzchar(token)

    map_style <- if (has_token) "streets" else "open-street-map"

    # Empty fallback map
    if (nrow(d) == 0) {
      mapbox_cfg <- list(
        style = map_style,
        zoom = default_zoom,
        center = default_center
      )

      if (has_token) {
        mapbox_cfg$accesstoken <- token
      }

      fig <- plot_ly(
        type = "scattermapbox",
        lat = c(default_center$lat),
        lon = c(default_center$lon),
        marker = list(size = 1, opacity = 0),
        hoverinfo = "none"
      ) %>%
        layout(
          mapbox = mapbox_cfg,
          margin = list(l = 0, r = 0, t = 0, b = 0),
          height = 600
        )

      return(fig)
    }

    # Compute map center and zoom from filtered bounds
    lon_min <- min(d$lon, na.rm = TRUE)
    lon_max <- max(d$lon, na.rm = TRUE)
    lat_min <- min(d$lat, na.rm = TRUE)
    lat_max <- max(d$lat, na.rm = TRUE)

    center <- list(
      lon = as.numeric((lon_min + lon_max) / 2),
      lat = as.numeric((lat_min + lat_max) / 2)
    )

    zoom <- zoom_for_bounds(lon_min, lon_max, lat_min, lat_max)

    # Build hover text
    d$hover_text <- paste0(
      "<b>", d$Name, "</b><br>",
      "Address: ", d$Address, "<br>",
      "Occupancy Year: ", d$`Occupancy Year`, "<br>",
      "Clientele: ", d$Clientele, "<br>",
      "Operator: ", d$Operator
    )

    mapbox_cfg <- list(
      style = map_style,
      zoom = zoom,
      center = center
    )

    if (has_token) {
      mapbox_cfg$accesstoken <- token
    }

    plot_ly(
      data = d,
      type = "scattermapbox",
      lat = ~lat,
      lon = ~lon,
      color = ~Clientele,
      text = ~hover_text,
      hoverinfo = "text",
      marker = list(size = 9, opacity = 0.75)
    ) %>%
      layout(
        mapbox = mapbox_cfg,
        margin = list(l = 0, r = 0, t = 0, b = 0),
        autosize = TRUE
      )
  })

  # Reset filters button
  observeEvent(input$reset, {

    updateCheckboxGroupInput(
      session,
      "clientele",
      selected = character(0)
    )

    updateSelectizeInput(
      session,
      "br",
      selected = character(0)
    )

    updateSelectizeInput(
      session,
      "accessible",
      selected = character(0)
    )

    updateDateRangeInput(
      session,
      "year",
      start = as.Date("1971-01-01"),
      end = as.Date("2025-12-31")
    )
  })

  # Download the AI-filtered table
  output$download_data <- downloadHandler(
    filename = function() {
      "filtered_data.csv"
    },
    content = function(file) {
      write.csv(qc_vals$df(), file, row.names = FALSE)
    }
  )
}

# ---------------------------
# App launch
# ---------------------------
shinyApp(app_ui, server)