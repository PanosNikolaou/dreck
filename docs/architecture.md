# gsensros Architecture

## Layer Design

The application follows a layered architecture with four distinct layers:

### 1. Lifecycle Layer

Manages application startup, shutdown, and view transitions.

- **gsensrosApp**: Application entry point extending `Application.AppBase`. Implements `onStart()`, `onStop()`, and `getInitialView()`.
- **gsensrosView**: View lifecycle methods `initialize()`, `onLayout()`, `onShow()`, `onHide()`, `onUpdate()`, `prepareToExit()`.

### 2. Sensor & Input Layer

Collects raw sensor data and user input events.

- **Sensor**: Accelerometer, gyroscope, magnetometer, heart rate, altitude via `Sensor.registerSensorDataListener()`
- **Position**: GPS location via `Position.enableLocationEvents()`
- **Input**: Button presses (`onSelect`, `onBack`) and page scrolling handled by delegates
- **Timer**: 500ms periodic callback (`timerCallback`) drives the main processing loop

### 3. Estimation Layer

Processes raw sensor data into meaningful state estimates.

- **Motion Detection**: Adaptive baseline learning, high-pass filtering, exponential variance, unified hysteresis
- **Depth Estimation**: Altitude-relative depth with surface calibration, strict validity gating for bad barometric data, and continuous recalibration
- **Dive State Detection**: Start at 0.5 m depth and stop only when shallow (≤ 0.5 m) and within 5 m of the recording start GPS point
- **Heading Estimation**: Three-tier source selection (true heading → magnetometer → gyro integration → DR fallback)
- **Speed Estimation**: GPS speed preferred; motion-based fallback when GPS unavailable
- **Dead Reckoning**: 2D position integration using speed × heading with heading correction
- **Kalman Filter**: 4-state (east, north, velEast, velNorth) Kalman filter with GPS corrections
- **Nitrogen Model**: Haldane-style multi-tissue on-gassing/off-gassing model

### 4. Recording Layer

Manages activity recording and FIT file creation.

- **ActivityRecording**: Garmin API for creating and managing activity sessions
- **FitContributor**: Custom FIT fields for DR position, depth, motion, speed, heading, etc.
- **Session Management**: Start, stop, save with proper resource cleanup

## Class Relationships

```
gsensrosApp
  └── creates gsensrosView + gsensrosDelegate
        ├── gsensrosView
        │     ├── DeadReckoning (dr)
        │     ├── KalmanDR (kalman)
        │     ├── NitrogenModel (n2Model)
        │     ├── Timer (updateTimer)
        │     └── Sensor/Position listeners
        ├── gsensrosDelegate
        │     └── delegates to gsensrosView
        └── ConfirmStopDelegate
              └── delegates to gsensrosView (stop/prepareToExit)
```

## Data Flow Summary

1. Sensors and GPS feed raw data into `gsensrosView`
2. `timerCallback` (500ms) orchestrates the processing pipeline:
   - `readSensors()` → raw sensor values
   - `updateDepth()` → depth estimate
   - `updateGPS()` → position and speed
   - `processDiveState()` → underwater flag
   - `updateMotionConfidence()` → moving state
   - Kalman/DR position updates
   - `writeFitFieldsIfNeeded()` → FIT recording
3. `onUpdate()` renders current state to the display