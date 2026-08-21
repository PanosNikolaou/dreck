# gsensros - Project Overview

gsensros is a Garmin Connect IQ app for dive/tracking workflows on wearable devices. It combines GPS, inertial sensing, pressure-derived depth estimation, and FIT export to build a practical underwater tracking and logging system for Garmin watches.

## Current status

The most recent fix was the depth pipeline correction. The app now starts from a valid pressure baseline immediately instead of waiting for the full calibration cycle, which avoids the false zero-depth behavior seen when comparing against the Suunto Ocean reference log.

## Key features

- Pressure-first depth estimation with altitude fallback and validation
- Startup calibration that keeps the first valid pressure sample as the live surface reference
- Non-physical depth spike rejection and clamp logic
- Dive-state detection with hysteresis and shallow-water logic
- Motion detection using motion score, gyro magnitude, and adaptive baseline tracking
- GPS quality gating and dead-reckoning fallback when the position signal degrades
- FIT output for DR position, depth, speed, heading, motion, GPS fix, and underwater state
- Nitrogen loading model and UI summary outputs

## Device and build info

| Property | Value |
|----------|-------|
| App ID | `61261946-ed35-4393-ba9e-faa0acae21f5` |
| Entry Class | `gsensrosApp` |
| Target Product | `instinct2x` |
| Min API Level | `3.4.0` |
| App Type | `watch-app` |
| Build Output | `build/gsensros.prg` |
| FIT Contributions | `build/gsensros-fit_contributions.json` |

## Depth algorithm summary

The current depth logic is designed to match realistic dive traces, not just the altitude sensor:

- primary source: ambient pressure
- secondary source: altitude difference from a calibrated surface level
- rejection: negative or impossible values are clipped to zero
- filtering: a low-pass smoothing stage damps transient sensor spikes
- calibration: first valid surface pressure becomes the baseline for the live dive trace

This is the core change that corrected the discrepancy against the Suunto Ocean samples.

## Permissions required

| Permission | Purpose |
|------------|---------|
| Sensor | Accelerometer, gyroscope, magnetometer, and pressure/altitude data |
| Positioning | GPS location access |
| Fit | Activity session creation and FIT serialization |
| FitContributor | Custom FIT field creation |
| Communications | Bluetooth and app-to-device communication |
| BluetoothLowEnergy | BLE device communication |
| Ant | ANT+ support |
| Notifications | UI and alert support |
| PushNotification | Push notification support |
| UserProfile | User profile access |
| PersistedContent | Data persistence |
| PersistedLocations | Persisted location storage |
| ComplicationPublisher | Complication support |

## Project structure

```text
gsensros/
├── manifest.xml
├── monkey.jungle
├── ConfirmStopDelegate.mc
├── source/
│   ├── gsensrosApp.mc
│   ├── gsensrosView.mc
│   ├── gsensrosDelegate.mc
│   ├── gsensrosMenuDelegate.mc
│   ├── DeadReckoning.mc
│   ├── KalmanDR.mc
│   └── NitrogenModel.mc
├── resources/
│   ├── drawables/
│   ├── layouts/
│   ├── menus/
│   └── strings/
├── docs/
├── README.md
├── garmin_dive_app_documentation.md
├── Dead_Reckoning_Kalman_Garmin_Report.md
└── build/
```