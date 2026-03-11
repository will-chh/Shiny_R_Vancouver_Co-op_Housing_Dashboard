#Script Structure for CLARITY, this shit confusing af
# Data Layer: Does filtering, encoding, label creations, and some data wrangling
# UI Layer: app_ui, this defines what the user sees, like side bar holds filters as inputs, and main area holds charts as output
# Server Layer: the reactive logic - and controls what runs when filter changes
#   df() -> apply sidebar filters to data
#   @render/reactive.text/table/calc/ploty/effect -> all this stuff controls and plots the charts
# App Layer: the last line, it just renders stuff

#Impoting things Mileston 2
from shiny import App, ui, reactive, render
import pandas as pd
from datetime import date

import os
import json
import numpy as np
import plotly.express as px
from shinywidgets import output_widget, render_plotly

#Imports for AI Milestone 3 
from pathlib import Path
from dotenv import load_dotenv
from chatlas import ChatAnthropic
import querychat

#Setting up the AI agent
# two .parent is for going back to repo root to find the .env for our SECRETS and API keys 
load_dotenv(Path(__file__).resolve().parent.parent / ".env")

chat_client = ChatAnthropic(
    model="claude-sonnet-4-0",
    system_prompt=(
        "You help users explore a Vancouver non-market housing dataset. "
        "Translate user questions into correct data queries. "
        "Use only the dataset columns that exist. "
        "Do not invent fields or values."
    ),
)

# Data wrangling
data = pd.read_csv('data/raw/non-market-housing.csv', sep=';')

data.rename(columns={'Clientele- Families': 'Clientele - Families'}, inplace=True)
data = data.loc[data['Project Status'] == 'Completed']

data['Clientele'] = 'Mixed'
data.loc[(data['Clientele - Seniors'] == 0) & (data['Clientele - Other'] == 0), 'Clientele'] = 'Families'
data.loc[(data['Clientele - Families'] == 0) & (data['Clientele - Other'] == 0), 'Clientele'] = 'Seniors'

room_types = ['1BR', '2BR', '3BR', '4BR', 'Studio']
for br in room_types:
    data[f'{br} Available'] = (data.filter(like=br).sum(axis=1) > 0).astype('int')

access_types = ['Accessible', 'Adaptable', 'Standard']
for ac in access_types:
    data[f'{ac} Available'] = (data.filter(like=ac).sum(axis=1) > 0).astype('int')

data['Total Units'] = (
    data['Clientele - Families'] + 
    data['Clientele - Seniors'] + 
    data['Clientele - Other']
)

#QUERYCHAT 
# ai_data gives QueryChat a cleaner table to work with.
# It avoids geometry/extra columns that are less useful for natural-language querying.
ai_data = data[[
    "Index Number",
    "Name",
    "Address",
    "Operator",
    "Clientele",
    "Occupancy Year",
    "Total Units",
    "1BR Available",
    "2BR Available",
    "3BR Available",
    "4BR Available",
    "Studio Available",
    "Accessible Available",
    "Adaptable Available",
    "Standard Available"
]].copy()

qc = querychat.QueryChat(
    ai_data,
    "vancouver_non_market_housing",
    client=chat_client,
    greeting="""Hello! I'm here to help you explore and analyze the Vancouver non-market housing data. You can ask me to filter, sort, or answer questions about the dataset.

Here are some ideas to get started:

Explore the data
* Show me all housing units for seniors
* What is the average number of total units?

Filter and sort
* Filter to mixed clientele housing with 2BR available
* Sort the housing projects by occupancy year descending"""
)


