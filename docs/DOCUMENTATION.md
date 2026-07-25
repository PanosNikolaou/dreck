# gsensros Documentation Index

gsensros is a Garmin Connect IQ watch application for motion detection, GPS tracking, heading estimation, depth estimation, dead reckoning, Kalman-style position updates, nitrogen loading modeling, and FIT activity recording.

## Table of Contents

| Section | Description |
|---------|-------------|
| [Overview](overview.md) | Project summary, goals, and key features |
| [Architecture](architecture.md) | System architecture, layer design, and class relationships |
| [Data Flow](data-flow.md) | Runtime data flow from sensor input to FIT recording |
| [Source Files](source/) | Per-file documentation for all source files |
| [Resource Files](resources/) | Per-file documentation for all resource/config files |

## Source Files

| File | Description |
|------|-------------|
| [gsensrosApp.mc](../source/gsensrosApp.mc) | Application entry point and lifecycle hooks |
| [gsensrosView.mc](../source/gsensrosView.mc) | Main view: UI rendering, sensor processing, DR/Kalman/recording logic |
| [gsensrosDelegate.mc](../source/gsensrosDelegate.mc) | Input delegate for button presses and scrolling |
| [gsensrosMenuDelegate.mc](../source/gsensrosMenuDelegate.mc) | Menu input delegate (placeholder) |
| [ConfirmStopDelegate.mc](../ConfirmStopDelegate.mc) | Confirmation dialog delegate for stop recording |
| [DeadReckoning.mc](../source/DeadReckoning.mc) | 2D dead reckoning engine with heading correction |
| [KalmanDR.mc](../source/KalmanDR.mc) | 4-state Kalman filter for GPS-corrected position |
| [NitrogenModel.mc](../source/NitrogenModel.mc) | Simplified Haldane-style nitrogen loading model |

## Resource Files

| File | Description |
|------|-------------|
| [manifest.xml](../manifest.xml) | Connect IQ app manifest (permissions, products, icons) |
| [monkey.jungle](../monkey.jungle) | Build configuration linking manifest |
| [layout.xml](../resources/layouts/layout.xml) | UI layout definition (minimal, UI drawn programmatically) |
| [strings.xml](../resources/strings/strings.xml) | String resources and FIT field contributions |
| [menu.xml](../resources/menus/menu.xml) | Menu definition for the app |
| [drawables.xml](../resources/drawables/drawables.xml) | Drawable asset declarations |

## Additional Documents

| File | Description |
|------|-------------|
| [README.md](../README.md) | Project README |
| [developerguide.md](../developerguide.md) | Developer guide |
| [garmin_dive_app_documentation.md](../garmin_dive_app_documentation.md) | Garmin dive app documentation |
| [NitrogenModel.md](../NitrogenModel.md) | Nitrogen model explanation |
| [Dead_Reckoning_Kalman_Garmin_Report.md](../Dead_Reckoning_Kalman_Garmin_Report.md) | DR/Kalman technical report |
| [Instinct® 2X Solar.md](../Instinct® 2X Solar.md) | Device-specific notes |