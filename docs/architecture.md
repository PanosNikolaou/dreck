# DRFusionTrack Architecture

## Component Graph

```text
drFusionTrackApp
  └── creates gsensrosView + delegates
        ├── gsensrosView
        │     ├── DeadReckoning
        │     ├── KalmanDR
        │     ├── NitrogenModel
        │     ├── Sensor.getInfo + sensor listener
        │     ├── Position.getInfo + position events
        │     └── timerCallback (500 ms)
        ├── gsensrosDelegate
        ├── gsensrosMenuDelegate
        └── ConfirmStopDelegate
```

## Layers

### 1. Lifecycle and Input Delegates

- [../source/gsensrosApp.mc](../source/gsensrosApp.mc): app entry
- [../source/gsensrosView.mc](../source/gsensrosView.mc): runtime state owner
- [../source/gsensrosDelegate.mc](../source/gsensrosDelegate.mc): key/select/menu behavior
- [../source/gsensrosMenuDelegate.mc](../source/gsensrosMenuDelegate.mc): menu-specific actions
- [../ConfirmStopDelegate.mc](../ConfirmStopDelegate.mc): stop-session confirmation flow

### 2. Sensor and Position Acquisition

- periodic pull via `Sensor.getInfo()` and `Position.getInfo()`
- event updates via location listener and sensor data callback
- null-safe handling of sparse simulator payloads

### 3. Estimation and State

- depth source tracker with tagged source (`P`, `D`, `ALT`, `GPS_ALT`, `SIM`, `NONE`)
- pressure normalization (Pa/hPa/kPa)
- altitude and pressure blending when both exist
- simulator-only synthetic depth when no real source exists and altitude is flat
- motion confidence from IMU + GPS + Kalman displacement fallback
- DR + Kalman local east/north propagation and correction

### 4. Recording and Diagnostics

- FIT record fields for depth, motion, moving, GPS fix, heading, DR coordinates, and POIs
- write helpers avoid redundant values
- runtime diagnostics include `DRDIAG` and `DEPTHDBG` for source-level tracing

## Depth Design (Current)

Priority order in [../source/gsensrosView.mc](../source/gsensrosView.mc):

1. direct depth (`depth` or `enhancedDepth`)
2. pressure depth from (`pressure` or `ambientPressure`)
3. altitude depth from (`altitude`, `enhancedAltitude`, or `Position.Info.altitude`)
4. simulator synthetic depth fallback for testability

Depth is clamped, rate-limited, and low-pass filtered before becoming `currentDepth`.

## Motion Design (Current)

- IMU motion score remains primary for real hardware.
- If IMU is weak in simulator, Kalman displacement-derived speed is used as a fallback signal.
- Moving state gates DR advancement and feeds FIT `Moving` telemetry.

## Constraints

The app is a custom Connect IQ watch app, not a certified dive-computer runtime. Design choices favor stable telemetry and debuggable behavior under mixed sensor quality.