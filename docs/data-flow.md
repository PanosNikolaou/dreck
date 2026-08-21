# gsensros Data Flow

## Main processing loop (500 ms)

```text
timerCallback()
  │
  ├─ compute dt
  ├─ readSensors(sensorInfo)
  │     ├─ heart rate / SpO2 / temp
  │     ├─ accelerometer and gyroscope
  │     ├─ heading and magnetometer
  │     └─ ambient pressure and altitude data
  │
  ├─ updateDepth(sensorInfo)
  │     ├─ collect valid pressure samples
  │     ├─ seed surface baseline from first valid reading
  │     ├─ compute pressure depth
  │     ├─ compute altitude depth if valid
  │     ├─ reject impossible jumps
  │     └─ apply low-pass smoothing
  │
  ├─ updateGPS(sensorInfo, posInfo)
  │     ├─ GPS quality check
  │     └─ update location, speed, fix state
  │
  ├─ processDiveState()
  │     └─ classify underwater / surface state with hysteresis
  │
  ├─ updateMotionConfidence()
  │     └─ motion score and confidence tracking
  │
  ├─ currentAscentRateMps = (lastDepthForAscent - currentDepth) / dt
  │
  ├─ n2Model.update(currentDepth, dt, isUnderwater, currentAscentRateMps)
  │
  ├─ if recording is active:
  │     ├─ getEstimatedSpeedMps()
  │     ├─ getBestHeading(dt)
  │     ├─ update DR / Kalman fusion
  │     └─ writeFitFieldsIfNeeded()
  │
  └─ WatchUi.requestUpdate()
```

## Depth calculation path

```text
pressurePa
  │
  ├─ valid surface sample? -> set surfacePressurePa
  │
  └─ current depth = (pressurePa - surfacePressurePa) / PA_PER_METER_SEAWATER
           if pressurePa > 50000 Pa and surfacePressurePa valid

altitude
  │
  └─ if valid, altitudeDepth = surfaceAltitude - rawAlt

final depth
  │
  ├─ if both pressure and altitude are valid:
  │     blend pressure and altitude with pressure priority
  │
  ├─ if only pressure is valid: use pressure depth
  │
  ├─ if only altitude is valid: use altitude depth
  │
  └─ clamp and smooth before storing in currentDepth
```

## Motion detection pipeline

```text
sensorDataCallback()
  │
  ├─ read raw accelerometer sample(s)
  ├─ compute magnitude and high-pass signal
  ├─ update motion variance and adaptive baseline
  ├─ convert to motionScoreMg
  ├─ hysteresis gating (motion on/off)
  └─ update isMotionDetected and movingConfidence
```

## Heading selection

```text
Priority order:
1. true heading
2. magnetometer heading
3. last valid DR heading / gyro-assisted estimate
``` 

## Dive-state transitions

```text
Surface
  └─ currentDepth > DIVE_START_DEPTH_M -> Dive start
Dive
  └─ currentDepth <= SURFACE_STOP_DEPTH_M and return near entry point -> end dive
```

## Session lifecycle

```text
startSession()
  ├─ reset state
  ├─ start GPS
  ├─ start recording
  ├─ create FIT fields
  └─ begin timer

stopSession()
  ├─ stop recording
  ├─ save session
  ├─ stop GPS
  └─ reset state
```

## Why the fix matters

The original pressure/altitude design could fall into a startup calibration dead zone and hold zero-depth values until the calibration window completed. Using the first valid pressure sample as the baseline eliminates that lag and keeps the trace aligned with the Suunto Ocean reference.