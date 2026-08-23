# DRFusionTrack Documentation Index

DRFusionTrack is a Garmin Connect IQ application for wearable underwater navigation, motion estimation, and FIT export. It combines GPS, inertial sensing, pressure-based depth estimation, and custom activity recording into a single watch app.

## Current status

The app is now branded and documented as DRFusionTrack. The design is centered on pressure-based depth, local dead reckoning, and conservative GPS correction when the fix is usable. This is the current implementation state of the project.

## Table of contents

| Section | Description |
|---------|-------------|
| [Overview](overview.md) | Project summary, goals, and key features |
| [Architecture](architecture.md) | System architecture and runtime data flow |
| [Data Flow](data-flow.md) | Processing loop, state transitions, and signal flow |
| [Fit Fields and Formulas](fit-fields-and-formulas.md) | FIT field definitions and formulas |
| [README.md](../README.md) | Project overview and build notes |
| [Source Files](source/) | Per-file source documentation |
| [Resource Files](resources/) | Resource and configuration documentation |

## Main source files

| File | Description |
|------|-------------|
| [gsensrosApp.mc](../source/gsensrosApp.mc) | Application entry point and lifecycle hooks |
| [gsensrosView.mc](../source/gsensrosView.mc) | Core runtime: sensors, depth, DR, and FIT recording |
| [DeadReckoning.mc](../source/DeadReckoning.mc) | Dead-reckoning engine |
| [KalmanDR.mc](../source/KalmanDR.mc) | Local filtered DR estimator and GPS correction |
| [NitrogenModel.mc](../source/NitrogenModel.mc) | Risk and UI loading model |

## Featured capabilities

- pressure-first depth estimation,
- shallow-water dive-state detection,
- motion confidence and heading estimation,
- East/North local navigation with sparse GPS correction,
- underwater state logging and route reconstruction,
- custom FIT output for telemetry analysis.

## Additional references

| File | Description |
|------|-------------|
| [README.md](../README.md) | Project README |
| [garmin_dive_app_documentation.md](../garmin_dive_app_documentation.md) | Operational documentation |
| [Dead_Reckoning_Kalman_Garmin_Report.md](../Dead_Reckoning_Kalman_Garmin_Report.md) | Technical report on dead reckoning and filtering |
| [version-changes-2026-08-14.md](version-changes-2026-08-14.md) | Release note history |

## Summary of the implementation

The current app is intentionally conservative: it keeps the live surface baseline, preserves valid shallow readings, and uses only quality-gated GPS corrections. This keeps the track stable and the underwater classification reliable rather than forcing aggressive state changes during small pressure spikes or weak GPS periods.