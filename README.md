# DRFusionTrack

DRFusionTrack is the Garmin Connect IQ watch app for underwater navigation, motion tracking, dead reckoning, and FIT logging. It combines pressure-derived depth, motion and heading estimation, GPS correction, and a lightweight local Kalman-style DR model to create a practical tracking solution for wrist-worn marine use.

## Overview

DRFusionTrack is built for Garmin Instinct-class devices and is designed to run as a custom watch app rather than as a native Garmin dive-computer mode. The project is focused on three things:

- live underwater state detection,
- local dead-reckoning position estimation when GPS is weak or unavailable,
- export of a rich FIT stream for post-session analysis.

The current implementation is tuned for real-world constraints: noisy GPS over water, shallow depth transitions, wrist-mounted motion, and the need to keep the app responsive while still logging usable telemetry.

## Current implementation status

The current codebase is the authoritative state of the project and includes the following improvements:

- pressure-first depth estimation with surface baseline from the first valid reading,
- shallow depth values preserved instead of being discarded at startup,
- underwater mode detection using hysteresis and shallow-water thresholds,
- motion confidence and heading selection based on the strongest valid sensor source,
- local East/North dead reckoning with GPS correction when the fix is usable,
- custom FIT field export for DR position, depth, speed, GPS state, and motion status,
- successful build validation against the Garmin Connect IQ SDK in this environment.

## Core features

### Depth and dive-state tracking
- ambient-pressure depth estimation as the primary source,
- altitude used only as a secondary validation signal,
- live surface reference established from the first valid pressure sample,
- noise rejection and shallow-value preservation,
- underwater/surface transitions with hysteresis and minimum time gating.

### Navigation and motion estimation
- accelerometer, gyroscope, and magnetometer support,
- adaptive motion confidence estimation,
- best-source heading selection: true heading, mag heading, or gyro fallback,
- GPS quality gating and local DR continuity during weak fixes.

### Sensor fusion and dead reckoning
- local East/North state propagation,
- conservative noise tuning for multipath-prone water conditions,
- GPS correction only when fixes are fresh and usable,
- synthetic local track generation for post-session reconstruction.

### FIT logging and analysis
- custom FIT fields for DR east/north, depth, heading, motion, GPS quality, and underwater state,
- synthetic DR latitude/longitude output for review,
- output suitable for later analysis in Python or external FIT tooling.

## Main runtime flow

1. startup initializes the app and sensor listeners,
2. the timer loop reads GPS, motion, and pressure data,
3. the app updates the depth estimate and dive state,
4. heading and speed are resolved from the strongest available source,
5. the local DR model predicts and corrects the track,
6. FIT values are written for the active session,
7. shutdown handles cleanup and final state save.

## Project files

- [source/gsensrosApp.mc](source/gsensrosApp.mc)
- [source/gsensrosView.mc](source/gsensrosView.mc)
- [source/DeadReckoning.mc](source/DeadReckoning.mc)
- [source/KalmanDR.mc](source/KalmanDR.mc)
- [source/NitrogenModel.mc](source/NitrogenModel.mc)
- [manifest.xml](manifest.xml)
- [resources/strings/strings.xml](resources/strings/strings.xml)
- [resources/drawables/drawables.xml](resources/drawables/drawables.xml)
- [docs/](docs/)

## Verification

The app was validated through the local Garmin SDK build process.

```bash
cd /home/panagiotis/Documents/gsensors/gsensros
./run_simulation.sh --build-only
```

This confirms the project compiles successfully with the current toolchain and that the DRFusionTrack branding and app entry are consistent with the active source.

## Notes

This project is a custom underwater navigation and dive-tracking app, not a certified commercial dive computer. It is intended for research, logging, and post-session analysis rather than as a medical or decompression system.

---

The final application behavior is intentionally conservative: the app favors stable live depth estimation, careful state transitions, and robust dead-reckoning continuity over aggressive corrections that would produce noisy or unstable tracks under imperfect GPS or sensor conditions.