# defining layout
app_ui = ui.page_fillable(
    ui.tags.style("""
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
    """),

    ui.h2(
        "Non-market Housing Dashboard for the City of Vancouver",
        style="text-align:center; font-weight:700; font-size: 40px"
    ),
    ui.p(
        "Below are the buildings that match your selections.",
        style="text-align:center; margin-top:-8px; font-size: 24px; color:#666;"
    ),

    ui.navset_tab(

        ui.nav_panel(
            "Dashboard",
            ui.page_sidebar(
                ui.sidebar(
                    ui.h4("Filters"),
                    ui.input_checkbox_group(
                        "clientele",
                        "Clientele",
                        ["Families", "Seniors", "Mixed"]
                    ),
                    ui.input_selectize(
                        "br",
                        "Bedrooms",
                        ["1BR", "2BR", "3BR", "4BR"],
                        multiple=True
                    ),
                    ui.input_selectize(
                        "accessible",
                        "Accessibility",
                        ["Standard", "Adaptable", "Accessible"],
                        multiple=True
                    ),
                    ui.input_slider(
                        "year",
                        "Year",
                        min=date(1971, 1, 1), max=date(2025, 12, 31),
                        value=[date(1971, 1, 1), date(2025, 12, 31)],
                        time_format="%Y"
                    ),
                    ui.input_action_button(
                        "reset",
                        "Reset Filters",
                        class_="btn btn-secondary",
                        style="margin-top: 15px; width: 100%;"
                    )
                ),

                ui.div(
                    ui.layout_columns(
                        ui.card(
                            ui.h4(
                                "Total Buildings Count",
                                style="color: #ffffff; text-align: center; font-weight: 500;"
                            ),
                            ui.div(
                                ui.output_text("total_units_card"),
                                style="""
                                    font-size: 48px;
                                    font-weight: bold;
                                    text-align: center;
                                    color: #ffffff;
                                    text-shadow: 1px 1px 3px rgba(0,0,0,0.3);
                                """
                            ),
                            style="""
                                background: linear-gradient(135deg, #6c5ce7, #a29bfe);
                                border-radius: 15px;
                                padding: 25px;
                                height: 200px;
                                box-shadow: 0 6px 15px rgba(0,0,0,0.08);
                            """
                        ),

                        ui.card(
                            ui.h4(
                                "Buildings Summary",
                                style="text-align: center; font-weight: 500; color: #2d3436;"
                            ),
                            ui.div(
                                ui.output_table("building_table"),
                                style="""
                                    width: 100%;
                                    max-height: 240px;
                                    overflow-y: auto;
                                    background-color: #ffffff;
                                    padding: 10px;
                                """
                            ),
                            style="""
                                border-radius: 15px;
                                box-shadow: 0 2px 8px rgba(0,0,0,0.08);
                                background-color: #ffffff;
                                border: 1px solid #dfe6e9;
                                display: flex;
                                flex-direction: column;
                                align-items: center;
                            """
                        ),
                        col_widths=[4, 8]
                    ),

                    ui.card(
                        ui.h4("Map"),
                        ui.div(
                            output_widget("map"),
                            style="height: 50vh;"
                        ),
                        style="""
                            margin-top: 20px;
                            flex-grow: 1;
                            display: flex;
                            flex-direction: column;
                        """
                    )
                )
            )
        ),

        ui.nav_panel(
            "AI Explorer",
            ui.div(
                ui.page_sidebar(
                    qc.sidebar(),
                    ui.div(
                        ui.card(
                            ui.card_header(ui.output_text("ai_title")),
                            ui.output_data_frame("ai_data_table"),
                            ui.download_button("download_data", "Download Data", class_="btn-primary"),
                            full_screen=True
                        ),
                        class_="ai-results-col"
                    )
                ),
                class_="ai-explorer-page"
            )
        )
    )
)


