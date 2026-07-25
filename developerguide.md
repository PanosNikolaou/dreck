# Garmin Connect IQ Developer Guide
## Dead Reckoning Navigation System for Garmin Wearables

## 1. Overview

This guide documents the Garmin Connect IQ APIs and the app-specific logic used in the `gsensrosView` navigation system. The application combines sensor polling, GPS tracking, dead reckoning, Kalman filtering, and FIT recording in a single wearable app.

This document focuses on:
- Garmin SDK modules and methods used in the code.
- The role of each function in the app.
- How the view, delegate, sensors, GPS, timer, and recording pipeline work together.
- The custom logic implemented in `DeadReckoning` and `KalmanDR`.

---

## 2. Imported Modules

```monkeyc
import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.Sensor;
import Toybox.Timer;
import Toybox.Lang;
import Toybox.System;
import Toybox.ActivityRecording;
import Toybox.Position;
import Toybox.Activity;
import Toybox.FitContributor;
import Toybox.Math;
```

### Module purpose

- `Toybox.Graphics`: Drawing text and UI elements.
- `Toybox.WatchUi`: View lifecycle and input handling.
- `Toybox.Sensor`: Access to accelerometer, gyroscope, magnetometer, and sensor listeners.
- `Toybox.Timer`: Periodic updates.
- `Toybox.System`: Logging and timing utilities.
- `Toybox.ActivityRecording`: FIT session recording.
- `Toybox.Position`: GPS/location data and location event control.
- `Toybox.Activity`: Sport type constants.
- `Toybox.FitContributor`: Custom FIT field definitions.
- `Toybox.Math`: Math utilities such as `atan2()`.

---

## 3. Main View Class

```monkeyc
class gsensrosView extends WatchUi.View
```

`gsensrosView` is the main UI screen. It handles:
- initialization,
- layout,
- periodic updates,
- sensor processing,
- GPS updates,
- recording control,
- and drawing the display.

---

## 4. Class State Variables

The app stores live sensor, navigation, and recording state in member variables.

### Motion and orientation
- `accelX`, `accelY`, `accelZ`
- `gyroX`, `gyroY`, `gyroZ`
- `magHeading`, `trueHeading`
- `headingEstimate`, `hasHeadingEstimate`

### GPS and speed
- `latitude`, `longitude`
- `speed`
- `hasGpsFix`
- `gpsQuality`
- `gpsActive`

### Session state
- `session`
- `isRecording`
- `isUnderwater`

### Timing and filtering
- `updateTimer`
- `lastUpdateMs`
- `fitWriteTick`

### Motion confidence
- `movingConfidence`
- `MOVING_CONFIDENCE_ON`
- `MOVING_CONFIDENCE_MAX`

### Calibration
- `calibrationActive`
- `calibrationStartMs`
- `CALIBRATION_DURATION_MS`
- `gyroBiasX`, `gyroBiasY`, `gyroBiasZ`
- `magBiasX`, `magBiasY`, `magBiasZ`

### FIT field references
- `drEastField`
- `drNorthField`
- `depthField`
- `gpsLatField`
- `gpsLonField`
- `motionField`
- `speedEstField`
- `underwaterField`
- `gpsFixField`
- `headingField`
- `movingField`

### Depth model
- `surfaceAltitudeSum`
- `surfaceAltitude`
- `depthFilter`
- `calibrationSamples`
- `CALIBRATION_COUNT`
- `currentDepth`

### UI scrolling
- `scrollY`
- `SCROLL_STEP`
- `SCROLL_MIN`
- `SCROLL_MAX`

---

## 5. View Lifecycle Methods

## 5.1 `initialize()`

```monkeyc
function initialize()
```

### Purpose
Initializes the view and creates app-specific processing objects.

### What it does
- Calls `View.initialize()`.
- Creates `dr = new DeadReckoning()`.
- Creates `kalman = new KalmanDR()`.

### Notes
`DeadReckoning` and `KalmanDR` are custom classes, not Garmin SDK classes.

---

## 5.2 `onLayout(dc as Dc) as Void`

```monkeyc
function onLayout(dc as Dc) as Void
```

### Parameters
- `dc as Dc`: The drawing context for layout initialization.

### Purpose
Loads the layout resource for the view.

### What it does
- Calls `setLayout(Rez.Layouts.MainLayout(dc))`.

---

## 5.3 `onShow() as Void`

