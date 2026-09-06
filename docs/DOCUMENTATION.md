# DRFusionTrack Documentation Index

## Current Baseline

This documentation set matches the latest runtime updates in [../source/gsensrosView.mc](../source/gsensrosView.mc), including:

- depth source tagging (`P`, `D`, `ALT`, `GPS_ALT`, `SIM`, `NONE`)
- motion threshold refactor with Kalman-based fallback
- simulator synthetic depth path for no-pressure/flat-altitude scenarios
- expanded runtime diagnostics (`DRDIAG`, `DEPTHDBG`)
- delegate/menu structure updates

## Core Documents

| Section | Description |
|---------|-------------|
| [overview.md](overview.md) | Current feature set and operating model |
| [architecture.md](architecture.md) | Component boundaries and runtime architecture |
| [data-flow.md](data-flow.md) | Loop-level processing and source resolution |
| [fit-fields-and-formulas.md](fit-fields-and-formulas.md) | FIT fields, formulas, and write behavior |
| [version-changes-2026-08-14.md](version-changes-2026-08-14.md) | Consolidated change history including latest commits |
| [command-reference.md](command-reference.md) | Verified build/run commands for current SDK |
| [../README.md](../README.md) | Project-level quick start and summary |

## Source Files Covered

| File | Role |
|------|------|
| [../source/gsensrosApp.mc](../source/gsensrosApp.mc) | app lifecycle entry |
| [../source/gsensrosView.mc](../source/gsensrosView.mc) | main runtime loop and telemetry |
| [../source/gsensrosDelegate.mc](../source/gsensrosDelegate.mc) | key/select/menu behavior |
| [../source/gsensrosMenuDelegate.mc](../source/gsensrosMenuDelegate.mc) | menu action delegate |
| [../source/DeadReckoning.mc](../source/DeadReckoning.mc) | DR propagation |
| [../source/KalmanDR.mc](../source/KalmanDR.mc) | local filtering and correction |
| [../source/NitrogenModel.mc](../source/NitrogenModel.mc) | N2 and risk telemetry |

## Notes

Simulation and real-device behavior are now explicitly separated in docs:

- real hardware should use pressure/direct-depth sources
- simulator may require `SIM` depth source when pressure is unavailable and altitude is constant