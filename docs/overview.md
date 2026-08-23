# DRFusionTrack - Project Overview

DRFusionTrack is a Garmin Connect IQ app for underwater navigation, sensor fusion, and activity logging on wearable hardware. It combines ambient pressure, motion sensors, GPS quality gating, and a local dead-reckoning model to create a practical underwater tracking system for Garmin watches.

## Current status

The current implementation is the authoritative state of the project. It is designed around these principles:

- pressure is the primary source for depth,
- the live surface reference is created from the first valid pressure sample,
- shallow values are preserved rather than discarded during startup,
- underwater transitions are gated by hysteresis and time-based stability,
- DR continues smoothly through GPS gaps and poor fix conditions,
- FIT output contains the telemetry needed for later review and analysis.

## Key features

- pressure-first depth estimation with altitude validation,
- underwater and surface detection with stop/start hysteresis,
- adaptive motion confidence tracking,
- heading estimation from the strongest valid signal,
- dead-reckoning propagation in a local East/North space,
- GPS correction when fixes are fresh and usable,
- custom FIT export for depth, motion, speed, heading, and GPS state,
- UI and logging support for dive-style session review.

## Device and build info

| Property | Value |
|----------|-------|
| App Name | DRFusionTrack |
| App ID | `61261946-ed35-4393-ba9e-faa0acae21f5` |
| Entry Class | `drFusionTrackApp` |
| Target Product | `instinct2x` |
| Min API Level | `3.4.0` |
| App Type | `watch-app` |
| Build Output | `build/gsensros.prg` |
| FIT Contributions | `build/gsensros-fit_contributions.json` |

## Depth and motion model summary

The current depth logic is tuned to match real dive behavior rather than a noisy startup baseline:

- primary source: ambient pressure,
- secondary source: altitude difference from a calibrated reference,
- rejection: negative or impossible values are clipped,
- filtering: a responsive low-pass stage stabilizes the depth trace,
- calibration: the first valid surface pressure becomes the active baseline.

The motion and heading logic uses the strongest available signal while staying conservative under noisy water conditions. This is critical because the app must remain stable when GPS is weak or when the user is moving in shallow water.

## Permissions required

| Permission | Purpose |
|------------|---------|
| Sensor | Raw motion, pressure, and orientation data |
| Positioning | GPS fix access |
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
├── source/
│   ├── gsensrosApp.mc
│   ├── gsensrosView.mc
│   ├── DeadReckoning.mc
│   ├── KalmanDR.mc
│   ├── NitrogenModel.mc
│   └── ...
├── resources/
│   ├── drawables/
│   ├── layouts/
│   ├── menus/
│   └── strings/
├── docs/
├── README.md
├── garmin_dive_app_documentation.md
├── Dead_Reckoning_Kalman_Garmin_Report.md
├── dreck.tex
├── build/
└── fit/
```