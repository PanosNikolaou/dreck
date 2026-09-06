# DRFusionTrack

DRFusionTrack is a Garmin Connect IQ watch app for underwater navigation, motion tracking, dead reckoning, and FIT logging. It targets Instinct-class devices and is designed for robust field telemetry and post-session analysis.

## What Is New (Latest 3-4 Commits)

- Added explicit depth source tracking in runtime (`P`, `D`, `ALT`, `GPS_ALT`, `SIM`, `NONE`).
- Refactored motion thresholds and added Kalman-derived motion fallback so movement can still be inferred when simulator IMU feeds are weak.
- Added simulator-safe synthetic depth fallback when pressure/direct-depth is unavailable and altitude is flat.
- Expanded diagnostics (`DEPTHDBG`) and improved session logging/trace visibility.
- Added and integrated delegates for interaction flow:
	- [source/gsensrosDelegate.mc](source/gsensrosDelegate.mc)
	- [source/gsensrosMenuDelegate.mc](source/gsensrosMenuDelegate.mc)

## Core Runtime Behavior

Depth source priority in [source/gsensrosView.mc](source/gsensrosView.mc):

1. direct depth (`depth` or `enhancedDepth`) if present
2. pressure-derived depth (`pressure` or `ambientPressure`, unit-normalized to Pa)
3. altitude-derived depth (`altitude`, `enhancedAltitude`, or `Position.Info.altitude`)
4. simulator synthetic depth fallback (only when no real pressure/direct-depth and altitude is flat)

Motion state combines IMU evidence and fallback cues:

- motion score from accelerometer/gyro pipeline
- GPS speed when valid
- Kalman displacement-derived speed fallback in low-sensor simulation cases

## Main Components

- [source/gsensrosApp.mc](source/gsensrosApp.mc): app entry and view wiring
- [source/gsensrosView.mc](source/gsensrosView.mc): primary runtime loop, depth, motion, DR/KF, FIT write
- [source/gsensrosDelegate.mc](source/gsensrosDelegate.mc): key/button behavior
- [source/gsensrosMenuDelegate.mc](source/gsensrosMenuDelegate.mc): menu flow bindings
- [source/DeadReckoning.mc](source/DeadReckoning.mc): DR propagation
- [source/KalmanDR.mc](source/KalmanDR.mc): local filter and corrections
- [source/NitrogenModel.mc](source/NitrogenModel.mc): lightweight N2/risk telemetry model

## Build And Run

```bash
cd /home/panagiotis/Documents/gsensors/gsensros
./run_simulation.sh --build-only
./run_simulation.sh --run-only
```

If `.run_simulation.sh` is used (missing `/`), the shell returns command not found. Use `./run_simulation.sh`.

## Documentation

- [docs/DOCUMENTATION.md](docs/DOCUMENTATION.md)
- [docs/overview.md](docs/overview.md)
- [docs/architecture.md](docs/architecture.md)
- [docs/data-flow.md](docs/data-flow.md)
- [docs/fit-fields-and-formulas.md](docs/fit-fields-and-formulas.md)
- [docs/version-changes-2026-08-14.md](docs/version-changes-2026-08-14.md)

## Safety Note

This app is for research and telemetry analysis. It is not a certified dive computer and must not be used as a sole life-support or decompression-planning instrument.