```monkeyc
function onShow() as Void
```

### Purpose
Runs when the view becomes visible.

### What it does
- Resets depth, motion, and heading state.
- Starts the sensor listener.
- Starts the startup calibration phase.
- Creates and starts the periodic timer.

### Important calls
- `System.getTimer()`
- `startMotionListener()`
- `startStartupCalibration()`
- `updateTimer.start(...)`

---

## 5.4 `onHide() as Void`

```monkeyc
function onHide() as Void
```

### Purpose
Runs when the view is hidden.

### What it does
- Stops the timer.
- Stops the sensor listener.
- Stops GPS.

---

## 6. Timer Loop

## 6.1 `timerCallback() as Void`

```monkeyc
function timerCallback() as Void
```

### Purpose
Main update loop for the app.

### Flow
1. Read time delta.
2. Read sensors.
3. Update depth.
4. Update GPS.
5. Update dive state.
6. Update motion confidence.
7. Finish calibration if needed.
8. If recording, perform Kalman and dead reckoning updates.
9. Write FIT fields periodically.
10. Request screen redraw.

### Garmin API used
- `System.getTimer()`
- `Sensor.getInfo()`
- `Position.getInfo()`
- `WatchUi.requestUpdate()`

---

## 7. GPS Control

## 7.1 `startGps() as Void`

```monkeyc
function startGps() as Void
```

### Purpose
Enables continuous location updates.

### Garmin API
```monkeyc
Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
```

### Parameters
- `Position.LOCATION_CONTINUOUS`: constant for continuous GPS updates.
- `method(:onPosition)`: callback method for position events.

---

## 7.2 `stopGps() as Void`

```monkeyc
function stopGps() as Void
```

### Purpose
Disables location updates.

### Garmin API
```monkeyc
Position.enableLocationEvents(Position.LOCATION_DISABLE, null);
```

---

## 7.3 `onPosition(info as Position.Info) as Void`

```monkeyc
function onPosition(info as Position.Info) as Void
```

### Purpose
Handles incoming GPS position updates.

### Important fields
- `info.position`
- `info.accuracy`

### Logic
- Checks if the update is valid.
- Converts coordinates using `toDegrees()`.
- Updates `latitude`, `longitude`, and `hasGpsFix`.

---

## 8. Sensor Listener

## 8.1 `startMotionListener() as Void`

```monkeyc
function startMotionListener() as Void
```

### Purpose
Registers an accelerometer listener.

### Garmin API
```monkeyc
Sensor.registerSensorDataListener(method(:sensorDataCallback), options);
```

### Options used
```monkeyc
var options = {
    :period => SENSOR_PERIOD_SEC,
    :accelerometer => {
        :enabled => true,
        :sampleRate => sampleRate,
        :includePower => true
    }
};
```

### Notes
- `sampleRate` is clamped to `Sensor.getMaxSampleRate()` if needed.
- `includePower` enables access to `accelerometerData.power`.

---

## 8.2 `stopMotionListener() as Void`

```monkeyc
function stopMotionListener() as Void
```

### Purpose
Unregisters the sensor listener.

### Garmin API
```monkeyc
Sensor.unregisterSensorDataListener();
```

---

## 8.3 `sensorDataCallback(sensorData as Sensor.SensorData) as Void`

```monkeyc
function sensorDataCallback(sensorData as Sensor.SensorData) as Void
```

### Purpose
Processes accelerometer power data.

### Important fields
- `sensorData.accelerometerData`
- `accelerometerData.power`

### Logic
- Computes average power.
- Smooths it using exponential filtering.
- Updates `motionScoreMg`.
- Sets `isMotionDetected` based on thresholds.

---

## 9. Motion and Heading

## 9.1 `readSensors(info) as Void`

```monkeyc
function readSensors(info) as Void
```

### Purpose
Reads raw sensor values from `Sensor.getInfo()`.

### Reads
- `info.accel`
- `info.gyro`
- `info.heading`
- `info.mag`

### Logic
- Updates accelerometer values.
- Updates gyro values and applies calibration bias.
- Uses true heading when available.
- Falls back to magnetometer heading if needed.
- Updates magnetic calibration bias during startup calibration.

---

## 9.2 `getBestHeading(dt as Float) as Float or Null`

```monkeyc
function getBestHeading(dt as Float) as Float or Null
```

### Purpose
Chooses the best available heading estimate.

