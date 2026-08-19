# dreck

Garmin Connect IQ `WatchUi.View` application for motion detection, GPS tracking, heading estimation, depth estimation, dead reckoning, Kalman-style position updates, and FIT recording.

## Overview

`dreck` is a view-based tracking app built for Garmin devices. It combines sensor callbacks, GPS updates, a periodic timer loop, and activity recording to maintain a live internal estimate of the user's movement and position.

The code is designed to:

- detect motion more reliably than a single threshold,
- determine whether the user is underwater or on land,
- estimate heading when GPS is unavailable,
- advance dead reckoning only when movement is believable,
- record the resulting data into a FIT session,
- show the current state on screen for debugging and monitoring.

## Architecture

The app is organized around four main layers.

### 1. Lifecycle layer
The Garmin `WatchUi.View` lifecycle methods manage startup, shutdown, and rendering:

- `initialize()`
- `onLayout()`
- `onShow()`
- `onHide()`
- `onUpdate()`
- `prepareToExit()`

These methods initialize the tracking helpers, start and stop sensors, and draw the live UI.

### 2. Sensor and GPS layer
Sensor input is collected from:

- accelerometer,
- gyroscope,
- magnetometer,
- true heading,
- altitude,
- GPS speed and position.

The main input functions are:

- `startMotionListener()`
- `stopMotionListener()`
- `sensorDataCallback()`
- `readSensors()`
- `startGps()`
- `stopGps()`
- `onPosition()`

### 3. Estimation layer
This layer determines the current state of the user:

- `updateDepth()` estimates depth from altitude.
- `processDiveState()` decides whether the user is underwater.
- `getBestHeading()` selects the best heading source.
- `isStationary()` and `isProbablyMoving()` classify movement.
- `updateMotionConfidence()` smooths the motion decision.
- `getEstimatedSpeedMps()` estimates speed when GPS is weak or missing.

### 4. Recording layer
Activity recording is handled through Garmin's `ActivityRecording` API. The app creates custom FIT fields for:

- DR East/North,
- depth,
- motion,
- speed estimate,
- underwater state,
- GPS fix state,
- heading,
- moving state.

## Runtime flow

1. `onShow()` resets the state, starts calibration, starts the sensor listener, and launches the timer.
2. `timerCallback()` runs every 500 ms and processes the current sensor/GPS state.
3. If recording is active, the app updates Kalman prediction or GPS correction and advances dead reckoning when appropriate.
4. `writeFitFieldsIfNeeded()` stores the current state into the FIT session.
5. `onUpdate()` redraws the UI.
6. `onHide()` and `prepareToExit()` shut down resources cleanly.

## Detailed function reference

### Lifecycle

#### `initialize()`
Creates the dead reckoning and Kalman helper objects. If object creation fails, the error is logged.

#### `onLayout(dc)`
Loads the UI layout resource.

#### `onShow()`
Runs when the view becomes visible. It resets motion and depth state, starts motion sensing, starts calibration, initializes timing, and starts the repeating update timer.

#### `onHide()`
Runs when the view is hidden. It stops the timer, sensor listener, and GPS.

#### `prepareToExit()`
Performs final cleanup before the app exits.

### Calibration

#### `startStartupCalibration()`
Begins a short startup calibration period for gyro and magnetometer bias estimation.

#### `finishStartupCalibration()`
Calculates the average bias values collected during calibration and disables calibration mode.

### Main processing loop

#### `timerCallback()`
This is the core control loop. It:

- computes `dt`,
- reads sensor and GPS state,
- updates depth and dive state,
- updates motion confidence,
- ends calibration when time expires,
- updates Kalman/DR estimates,
- writes FIT fields,
- requests a UI redraw.

This is the most important function in the app.

### GPS handling

#### `startGps()`
Enables continuous GPS location updates.

#### `stopGps()`
Disables GPS location updates.

#### `getPositionQuality(info)`
Returns the GPS accuracy value from a `Position.Info` object.

#### `onPosition(info)`
Receives GPS updates and stores the current latitude, longitude, and quality if the fix is usable.

### Motion detection

#### `startMotionListener()`
Registers a sensor listener for accelerometer power data.

#### `stopMotionListener()`
Unregisters the sensor listener.

#### `sensorDataCallback(sensorData)`
Processes accelerometer power samples and updates the motion score.

The logic is:
- compute average accelerometer power,
- compare it to a learned baseline,
- smooth the result,
- combine it with gyro magnitude,
- use hysteresis to avoid unstable toggling.

This is the app's main motion detection engine.

#### `isStationary()`
Returns `true` only when the user is very likely still. It checks:

- GPS speed,
- motion score,
- gyro magnitude.

This is used as a strict gate before advancing dead reckoning.

#### `isProbablyMoving()`
Returns a looser motion decision used for confidence tracking.

#### `updateMotionConfidence()`
Increases or decreases the confidence score depending on whether movement appears likely.

#### `resetMotionState()`
Clears all motion-related runtime values.

### Heading and sensor state

#### `resetHeadingEstimate()`
Resets the current heading estimate.

#### `absf(v)`
Returns the absolute value of a float.

#### `isGpsQualityUsable(q)`
Checks whether GPS quality is good enough to trust.

#### `readSensors(info)`
Reads raw accelerometer, gyro, heading, and magnetometer values from the current sensor info.

It also applies calibration bias correction and updates:

- `accelX`, `accelY`, `accelZ`
- `gyroX`, `gyroY`, `gyroZ`
- `trueHeading`
- `magHeading`

