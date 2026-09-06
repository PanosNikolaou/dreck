# DRFusionTrack Data Flow

## Main Loop (500 ms)

```text
timerCallback()
  ├─ dt from System.getTimer()
  ├─ sensorInfo = Sensor.getInfo()
  ├─ posInfo = Position.getInfo()
  ├─ readSensors(sensorInfo)
  ├─ updateDepth(sensorInfo, posInfo)
  ├─ updateGPS(sensorInfo, posInfo)
  ├─ processDepthState()
  ├─ updateMotionConfidence()
  ├─ update DR + Kalman fusion
  ├─ writeFitFieldsIfNeeded() (throttled)
  └─ WatchUi.requestUpdate()
```

## Depth Source Resolution

`updateDepth(sensorInfo, posInfo)` resolves input in this order:

1. direct depth (`depth`, `enhancedDepth`)
2. pressure (`pressure`, `ambientPressure`) normalized to Pa
3. altitude (`altitude`, `enhancedAltitude`, `Position.Info.altitude`)
4. simulator synthetic fallback if no pressure/direct-depth and altitude is flat

Runtime source tag:

- `D` direct depth
- `P` pressure
- `ALT` sensor altitude
- `GPS_ALT` position altitude
- `SIM` synthetic depth for simulator-only testability
- `NONE` no usable source

## Depth Computation

Pressure branch:

$$
depth_P = \max\left(0,\ \frac{pressurePa - surfacePressurePa}{PA\_PER\_METER\_SEAWATER}\right)
$$

Altitude branch (sign-robust):

$$
depth_{A1} = \max(0,\ surfaceAltitude - rawAlt)
$$

$$
depth_{A2} = \max(0,\ rawAlt - surfaceAltitude)
$$

If only altitude exists, the larger plausible positive branch is selected.

If both pressure and altitude exist, pressure is dominant and altitude is weakly blended.

Output depth is rate-limited, low-pass filtered, and clamped.

## Motion Pipeline

Primary motion evidence:

- accelerometer and gyroscope from `sensorDataCallback()`
- hysteresis-based motion state

Fallback motion evidence:

- GPS speed when valid
- Kalman displacement-derived speed (`kfDerivedSpeedMps`) when IMU is sparse in simulator

## Recording Flow

When recording is active:

1. heading and speed are resolved
2. DR/KF state advances
3. FIT fields are written using epsilon/change-based write helpers
4. diagnostics (`DRDIAG`, `DEPTHDBG`) can be emitted for troubleshooting

## Simulator-Specific Note

If simulator altitude is constant and pressure is unavailable, real depth cannot be derived from raw sensors. In this case source `SIM` is intentionally used so depth/FIT flows can still be validated end-to-end.