### Priority
1. `trueHeading`
2. `magHeading`
3. Integrated `gyroZ`
4. `dr.getHeadingRad()`
5. `null`

### Parameters
- `dt as Float`: elapsed time in seconds.

---

## 9.3 `normalizeAngleRad(a as Float) as Float`

```monkeyc
function normalizeAngleRad(a as Float) as Float
```

### Purpose
Normalizes an angle into the range \([0, 2\pi)\).

---

## 9.4 `radToDeg(a as Float) as Float`

```monkeyc
function radToDeg(a as Float) as Float
```

### Purpose
Converts radians to degrees.

---

## 10. Depth and Dive State

## 10.1 `resetDepthCalibration() as Void`

```monkeyc
function resetDepthCalibration() as Void
```

### Purpose
Resets the surface altitude reference and depth filter.

---

## 10.2 `updateDepth(info) as Void`

```monkeyc
function updateDepth(info) as Void
```

### Purpose
Computes depth from barometric altitude.

### Logic
- During startup, collects baseline altitude samples.
- After calibration, computes:
  - `rawDepth = surfaceAltitude - rawAlt`
- Applies low-pass filtering.
- Clamps depth to non-negative values.

---

## 10.3 `processDiveState() as Void`

```monkeyc
function processDiveState() as Void
```

### Purpose
Determines whether the user is underwater.

### Logic
- If depth exceeds `DIVE_START_DEPTH_M`, set underwater true.
- If depth falls below `SURFACE_STOP_DEPTH_M`, set underwater false.

---

## 11. Motion Confidence and Speed

## 11.1 `resetMotionState() as Void`

```monkeyc
function resetMotionState() as Void
```

### Purpose
Clears motion score and motion confidence.

---

## 11.2 `isProbablyMoving() as Boolean`

```monkeyc
function isProbablyMoving() as Boolean
```

### Purpose
Determines whether movement is likely.

### Inputs
- GPS speed
- underwater state
- motion score

---

## 11.3 `updateMotionConfidence() as Void`

```monkeyc
function updateMotionConfidence() as Void
```

### Purpose
Increases or decreases confidence that the user is moving.

---

## 11.4 `isStationary() as Boolean`

```monkeyc
function isStationary() as Boolean
```

### Purpose
Checks if the user appears stationary.

### Logic
- Rejects movement if GPS speed is high.
- Rejects movement if motion score is high.
- Rejects movement if gyro Z is high.

---

## 11.5 `getEstimatedSpeedMps() as Float`

```monkeyc
function getEstimatedSpeedMps() as Float
```

### Purpose
Computes a usable speed estimate.

### Priority
1. GPS speed if valid.
2. Zero if movement confidence is too low.
3. Underwater fallback speed.
4. Land fallback speed.
5. Zero.

---

## 11.6 `shouldAdvanceDR(bestHeading as Float or Null, estSpeed as Float) as Boolean`

```monkeyc
function shouldAdvanceDR(bestHeading as Float or Null, estSpeed as Float) as Boolean
```

### Purpose
Decides whether to advance dead reckoning.

### Returns true only if:
- heading exists,
- speed is above threshold,
- motion confidence is high enough,
- user is not stationary.

---

## 12. Recording Control

## 12.1 `onSelect() as Boolean`

```monkeyc
function onSelect() as Boolean
```

### Purpose
Toggles recording.

### Behavior
- If recording, stop the session.
- Otherwise, start a new session.

---

## 12.2 `onBack() as Boolean`

```monkeyc
function onBack() as Boolean
```

### Purpose
Safely exits the app.

### Behavior
- Stops recording if needed.
- Stops timer.
- Stops sensor listener.
- Stops GPS.

---

## 12.3 `startSession() as Void`

```monkeyc
function startSession() as Void
```

### Purpose
Begins a new recording session.

### Steps
- Starts GPS.
- Captures entry position.
- Starts FIT recording.
- Resets heading and motion state.
- Resets Kalman and dead reckoning state.

---

## 12.4 `stopSession() as Void`

```monkeyc
function stopSession() as Void
```

### Purpose
Stops recording and saves data.

### Steps
- Captures exit position.
- Saves FIT session.
- Stops GPS.
- Resets state.

---

## 12.5 `captureEntryPosition() as Void`

```monkeyc
function captureEntryPosition() as Void
```

### Purpose
Stores GPS start coordinates.

---

## 12.6 `captureExitPosition() as Void`

