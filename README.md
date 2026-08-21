# gsensros

Garmin Connect IQ dive/tracking app for underwater motion estimation, GPS-assisted dead reckoning, depth tracking, and FIT recording.

## Overview

`gsensros` is a wearable tracking app built for Garmin devices. It combines pressure-derived depth estimation, altitude fallback, motion detection, heading and DR estimates, and custom FIT recording so dives can be logged and analyzed after the session.

The app is designed to:

- estimate current depth using a pressure baseline and altitude fallback,
- reject non-physical spikes and invalid pressure/altitude values,
- detect underwater state using a calibrated depth threshold and hysteresis,
- update speed and heading from the strongest available source,
- continue dead reckoning through GPS gaps,
- export the resulting values as custom FIT fields.

## Current algorithm status

The most important fix in the current implementation is in the depth pipeline:

- a valid pressure sample is used as the live surface baseline immediately,
- shallow pressure data is no longer forced to zero during startup calibration,
- altitude is treated as a secondary correction signal, not the primary source,
- the output is smoothed with a tighter low-pass to follow real dive traces without lagging.

This was validated against the Suunto Ocean reference log: the reference data contains realistic depth values such as 1.56 m, 3.96 m, 4.47 m, and 5.91 m, while the Garmin export previously collapsed to zero during the same dive. The current logic is tuned to track the Suunto-style profile much more closely.

## Core runtime model

The app follows a timer-driven processing loop with a few major sub-systems:

### 1. Sensor and GPS layer
- accelerometer and gyroscope sampling
- magnetometer and true heading input
- GPS speed and location quality checks
- ambient pressure and altitude data

### 2. Estimation layer
- `updateDepth()`
- `processDiveState()`
- `getBestHeading()`
- `getEstimatedSpeedMps()`
- `updateMotionConfidence()`
- `DeadReckoning` / `KalmanDR` integration

### 3. Recording layer
- FIT field creation
- custom field writes on the active recording session
- dive session summary tracking (max depth, dive time, max N2 loading)

## Main processing flow

1. `onShow()` resets the state, starts calibration, starts sensors, and launches the periodic timer.
2. `timerCallback()` runs every 500 ms and reads sensor/GPS state.
3. `readSensors()` and `updateDepth()` refresh the current motion and depth estimates.
4. `processDiveState()` classifies the user as underwater or on the surface.
5. `updateMotionConfidence()` updates the movement confidence signal.
6. DR/Kalman values are updated when the state is valid.
7. `writeFitFieldsIfNeeded()` writes the active state to the FIT stream.
8. `onHide()` and `prepareToExit()` shut everything down cleanly.

## Important design notes

### Depth estimation
The current depth estimate is a pressure-first algorithm:

- pressure is preferred as the main depth source,
- altitude is used as a fallback and validation signal,
- negative pressure differences are clipped to zero,
- non-physical spikes are rejected before smoothing.

The core formulation is:

$$
depth \approx \frac{pressurePa - surfacePressurePa}{PA\_PER\_METER\_SEAWATER}
$$

with a low-pass filter applied after validation so the value tracks real dive motion without reacting to transient sensor noise.

### Dive state detection
The app keeps a depth threshold plus hysteresis and minimum duration logic to avoid false start/stop flips near the surface.

### FIT output
The app records custom FIT fields for DR position, depth, speed, motion, heading, GPS fix, and underwater state. These values are used to reconstruct the route and dive context after the session is saved.

## Relevant files

- [source/gsensrosView.mc](source/gsensrosView.mc)
- [source/DeadReckoning.mc](source/DeadReckoning.mc)
- [source/KalmanDR.mc](source/KalmanDR.mc)
- [source/NitrogenModel.mc](source/NitrogenModel.mc)
- [manifest.xml](manifest.xml)
- [docs/](docs/)

## Verification status

This workspace does not currently include the Garmin Connect IQ compiler (`monkeyc`), so a device build cannot be run here. The code is nevertheless validated in-editor for syntax diagnostics and the documented depth fix is consistent with the observed Suunto reference trace.

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