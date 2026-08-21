# gsensros Documentation Index

gsensros is a Garmin Connect IQ application for wearable dive tracking, motion estimation, and FIT export. It combines GPS, inertial input, pressure-based depth estimation, and custom activity recording into a single watch app.

## Current status

The depth pipeline has been corrected to use pressure as the primary source and to initialize the surface baseline from the first valid pressure sample. This resolves the earlier flat-zero depth behavior and aligns the app more closely with the Suunto Ocean reference trace.

## Table of Contents

| Section | Description |
|---------|-------------|
| [Overview](overview.md) | Project summary, goals, and key features |
| [Architecture](architecture.md) | System architecture and runtime data flow |
| [Data Flow](data-flow.md) | Processing loop, state transitions, and signal flow |
| [Fit Fields and Formulas](fit-fields-and-formulas.md) | Detailed formulas and FIT field explanations |
| [README.md](../README.md) | Project overview and current algorithm notes |
| [Source Files](source/) | Per-file documentation for the app source |
| [Resource Files](resources/) | Resource and configuration documentation |

## Main source files

| File | Description |
|------|-------------|
| [gsensrosApp.mc](../source/gsensrosApp.mc) | Application entry point and lifecycle hooks |
| [gsensrosView.mc](../source/gsensrosView.mc) | Core runtime: sensors, depth, DR, fit recording |
| [gsensrosDelegate.mc](../source/gsensrosDelegate.mc) | Input delegate for interactions |
| [gsensrosMenuDelegate.mc](../source/gsensrosMenuDelegate.mc) | Menu handling |
| [ConfirmStopDelegate.mc](../ConfirmStopDelegate.mc) | Stop confirmation workflow |
| [DeadReckoning.mc](../source/DeadReckoning.mc) | Dead-reckoning engine |
| [KalmanDR.mc](../source/KalmanDR.mc) | Kalman filter for GPS-corrected navigation |
| [NitrogenModel.mc](../source/NitrogenModel.mc) | Nitrogen loading model |

## Additional references

| File | Description |
|------|-------------|
| [README.md](../README.md) | Project README |
| [garmin_dive_app_documentation.md](../garmin_dive_app_documentation.md) | Garmin dive-app architecture notes |
| [NitrogenModel.md](../NitrogenModel.md) | Nitrogen model explanation |
| [Dead_Reckoning_Kalman_Garmin_Report.md](../Dead_Reckoning_Kalman_Garmin_Report.md) | Technical report on DR and filtering |
| [Instinct® 2X Solar.md](../Instinct®%202X%20Solar.md) | Device-specific notes |
| [version-changes-2026-08-14.md](version-changes-2026-08-14.md) | Prior release notes |

## Summary of the corrected depth fix

The primary improvement is that the app no longer waits for a long startup calibration window before trusting pressure-based depth. The first valid ambient pressure sample becomes the baseline, and the depth estimate is allowed to begin live immediately. This was the missing factor behind the disconnect between the Garmin export and the Suunto Ocean dive log.