```monkeyc
function captureExitPosition() as Void
```

### Purpose
Stores GPS end coordinates.

---

## 13. FIT Recording

## 13.1 `startRecording() as Void`

```monkeyc
function startRecording() as Void
```

### Purpose
Creates the FIT session and custom fields.

### Garmin APIs used
- `ActivityRecording.createSession(...)`
- `session.createField(...)`
- `session.start()`

### Custom fields created
- DR East
- DR North
- Depth
- GPS Lat
- GPS Lon
- Motion
- Speed Estimate
- Underwater
- GPS Fix
- Heading
- Moving

---

## 13.2 `shutdownSessionSafe() as Void`

```monkeyc
function shutdownSessionSafe() as Void
```

### Purpose
Stops and saves the session.

### Garmin APIs used
- `session.isRecording()`
- `session.stop()`
- `session.save()`

---

## 13.3 `shutdownSessionWithoutSave() as Void`

```monkeyc
function shutdownSessionWithoutSave() as Void
```

### Purpose
Stops an active session without saving it.

---

## 13.4 `writeFitFieldsIfNeeded(estSpeed as Float, bestHeading as Float or Null) as Void`

```monkeyc
function writeFitFieldsIfNeeded(estSpeed as Float, bestHeading as Float or Null) as Void
```

### Purpose
Writes custom values into the FIT record fields.

### Uses
- `field.setData(value)`

### Values written
- East/North position
- Depth
- Motion score
- Speed estimate
- Underwater flag
- GPS fix flag
- Heading
- Moving flag
- Latitude/longitude when valid

---

## 14. Helper Methods

## 14.1 `floatEquals(a as Float, b as Float, eps as Float) as Boolean`

Compares two float values with tolerance.

## 14.2 `isFiniteValue(v) as Boolean`

Checks whether a numeric value is valid before writing.

## 14.3 `writeFloatField(...)`

Writes float FIT data only when it changes enough.

## 14.4 `writeUIntField(...)`

Writes integer FIT data only when it changes.

## 14.5 `errorToString(e) as String`

Returns a safe error message string.

---

## 15. UI Rendering

## 15.1 `onUpdate(dc as Dc) as Void`

```monkeyc
function onUpdate(dc as Dc) as Void
```

### Purpose
Draws the current screen.

### Garmin Graphics APIs used
- `dc.setColor(...)`
- `dc.drawText(...)`
- `dc.getWidth()`

### Displayed values
- Recording state
- Mode
- GPS status
- Quality
- Motion
- Depth
- Calibration countdown
- Kalman or DR coordinates
- Speed

### Scrolling
The vertical offset is controlled by:
```monkeyc
var y = 8 + scrollY;
```

---

## 16. Exit Cleanup

## 16.1 `prepareToExit() as Void`

```monkeyc
function prepareToExit() as Void
```

### Purpose
Performs safe cleanup before leaving the screen.

### Steps
- Stops session if recording.
- Stops timer.
- Stops sensor listener.
- Stops GPS.

---

## 17. Custom Classes

These are not Garmin SDK classes and should be documented separately.

### `DeadReckoning`
Used for inertial navigation and heading-based propagation.

### `KalmanDR`
Used for position prediction and GPS correction.

### Suggested custom methods
- `reset()`
- `resetWithHeading(...)`
- `updateWithSpeed(...)`
- `hasValidHeading()`
- `getHeadingRad()`
- `getDRData()`
- `setReference(...)`
- `predict(...)`
- `updateGps(...)`
- `getEast()`
- `getNorth()`

---

## 18. Typical App Flow

1. `onShow()` starts the timer and sensor listener.
2. `timerCallback()` polls sensors and updates state.
3. `onSelect()` starts or stops recording.
4. `startSession()` creates the session and begins FIT logging.
5. `onUpdate()` redraws the interface.
6. `onBack()` or `onHide()` stops everything safely.

---

## 19. Notes for Development

- Use `WatchUi.requestUpdate()` whenever state changes.
- Keep sensor and GPS handling lightweight for wearable performance.
- Use calibration early in the session for better bias correction.
- Keep FIT writes throttled to reduce overhead.
- Clamp or validate all float values before writing to FIT.

---

## 20. Summary

This app is a full Connect IQ wearable navigation system built from:
- `WatchUi.View` for display,
- `BehaviorDelegate` for input,
- `Sensor` for