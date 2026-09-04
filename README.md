# HimRakshak AI — Flutter Live MVP

Live/near-live Uttarakhand mountain-hazard decision-support app.

## Live data
Uses Open-Meteo hourly precipitation, soil moisture, wind and temperature data for monitored Uttarakhand locations. The displayed hazard scores are transparent MVP heuristics and are **not** an official early-warning model.

## Build APK in GitHub Actions
1. Push this repository to GitHub.
2. Open **Actions** → **Build HimRakshak APK**.
3. Tap **Run workflow**.
4. After completion, download the artifact **HimRakshak-release-apk**.
5. Extract it on Android; inside is `app-release.apk`.

The workflow creates the Android platform project automatically, so only Flutter source files are stored here.
