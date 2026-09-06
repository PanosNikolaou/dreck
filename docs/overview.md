# DRFusionTrack - Project Overview

DRFusionTrack is a Garmin Connect IQ watch app that fuses sensor data, motion cues, dead reckoning, and FIT logging for underwater session analysis.

## Latest Status

The latest commits introduced three important runtime upgrades:

1. depth source tracking and diagnostics in [source/gsensrosView.mc](../source/gsensrosView.mc)
2. motion-threshold refactor with Kalman-motion fallback for simulator behavior
3. simulator synthetic depth fallback when no pressure/direct-depth feed exists and altitude is flat

## Operational Model

Depth source order:

1. direct depth (`depth` or `enhancedDepth`)
2. pressure depth (`pressure` or `ambientPressure`, normalized from Pa/hPa/kPa)
3. altitude depth (`altitude`, `enhancedAltitude`, or `Position.Info.altitude`)
4. simulator fallback (`SIM`) only in no-real-depth source mode

Motion state:

- IMU-driven motion score where available
- GPS speed gating when quality is valid
- Kalman displacement speed fallback to avoid false stationary lock in simulator

## App Structure

- [../source/gsensrosApp.mc](../source/gsensrosApp.mc)
- [../source/gsensrosView.mc](../source/gsensrosView.mc)
- [../source/gsensrosDelegate.mc](../source/gsensrosDelegate.mc)
- [../source/gsensrosMenuDelegate.mc](../source/gsensrosMenuDelegate.mc)
- [../source/DeadReckoning.mc](../source/DeadReckoning.mc)
- [../source/KalmanDR.mc](../source/KalmanDR.mc)
- [../source/NitrogenModel.mc](../source/NitrogenModel.mc)

## Build Target

- product: `instinct2x`
- app type: `watch-app`
- Connect IQ SDK: auto-detected latest under `~/.Garmin/ConnectIQ/Sdks`

## Known Simulation Limitation

Some simulator runs provide no pressure input and a constant altitude sample. In this case, real depth cannot be derived from sensors. The code now marks source `SIM` and emits synthetic depth for validation of UI/FIT flow only.