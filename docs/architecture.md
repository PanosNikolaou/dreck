# DRFusionTrack Architecture

## Layer design

The app follows a layered design that separates sensor input, estimation, and recording while keeping them connected through a central runtime controller.

### 1. Lifecycle layer

Handles app startup, view creation, shutdown, and session cleanup.

- `drFusionTrackApp`: application entry point
- `gsensrosView`: core runtime state machine and sensor polling
- `gsensrosDelegate`: button/input handling
- `ConfirmStopDelegate`: stop confirmation flow

### 2. Sensor and input layer

Collects raw data from the watch hardware and the environment.

- accelerometer, gyroscope, and magnetometer readings,
- ambient pressure and altitude data,
- GPS position and quality data,
- timer-driven sampling for the main state loop.

### 3. Estimation layer

Transforms raw measurements into valid state estimates.

- `updateDepth()`: pressure-based depth with live baseline calibration,
- `processDiveState()`: underwater vs surface classification with hysteresis,
- `getBestHeading()`: strongest valid heading source selection,
- `getEstimatedSpeedMps()`: motion and GPS speed fusion,
- `updateMotionConfidence()`: movement confidence and stability gating,
- `DeadReckoning` and `KalmanDR`: local navigation and GPS-corrected track generation,
- `NitrogenModel`: UI-oriented risk model for monitoring and logging.

### 4. Recording layer

Stores the final state into the FIT stream for analysis.

- custom FIT fields for DR east/north, depth, speed, heading, GPS fix, and underwater state,
- throttled writes for efficiency and data integrity,
- session summaries and live UI telemetry.

## Core architecture

```text
drFusionTrackApp
  └── creates gsensrosView and delegates
        ├── gsensrosView
        │     ├── DeadReckoning
        │     ├── KalmanDR
        │     ├── NitrogenModel
        │     ├── Sensor + Position listeners
        │     └── Timer callback
        ├── gsensrosDelegate
        └── ConfirmStopDelegate
```

## Depth architecture

The depth model is designed around pressure as the primary signal:

- first valid pressure sample becomes the active surface reference,
- pressure is the main depth source,
- altitude is secondary and used only as validation,
- negative or impossible jumps are clipped,
- low-pass smoothing keeps the signal stable without removing real motion.

This is the core fix that makes the app behave like a practical underwater tracker rather than a noisy startup artifact.

## Runtime flow

1. startup begins sensor listeners and timer scheduling,
2. the 500 ms loop reads the latest sensor and GPS inputs,
3. `updateDepth()` produces a live depth estimate,
4. `processDiveState()` decides whether the user is underwater,
5. motion confidence and heading are recalculated,
6. DR and Kalman filters advance the local track,
7. FIT writes occur when enough state change is present,
8. shutdown ends listeners and preserves the session cleanly.

## Constraints

Garmin Connect IQ is not a native dive-computer API. DRFusionTrack therefore behaves as a custom wearable tracker: it estimates depth and underwater motion using a conservative heuristic model, then uses a local DR estimator and sparse GPS corrections to build a useful post-session route.