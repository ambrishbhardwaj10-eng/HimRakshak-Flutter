# HimRakshak AI

HimRakshak AI is an experimental mountain hazard
decision-support application focused on Uttarakhand, India.

The application combines environmental data,
official alerts, location information and an
experimental risk-calculation engine.

> HimRakshak AI is not an official government
> emergency-warning system.

Users should always follow warnings and instructions
issued by authorized government agencies.

---

## Features

### Current GPS Location

The application detects the user's current GPS
location and displays it on the map.

Users can also:

- Search locations
- Tap locations on the map
- Analyse another place
- Return to their current location
- View Uttarakhand on the map

---

## Official Disaster Alerts

HimRakshak integrates the NDMA SACHET public alert
feed.

Official alerts are displayed separately from
HimRakshak's experimental risk calculations.

Possible alerts include:

- Heavy rainfall
- Flood warnings
- Landslide-related warnings
- Severe weather
- Other disaster alerts

Source:

NDMA SACHET / authorized issuing agencies.

---

## IMD Official Observations

The application contains support for official
India Meteorological Department observations.

Possible values include:

- Temperature
- Humidity
- Wind speed
- 24-hour rainfall
- Observation station
- Observation date and time

IMD API authentication must be configured before
official IMD observations become available.

If official observation data cannot be retrieved,
HimRakshak will display:

"No official observation available"

The application will not create or fabricate an
official IMD reading.

---

## HimRakshak Experimental Risk Engine

HimRakshak calculates experimental:

- Landslide indicator
- Flood indicator
- Overall hazard indicator

Scores are displayed from 0 to 100.

These scores are not official probabilities.

For example:

Landslide Indicator: 78/100

does not mean there is officially a 78% probability
of a landslide.

---

## Landslide Calculation

The current experimental landslide model uses:

- Rainfall: 45%
- Soil moisture: 30%
- Elevation: 20%
- Wind: 5%

Conceptually:

Rainfall
+
Soil moisture
+
Elevation
+
Wind
=
Experimental landslide indicator

---

## Flood Calculation

The current experimental flood model uses:

- Rainfall: 70%
- Soil moisture: 20%
- Next 12-hour rainfall: 10%

The higher value between the landslide and flood
indicators is currently used as the overall
experimental risk indicator.

---

## Explainable Risk

HimRakshak attempts to explain why a risk score is
elevated.

Examples:

- Heavy recent rainfall
- Forecast rainfall
- Wet soil
- High elevation
- Strong wind

This makes the experimental score easier to
understand instead of showing only a number.

---

## Map

HimRakshak supports Mapbox when a Mapbox access
token is configured.

Available modes:

- Satellite
- Hybrid
- Terrain / 3D

If Mapbox is not configured, the application falls
back to OpenStreetMap.

Existing functionality including GPS, location
search and map tapping remains available.

---

## Data Sources

The application can use several different data
sources.

### Official information

- India Meteorological Department
- NDMA SACHET

### Location information

- OpenStreetMap Nominatim

### Experimental model inputs

- Open-Meteo
- Elevation/environmental information

Official information and experimental calculations
are intentionally displayed separately.

---

## Data Freshness

Official observation cards show observation and
fetch timestamps when available.

Users should check the observation time before
making decisions.

Older observations may not represent current
conditions.

---

## Critical Alerts

The app can generate local Android notifications
when the experimental HimRakshak risk crosses the
configured critical threshold.

These notifications are:

Experimental HimRakshak notifications.

They are not official IMD, NDMA or government
emergency notifications.

Official alerts are displayed separately.

---

## GitHub Secrets

The GitHub Actions workflow supports the following
repository secrets.

### MAPBOX_ACCESS_TOKEN

Used for Mapbox maps.

Add it in:

Settings
→ Secrets and variables
→ Actions
→ New repository secret

Secret name:

MAPBOX_ACCESS_TOKEN

---

### IMD_AUTH_HEADER_NAME

Authentication header name supplied for your IMD
API access.

---

### IMD_AUTH_HEADER_VALUE

Authentication header value supplied for your IMD
API access.

Never hardcode private API credentials directly
inside main.dart.

---

## Build

The Android APK is automatically generated using
GitHub Actions.

Workflow:

.github/workflows/build-apk.yml

The workflow performs:

1. Flutter setup
2. Android project generation
3. Android permissions configuration
4. Dependency installation
5. Flutter analysis
6. Release APK build
7. APK artifact upload

---

## Android Permissions

The application requires:

- Internet
- Fine location
- Coarse location
- Notifications

Location permissions are required to determine the
user's GPS position.

---

## Safety Disclaimer

HimRakshak AI is an experimental research and
decision-support application.

It should not be used as the sole source for
emergency decisions.

The calculated 0–100 risk indicators are heuristic
experimental indicators and are not official
probabilities.

Always follow authorized alerts from agencies such
as:

- IMD
- NDMA
- State Disaster Management Authorities
- District administration
- Other authorized emergency agencies

In an emergency, contact the appropriate local
emergency services and follow official evacuation
instructions.
