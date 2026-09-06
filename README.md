#HimRakshak AI — Official Data Upgrade

This package is a drop-in replacement for the three files you shared.


Added


#NDMA SACHET official CAP/RSS alert feed integration.

#IMD official observation integration scaffold using the official Current Weather API.

#Clear separation between official observations/alerts and the experimental HimRakshak 0–100 score.

Data timestamps / freshness labels.

Explainable risk card ("Why is this score high?").

Optional Mapbox map upgrade:
Satellite
Hybrid (Mapbox Standard Satellite)
Terrain / 3D

Existing OSM map remains as a fallback if no Mapbox token is configured.

Existing GPS, search, map tap, risk calculation and local critical notifications are preserved.


#GitHub Actions secrets

Create these repository secrets:



#MAPBOX_ACCESS_TOKEN

Public Mapbox access token used by the mobile SDK.

IMD_AUTH_HEADER_NAME


IMD_AUTH_HEADER_VALUE

Use the exact authentication header name/value provided by your IMD API account.
These are intentionally configurable because the public IMD API reference documents endpoints/fields but not a universal public authentication header scheme.


If the IMD secrets are absent, the app does NOT invent an observation. It displays that official observation access is not configured.


Important safety behavior

The HimRakshak 0–100 score remains an experimental weighted heuristic.
It is NOT an official probability or government warning.


Official NDMA/IMD information is displayed separately and should take precedence.

