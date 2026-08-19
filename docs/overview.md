# gsensros - Project Overview

gsensros is a Garmin Connect IQ watch face application designed for dive and land-based motion tracking. It runs on Garmin devices (tested on Instinct 2X Solar) and provides real-time monitoring of navigation metrics including dead reckoning position, GPS position, depth, heading, motion state, speed estimation, and nitrogen loading.

## Key Features

- **Motion Detection**: Multi-stage motion detection using accelerometer and gyroscope data with adaptive baseline learning and hysteresis
- **GPS Tracking**: Continuous GPS location updates with quality-based validation
- **Heading Estimation**: Hierarchical heading source selection (true heading → magnetometer → gyro integration → dead reckoning fallback)
- **Dead Reckoning**: 2D position tracking using speed and heading with GPS correction
- **Kalman Filter**: 4-state Kalman filter for GPS-corrected east/north position estimation
- **Depth Estimation**: Altitude-based depth calculation with surface calibration, strict validation of barometric values, and automatic recalibration
- **Dive State Detection**: Starts at 0.5 m depth and ends only when the user is back at 0.5 m or shallower and within 5 m of the start GPS point
- **Nitrogen Loading**: Simplified Haldane-style multi-tissue nitrogen model for dive risk assessment
- **FIT Recording**: Activity recording with custom FIT fields for post-dive analysis
- **UI Display**: Real-time watch display of all tracking metrics with scrollable layout

## Device and Build Info

| Property | Value |
|----------|-------|
| App ID | `61261946-ed35-4393-ba9e-faa0acae21f5` |
| Entry Class | `gsensrosApp` |
| Target Product | `instinct2x` |
| Min API Level | `3.4.0` |
| App Type | `watch-app` |
| Build Output | `build/gsensros.prg` |
| FIT Contributions | `build/gsensros-fit_contributions.json` |

## Permissions Required

| Permission | Purpose |
|------------|---------|
| Sensor | Accelerometer, gyroscope, magnetometer data |
| SensorHistory | Historical sensor data access |
| SensorLogging | Sensor logging support |
| Positioning | GPS location access |
| Fit | Activity recording and FIT file creation |
| FitContributor | Custom FIT field creation |
| Communications | Bluetooth connectivity |
| BluetoothLowEnergy | BLE device communication |
| Ant | ANT+ sensor support |
| Notifications | Notification delivery |
| PushNotification | Push notification support |
| UserProfile | User profile access |
| PersistedContent | Data persistence |
| PersistedLocations | Location data persistence |
| ComplicationPublisher | Watch face complication publishing |

## Project Structure

```
gsensros/
├── manifest.xml                   # App manifest
├── monkey.jungle                  # Build configuration (project.manifest = manifest.xml)
├── ConfirmStopDelegate.mc         # Confirmation dialog delegate (root-level source)
├── source/                        # Monkey C source directory
│   ├── gsensrosApp.mc           # Application entry point
│   ├── gsensrosView.mc          # Main view (1488 lines, core logic)
│   ├── gsensrosDelegate.mc      # Input behavior delegate
│   ├── gsensrosMenuDelegate.mc  # Menu delegate (placeholder)
│   ├── DeadReckoning.mc           # DR engine (334 lines)
│   ├── KalmanDR.mc                # Kalman filter (107 lines)
│   └── NitrogenModel.mc           # Nitrogen model (100 lines)
├── resources/
│   ├── drawables/
│   │   ├── drawables.xml
│   │   ├── launcher_icon.svg
│   │   └── monkey.png
│   ├── layouts/
│   │   └── layout.xml
│   ├── menus/
│   │   └── menu.xml
│   └── strings/
│       └── strings.xml
└── docs/                          # This documentation
```