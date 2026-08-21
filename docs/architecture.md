# gsensros Architecture

## Layer design

The app follows a layered design that keeps sensor input, estimation, and recording separated but connected through the central `gsensrosView` controller.

### 1. Lifecycle layer

Manages startup, shutdown, and view transitions.

- `gsensrosApp`: application entry point
- `gsensrosView`: lifecycle methods and the core runtime state machine
- `gsensrosDelegate`: input handling and user interaction
- `ConfirmStopDelegate`: stop confirmation flow

### 2. Sensor and input layer

Collects raw data from the watch hardware and the environment.

- `Sensor.getInfo()` for accelerometer, gyroscope, heading, and pressure-related values
- `Position.getInfo()` for GPS quality and location data
- timer sampling at 500 ms for the main processing loop
- button and navigation delegate events

### 3. Estimation layer

Transforms raw measurements into useful state estimates.

- `updateDepth()`: pressure-derived depth estimate with altitude fallback
- `processDiveState()`: underwater vs surface classification with hysteresis
- `getBestHeading()`: heading priority selection
- `getEstimatedSpeedMps()`: motion/GPS speed fusion
- `updateMotionConfidence()`: stage-based movement confidence assessment
- `DeadReckoning` and `KalmanDR`: drift-resistant navigation updates
- `NitrogenModel`: simplified nitrogen loading model

### 4. Recording layer

Writes the final state into the FIT file for post-session analysis.

- custom field creation for DR east/north, depth, speed, heading, GPS fix, and underwater state
- `writeFitFieldsIfNeeded()` throttles updates to avoid too-frequent FIT writes
- summary fields for max depth and dive timing

## Class relationships

```text
gsensrosApp
  └── creates gsensrosView and delegate
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

The most significant fixed component is the depth model:

- a valid pressure sample becomes the active surface reference immediately,
- pressure is used as the primary depth source,
- altitude is secondary and only blended when it is valid,
- negative values and impossible jumps are rejected,
- a low-pass stage keeps the track smooth without losing the real dive profile.

This differs materially from the earlier altitude-first design and is the reason the current app matches the Suunto reference much more closely.

## Runtime flow

1. `onShow()` resets state and starts calibration.
2. `timerCallback()` computes `dt` and reads sensor state.
3. `updateDepth()` uses pressure and altitude to estimate the current depth.
4. `processDiveState()` decides whether the user is underwater.
5. `updateMotionConfidence()` updates movement confidence.
6. DR/Kalman state is advanced using the strongest available signals.
7. `writeFitFieldsIfNeeded()` stores the final estimate in FIT.
8. `onHide()` and `prepareToExit()` cleanly stop the session and resources.

## Important constraints

Garmin Connect IQ is not a native dive platform. The app behaves as a custom underwater tracker on top of a surface activity model, so the implementation must treat depth and underwater state as heuristic estimates rather than a Garmin native dive API.