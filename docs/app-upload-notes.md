# Connect IQ Beta App Upload Notes

## Project identity

- App name: DRFusionTrack
- Manifest App ID: 61261946-ed35-4393-ba9e-faa0acae21f5
- Entry class: drFusionTrackApp
- Build target: Instinct® 2X
- App type: Device App
- Min API level: 3.4.0
- Current version: 24826BETA1A
- Status: Verified
- Signature: Verified

## Current app description

DRFusionTrack is a Garmin Connect IQ watch app for underwater navigation, motion tracking, dead reckoning, and FIT logging. It combines pressure-derived depth, motion and heading estimation, GPS quality gating, and a local dead-reckoning model to create a practical tracking solution for wrist-worn marine use.

## Suggested store listing content

### Title

DRFusionTrack

### Description

DRFusionTrack is a custom Garmin Connect IQ app for underwater navigation, motion tracking, and post-session analysis. It blends pressure-based depth estimation, local dead reckoning, GPS quality checks, and FIT export to provide a practical tracking experience for marine and underwater activity use on Instinct® 2X devices.

The app focuses on three core goals:

- live underwater state detection,
- local dead-reckoning position tracking during weak or missing GPS,
- export of a detailed FIT stream for later analysis.

It is designed for real-world wearable constraints: noisy GPS over water, shallow transitions, wrist-mounted motion, and the need to keep tracking stable without excessive false corrections.

### What’s New

This beta build includes the current DRFusionTrack implementation with pressure-first depth estimation, improved shallow-water handling, conservative GPS correction, and custom FIT field output for navigation, depth, motion, and session metrics.

## Category recommendation

- Category: Health & Fitness
- Subcategory: Marine

This matches the app’s underwater tracking, dive-state monitoring, and marine navigation purpose.

## Privacy and compliance

- Does the app collect user data? No
- Does the app decode or encode ANT+ profiles? No

## Technical project status

The current implementation is the authoritative state of the project and includes:

- pressure-first depth estimation with a calibrated surface reference,
- shallow-value preservation instead of discarding early startup readings,
- underwater/surface hysteresis with minimum dwell time,
- motion confidence and heading estimation from the strongest valid sensor source,
- local East/North dead reckoning with GPS correction when fixes are fresh and usable,
- custom FIT export for DR position, depth, heading, motion, GPS state, and session metrics,
- successful local build validation using the Garmin Connect IQ SDK.

## Device and runtime info

| Property | Value |
|----------|-------|
| Target Product | instinct2x |
| App Type | watch-app |
| Entry Class | drFusionTrackApp |
| Manifest File | manifest.xml |
| Main View | gsensrosView |
| Build Output | build/gsensros.prg |
| FIT Contributions | build/gsensros-fit_contributions.json |

## Required permissions

| Permission | Purpose |
|------------|---------|
| Sensor | Motion and environmental sensing |
| Positioning | GPS fix access |
| Fit | Activity recording and FIT serialization |
| FitContributor | Custom FIT field creation |
| Communications | Device communication |
| BluetoothLowEnergy | BLE communication |
| Notifications | Alerts and UI feedback |
| PushNotification | Notification support |
| UserProfile | User profile access |
| PersistedContent | Storage access |
| PersistedLocations | Location persistence |
| ComplicationPublisher | Complication support |
| Ant | ANT+ support (not active in this app) |

## Upload checklist

1. Enter the title: DRFusionTrack.
2. Use the description above as the English app description.
3. Add the “What’s New” notes for the beta version.
4. Upload a 1440x720 hero image under 2048 KB.
5. Select Health & Fitness → Marine (recommended).
6. Confirm that the app does not collect user data.
7. Confirm that the app does not use ANT+ profiles.
8. Submit the beta app for the Instinct® 2X target device.

## Notes

This beta submission reflects the current state of the project as documented in the project README, docs overview, and implementation documentation. The app is intended for underwater navigation and dive-tracking workflows on Garmin Instinct® 2X hardware and is specifically positioned as a custom tracking and analysis tool rather than a certified medical or commercial dive-computer product.