# defining logic and reactivity
def server(input, output, session):
    qc_vals = qc.server()
    # chat = ui.Chat("housing_chat") #connects the server to the UI chat box

    # @chat.on_user_submit #runs everytime the user sends a message
    # async def handle_user_input(user_input: str):
    #     response = await chat_client.stream_async(user_input) #sends the prompt to Claude
    #     await chat.append_message_stream(response) #streams the response back to the app

    @output
    @render.text
    def ai_title():
        return qc_vals.title() or "AI-filtered housing dataset"

    @output
    @render.data_frame
    def ai_data_table():
        return render.DataGrid(qc_vals.df())

    @reactive.calc
    def df():
        filtered_data = data.copy()

        if input.clientele():
            filtered_data = filtered_data[
                filtered_data.Clientele.isin(input.clientele())
            ]

        if input.br():
            br_list = [i + " Available" for i in input.br()]
            filtered_data = filtered_data[
                (filtered_data[br_list] > 0).any(axis=1)
            ]

        if input.accessible():
            access_list = [i + " Available" for i in input.accessible()]
            filtered_data = filtered_data[
                (filtered_data[access_list] > 0).any(axis=1)
            ]

        years = input.year()
        filtered_data = filtered_data[
            (filtered_data['Occupancy Year'] >= years[0].year) &
            (filtered_data['Occupancy Year'] <= years[1].year)
        ]

        return filtered_data
    
    @output
    @render.text
    def total_units_card():
        return f"{int(df()['Total Units'].sum()):,}"
    
    @output
    @render.table
    def building_table():
        return df()[[
            "Index Number",
            "Name",
            "Occupancy Year"
        ]].sort_values("Occupancy Year")
    
    @reactive.calc
    def df_points():
        """Extract lon/lat from GeoJSON Point stored in 'Geom'."""
        d = df().copy()

        def parse_point(s):
            try:
                obj = json.loads(s) if isinstance(s, str) else s
                if obj.get("type") != "Point":
                    return (np.nan, np.nan)
                lon, lat = obj.get("coordinates", [np.nan, np.nan])
                return (lon, lat)
            except Exception:
                return (np.nan, np.nan)

        coords = d["Geom"].apply(parse_point)
        d["lon"] = coords.apply(lambda x: x[0])
        d["lat"] = coords.apply(lambda x: x[1])
        return d.dropna(subset=["lon", "lat"])

    def _zoom_for_bounds(lon_min, lon_max, lat_min, lat_max):
        lon_range = max(1e-6, lon_max - lon_min)
        lat_range = max(1e-6, lat_max - lat_min)
        max_range = max(lon_range, lat_range)

        if max_range > 30:  return 2
        if max_range > 15:  return 3
        if max_range > 8:   return 4
        if max_range > 4:   return 5
        if max_range > 2:   return 6
        if max_range > 1:   return 7
        if max_range > 0.5: return 8
        if max_range > 0.25:return 9
        if max_range > 0.12:return 10
        if max_range > 0.06:return 11
        if max_range > 0.03:return 12
        return 13

    @render_plotly
    def map():
        d = df_points()

        # Vancouver fallback (if filters return 0 rows)
        default_center = {"lat": 49.2827, "lon": -123.1207}
        default_zoom = 10

        token = os.getenv("MAPBOX_TOKEN")

        if token:
            px.set_mapbox_access_token(token)
            map_style = "streets"
        else:
            map_style = "open-street-map"

        if len(d) == 0:
            fig = px.scatter_mapbox(
                pd.DataFrame({"lat": [default_center["lat"]], "lon": [default_center["lon"]]}),
                lat="lat",
                lon="lon",
                zoom=default_zoom,
                center=default_center,
            )
            fig.update_traces(marker={"size": 1, "opacity": 0.0}, hoverinfo="skip")
            fig.update_layout(mapbox_style=map_style, margin=dict(l=0, r=0, t=0, b=0), height=600)
            return fig

        lon_min, lon_max = d["lon"].min(), d["lon"].max()
        lat_min, lat_max = d["lat"].min(), d["lat"].max()
        center = {"lon": float((lon_min + lon_max) / 2), "lat": float((lat_min + lat_max) / 2)}
        zoom = _zoom_for_bounds(lon_min, lon_max, lat_min, lat_max)

        fig = px.scatter_mapbox(
            d,
            lat="lat",
            lon="lon",
            color='Clientele',
            hover_name="Name" if "Name" in d.columns else None,
            hover_data=[c for c in ["Address", "Occupancy Year", "Clientele", "Operator"] if c in d.columns],
            zoom=zoom,
            center=center,
        )
        fig.update_traces(marker={"size": 9, "opacity": 0.75})
        fig.update_layout(mapbox_style=map_style, margin=dict(l=0, r=0, t=0, b=0), autosize=True)
        return fig
    
    @reactive.effect
    @reactive.event(input.reset)
    def _():
        ui.update_checkbox_group(
            "clientele",
            selected=[]
        )

        ui.update_selectize(
            "br",
            selected=[]
        )

        ui.update_selectize(
            "accessible",
            selected=[]
        )

        ui.update_slider(
            "year",
            value=[date(1971, 1, 1), date(2025, 12, 31)]
        )

    @render.download(filename="filtered_data.csv")
    def download_data():
        yield ai_data_table.data_view().to_csv()

# For App Rendering, this line must be at the last
app = App(app_ui, server=server)