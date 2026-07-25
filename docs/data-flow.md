# gsensros Data Flow

## Main Processing Loop (timerCallback — 500ms)

```
timerCallback()
  │
  ├─ compute dt (time since last callback)
  │
  ├─ readSensors(sensorInfo)
  │     ├─ heartRate → heartRate
  │     ├─ accel[x,y,z] → accelX, accelY, accelZ
  │     ├─ gyro[x,y,z] → gyroX, gyroY, gyroZ (bias-corrected)
  │     ├─ heading → trueHeading, headingEstimate
  │     └─ mag[x,y,z] → magHeading (when heading unavailable)
  │
  ├─ updateDepth(sensorInfo)
  │     ├─ calibrates surface altitude (first 15 samples)
  │     ├─ adapts surface altitude when on deck
  │     └─ computes currentDepth = surfaceAltitude - rawAltitude
  │
  ├─ updateGPS(sensorInfo, posInfo)
  │     ├─ reads GPS speed from sensorInfo
  │     └─ reads GPS position from posInfo
  │
  ├─ processDiveState()
  │     └─ sets isUnderwater based on depth thresholds
  │
  ├─ updateMotionConfidence()
  │     └─ updates movingConfidence counter
  │
  ├─ compute currentAscentRateMps = (lastDepth - currentDepth) / dt
  │
  ├─ n2Model.update(currentDepth, dt, isUnderwater, currentAscentRateMps)
  │
  ├─ [recording only]
  │     ├─ getEstimatedSpeedMps() → estSpeed
  │     ├─ getBestHeading(dt) → bestHeading
  │     ├─ kalman.updateGps(lat, lon) [if GPS fix available]
  │     ├─ kalman.predict(estSpeed, heading, dt) [if no GPS fix]
  │     ├─ dr.updateWithSpeed(accel, gyro, heading, dt, estSpeed)
  │     │   [if should advance DR]
  │     └─ writeFitFieldsIfNeeded(estSpeed, heading) [every 2 ticks]
  │
  └─ WatchUi.requestUpdate()
        └─ onUpdate(dc) [renders UI]
```

## Motion Detection Pipeline

```
sensorDataCallback(sensorData)
  │
  ├─ For each accelerometer sample:
  │     magnitude = sqrt(ax² + ay² + az²)
  │     highPass = magnitude - lastAccelMag
  │     lastAccelMag = lerp(lastAccelMag, magnitude, 0.85)
  │     motionVar = lerp(motionVar, highPass², 0.20)
  │
  ├─ gyroMag = sqrt(gyroX² + gyroY² + gyroZ²)
  │
  ├─ rawScore = sqrt(motionVar) * 1000 + gyroMag * 80
  │
  ├─ Adapt baseline:
  │     baseline = lerp(baseline, rawScore, alpha)
  │     alpha = 0.08 if stationary, 0.015 if moving
  │
  ├─ motionScoreMg = lerp(motionScoreMg, abs(rawScore - baseline), 0.70)
  │
  └─ updateMotionState() with hysteresis:
        onThreshold = 18 (underwater) or 22 (land)
        offThreshold = 8 (underwater) or 10 (land)
        riseCounter += 1 if above onThreshold
        fallCounter -= 1 if below offThreshold
        isMotionDetected = (riseCounter >= 2) or (fallCounter <= -4)
```

## Heading Source Selection (getBestHeading)

```
Priority order:
1. trueHeading         (from Sensor.Info.heading)
2. magHeading          (from magnetometer, when true heading unavailable)
3. headingEstimate     (gyro-integrated estimate, when moving)
4. dr.getHeadingRad()  (dead reckoning heading, last resort)
```

## Dive State Transitions

```
         ┌──────────────────────────┐
         │  Surface (isUnderwater = false) │
         └────────────┬─────────────┘
                      │
              currentDepth > 1.5m
                      │
                      ▼
         ┌──────────────────────────┐
         │  Underwater               │
         │  (isUnderwater = true)    │
         └────────────┬─────────────┘
                      │
              currentDepth ≤ 0.5m
                      │
                      ▼
         ┌──────────────────────────┐
         │  Surface (isUnderwater = false) │
         └──────────────────────────┘
```

## Session Lifecycle

```
onSelect() [center button]
  │
  ├─ [not recording] → startSession()
  │     ├─ startGps()
  │     ├─ captureEntryPosition()
  │     ├─ startRecording()
  │     │     ├─ shutdownSessionWithoutSave() [close previous]
  │     │     ├─ ActivityRecording.createSession()
  │     │     ├─ safeCreateField() for each FIT field
  │     │     └─ session.start()
  │     ├─ reset heading, motion, Kalman, DR
  │     └─ lastUpdateMs = now
  │
  └─ [recording] → stopSession()
        ├─ shutdownSessionSafe()
        │     ├─ session.stop()
        │     └─ session.save()
        ├─ captureExitPosition()
        ├─ stopGps()
        ├─ reset depth, motion, heading
        └─ set hasEntryPosition = false

onBack() [back button]
  │
  ├─ [recording] → push Confirmation dialog
  │     └─ ConfirmStopDelegate.onResponse()
  │           ├─ [YES] → stopSession() + prepareToExit() → pop views
  │           └─ [NO]  → pop confirmation dialog only
  │
  └─ [not recording] → prepareToExit() → return false (system handles exit)
```