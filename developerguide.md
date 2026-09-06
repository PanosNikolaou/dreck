# Garmin Connect IQ Developer Guide
## DRFusionTrack Implementation Notes

## 1. Purpose

This guide documents the current implementation of DRFusionTrack as it exists in source, with emphasis on the latest runtime changes in depth estimation, motion fallback, simulation behavior, and diagnostics.

## 2. Runtime Architecture

Primary files:

- [source/gsensrosApp.mc](source/gsensrosApp.mc)
- [source/gsensrosView.mc](source/gsensrosView.mc)
- [source/gsensrosDelegate.mc](source/gsensrosDelegate.mc)
- [source/gsensrosMenuDelegate.mc](source/gsensrosMenuDelegate.mc)
- [source/DeadReckoning.mc](source/DeadReckoning.mc)
- [source/KalmanDR.mc](source/KalmanDR.mc)
- [source/NitrogenModel.mc](source/NitrogenModel.mc)
- [ConfirmStopDelegate.mc](ConfirmStopDelegate.mc)

Responsibility summary:

- App class wires the view and delegates.
- View owns lifecycle, sensor reads, depth/motion state, DR/KF updates, and FIT writes.
- Delegates handle key and menu behavior.
- DR/Kalman classes maintain local coordinate tracking.

## 3. Main Loop

`timerCallback()` runs every 500 ms and performs:

1. dt calculation
2. sensor and position reads
3. depth update via `updateDepth(sensorInfo, posInfo)`
4. GPS state update
5. depth-state transition processing
6. motion confidence update
7. DR/Kalman update
8. throttled FIT writes
9. screen refresh

## 4. Depth Model (Current)

Depth source selection order:

1. direct depth fields (`depth`, `enhancedDepth`)
2. pressure fields (`pressure`, `ambientPressure`)
3. altitude fields (`altitude`, `enhancedAltitude`, `Position.Info.altitude`)
4. simulator fallback (`SIM`) when no real source exists and altitude remains flat

Pressure units are normalized:

- hPa to Pa when value looks like ~800 to ~1200
- kPa to Pa when value looks like ~80 to ~120

Depth stabilization stages:

- startup calibration
- jump/rate limiting
- low-pass filtering
- physical clamping

Depth source tag (`depthSourceTag`) is exposed in UI/logs for diagnostics:

- `D`, `P`, `ALT`, `GPS_ALT`, `SIM`, `NONE`

## 5. Motion Model (Current)

Motion confidence blends multiple signals:

- IMU-based motion score
- GPS speed when valid
- Kalman displacement-derived speed fallback (`kfDerivedSpeedMps`)

This prevents simulator sessions from being stuck in stationary mode when IMU payloads are sparse.

## 6. FIT Recording Model

Core record fields include:

- DR_East, DR_North
- Depth, DepthActive
- Speed, Heading
- Motion, Moving, GpsFix
- DR_Lat, DR_Lon
- POI fields
- optional DR_Diag

Write helpers suppress redundant writes by epsilon/change thresholds.

## 7. Diagnostics and Troubleshooting

Runtime diagnostics:

- `DRDIAG`: compact motion/heading/GPS state logging
- `DEPTHDBG`: depth-source and intermediate values (`rawAlt`, `alt0`, `pPa`, `pDepth`, `aDepth`, final depth)

Debug behavior:

- `isDebugLoggingEnabled()` now defaults to enabled when no explicit setting exists.

## 8. Simulation vs Device Behavior

Real device expectation:

- pressure/direct-depth should dominate and produce physically meaningful depth

Simulator limitation seen in latest validation:

- no pressure available
- altitude fixed at a constant value
- real depth mathematically remains zero in this environment

To keep integration testable, simulator fallback may synthesize depth when source is flat/noisy and no real depth sensor exists.

## 9. Build and Run

Use project wrapper script:

```bash
cd /home/panagiotis/Documents/gsensors/gsensros
./run_simulation.sh --build-only
./run_simulation.sh --run-only
```

## 10. Recommended Validation Workflow

1. Build with `--build-only`.
2. Run with `--run-only`.
3. Confirm UI shows expected `Dsrc` value.
4. For simulator: verify `DEPTHDBG` behavior matches source assumptions.
5. Export FIT and compare with reference route/depth data.

## 11. Safety Statement

DRFusionTrack is for telemetry/research use. It is not a certified dive computer and must not be the sole instrument for dive safety decisions.