#### `getBestHeading(dt)`
Chooses the best available heading source in this order:

1. true heading,
2. magnetometer heading,
3. gyro integration,
4. dead reckoning fallback.

#### `normalizeAngleRad(a)`
Normalizes an angle into the `0..2π` range.

#### `radToDeg(a)`
Converts radians to degrees.

### Depth and dive state

#### `updateDepth(info)`
Estimates depth from altitude relative to a calibrated surface reference.

#### `processDiveState()`
Determines whether the user is underwater using the live depth threshold and the recorded GPS entry point. The app marks the dive as started once depth exceeds 0.5 m. It ends only when the depth is at or below 0.5 m and the current GPS position is within 5 m of the original recording start location, which prevents false stop events while the user is still near the surface in a different place.

### Speed and motion estimation

#### `getEstimatedSpeedMps()`
Returns the best available speed estimate. It prefers GPS speed when usable, otherwise falls back to motion-based estimates.

#### `shouldAdvanceDR(bestHeading, estSpeed)`
Checks whether dead reckoning should advance. It requires:

- a valid heading,
- enough speed,
- sufficient motion confidence,
- not being stationary.

### Session management

#### `onSelect()`
Starts or stops the recording session.

#### `onBack()`
Stops recording if needed, then stops timers, GPS, and motion sensing.

#### `startSession()`
Starts a new tracking session, initializes GPS and entry position, resets tracking state, and configures the Kalman/DR systems.

#### `stopSession()`
Stops the current session, captures the exit position, saves the FIT file, and clears state.

#### `captureEntryPosition()`
Stores the GPS position at the start of recording.

#### `captureExitPosition()`
Stores the GPS position at the end of recording.

#### `startRecording()`
Creates the Garmin activity session and defines the custom FIT fields.

#### `shutdownSessionSafe()`
Stops the recording session and saves it safely.

#### `shutdownSessionWithoutSave()`
Stops the session without saving it.

#### `stopTimerOnly()`
Stops the repeating timer.

#### `forceCleanup()`
Clears session and recording state references.

### FIT helpers

#### `clearLastFitValues()`
Clears cached values used to avoid duplicate FIT writes.

#### `clearFitFields()`
Clears all FIT field references and cached values.

#### `resetDepthCalibration()`
Resets altitude and depth calibration state.

#### `isFiniteValue(v)`
Returns `true` only if the value is a valid finite number.

#### `writeFloatField(field, value, lastValue, eps)`
Writes a float field only if the value changed enough from the previous one.

#### `writeUIntField(field, value, lastValue)`
Writes an integer field only if the value changed.

#### `writeFitFieldsIfNeeded(estSpeed, bestHeading)`
Writes the current state into the FIT session:

- east/north position,
- depth,
- motion,
- estimated speed,
- underwater flag,
- GPS fix flag,
- heading,
- moving flag,
- GPS coordinates.

#### `floatEquals(a, b, eps)`
Compares two float values using a tolerance.

#### `errorToString(e)`
Converts an exception to a readable log string.

### UI

#### `onUpdate(dc)`
Renders the current state on the display.

The UI shows:
- recording status,
- mode,
- GPS availability,
- GPS quality,
- moving status,
- depth,
- motion score,
- calibration countdown,
- Kalman/DR values,
- current speed.

## Motion detection design

The motion detection system uses multiple stages:

1. **Baseline learning**  
   The app learns a resting accelerometer power baseline.

2. **Delta calculation**  
   It measures how far the current signal is from that baseline.

3. **Gyro reinforcement**  
   Rotational motion is included through gyro magnitude.

4. **Smoothing**  
   The signal is filtered so it is less sensitive to short spikes.

5. **Hysteresis**  
   Separate thresholds prevent noisy on/off switching.

6. **Confidence tracking**  
   Motion must persist before the app trusts it.

This is a practical design for wearable tracking because it handles noise and brief sensor spikes much better than a single threshold.

## FIT fields

The following custom FIT fields are created:

- `DR_East_m`
- `DR_North_m`
- `Depth_m`
- `GPS_Lat`
- `GPS_Lon`
- `Motion_mg`
- `Speed_Est`
- `Underwater`
- `GPS_Fix`
- `Heading_deg`
- `Moving`

These fields make it possible to analyze motion, tracking, and sensor behavior after the session ends.

## Data model

The app maintains three important internal states:

### Motion state
Represents whether the user is likely moving and how strong that confidence is.

### Tracking state
Represents current heading, depth, GPS quality, underwater state, and dead reckoning position.

### Recording state
Represents whether a FIT session is active and what data fields are available.

## Notes on performance

The app is designed to reduce unnecessary processing by:

- writing FIT fields only when values change enough,
- using motion confidence instead of raw motion spikes,
- smoothing sensor signals,
- keeping expensive processing in a timer loop rather than inside the UI render path.

## Known limitations

- Accelerometer power is still noisy and device-dependent.
- Heading can drift if true heading is unavailable.
- Altitude-based depth is approximate.
- Motion thresholds may need tuning per device.
- Dead reckoning quality depends heavily on correct motion detection.

## Suggested improvements

If you want to refine the app further, the best next steps are:

1. Split the motion logic into its own helper class.
2. Make thresholds configurable.
3. Add debug logs for raw motion and calibration data.
4. Separate timer processing into smaller functions.
5. Add device-specific tuning for motion and depth behavior.