# FIT fields and formulas

This guide explains the FIT fields produced by the Garmin app, the formulas used to compute them, and the current depth logic that was corrected against the Suunto Ocean reference log.

## 1. Overview

The FIT writing path is centered in [source/gsensrosView.mc](../source/gsensrosView.mc), with navigation estimates coming from [source/DeadReckoning.mc](../source/DeadReckoning.mc) and [source/KalmanDR.mc](../source/KalmanDR.mc).

The app produces a compact real-time stream of useful values rather than a large scientific payload. The most important fields are:

- DR East / North
- Depth
- Speed estimate
- Heading
- Underwater state
- Motion / moving state
- GPS fix state

## 2. FIT fields currently stored

The active set includes:

- DR_East (float, m)
- DR_North (float, m)
- Depth (float, m)
- Speed (float, m/s)
- Heading (float, deg)
- Underwater (uint32)
- Motion (float, mg)
- Moving (uint32)
- GpsFix (uint32)
- DR_Lat / DR_Lon (float, deg)
- POI_Id, POI_Lat, POI_Lon
- optional DR_Diag values

These fields are written mainly from the timer loop via `writeFitFieldsIfNeeded()`.

## 3. Depth formula and current implementation

The corrected depth formula uses pressure as the primary source:

$$
depth \approx \frac{pressurePa - surfacePressurePa}{PA\_PER\_METER\_SEAWATER}
$$

where:

- `surfacePressurePa` is the live baseline calibrated from the first valid pressure reading,
- `PA_PER_METER_SEAWATER` is the water-density approximation used by the app,
- negative values are clipped to zero,
- deep spikes and impossible jumps are rejected before smoothing.

The app also computes an altitude-based estimate:

$$
altitudeDepth = surfaceAltitude - rawAlt
$$

and then blends the two values when both are valid, with pressure taking priority. This prevents the old altitude-only behavior from dominating the estimate when the barometer is stable and the GPS/altitude path is noisy.

The final filtered depth is passed through a low-pass filter:

$$
depthFilter = 0.6 \cdot depthFilter + 0.4 \cdot rawDepth
$$

This gives a much more natural dive trace than the older flat-zero startup behavior.

## 4. DR position formulas

The dead reckoning update uses heading and speed to estimate local displacement:

$$
stepEast = speedMps \cdot \sin(headingRad) \cdot dt
$$

$$
stepNorth = speedMps \cdot \cos(headingRad) \cdot dt
$$

$$
eastMeters = eastMeters + stepEast
$$

$$
northMeters = northMeters + stepNorth
$$

This is the basic tracking model used in the app when GPS is weak or unavailable.

## 5. Speed estimation

The app favors the most trustworthy source available:

1. GPS speed if usable
2. motion-derived speed estimate
3. fallback motion mapping for low-quality conditions

The fallback uses motion thresholds to produce a plausible speed estimate rather than a brittle constant.

## 6. Heading and motion notes

Heading is chosen from the strongest source available, while motion confidence is handled by a hysteresis model so small sensor noise does not trigger state flips.

That means the app uses:

- true heading when present,
- magnetometer-based heading when useful,
- motion score and gyroscope magnitude for underwater movement detection,
- filtered confidence to decide whether the system should advance DR or hold the last valid state.

## 7. Why the corrected depth logic matters

The Suunto Ocean reference dive log contains realistic shallow values, while the Garmin export previously flattened to zero. Any fit/export pipeline that maintains zero depth during startup calibration is effectively discarding the actual underwater trace.

The corrected algorithm resolves that problem by using the first valid pressure sample as the active surface baseline and keeping the live depth estimate active immediately instead of waiting for the calibration delay to end.
How it is computed:
- The app tracks the dive state with depth thresholds and hysteresis so that the state does not oscillate around the transition point.
- The field is written as a binary value:

$$
underwaterVal = 1 \ if\ underwater\ else\ 0
$$

Why it matters:
- It provides a simple state indicator for downstream analysis and for selecting the correct motion/speed logic.

### 6.6 Motion

Source:
- sensorDataCallback() and updateMotionState() in [source/gsensrosView.mc](../source/gsensrosView.mc)

Meaning:
- A continuous motion score in millig units, intended to reflect how active or dynamic the movement is.

How it is computed:
- The app combines acceleration and gyro evidence with a baseline adaptation step.
- A simplified form is:

$$
rawScore = \sqrt{motionVar} \cdot 1000 + gyroMag \cdot GYRO\_WEIGHT
$$

- The result is then smoothed using an exponential filter:

$$
motionScoreMg = alpha \cdot motionScoreMg + (1 - alpha) \cdot delta
$$

where:

$$
delta = max(rawScore - motionBaselineMg, 0)
$$

and a typical smoothing factor is $alpha = 0.55$.

Why it matters:
- It gives a compact measure of movement intensity that can be used both for UI feedback and for speed estimation.

### 6.7 Moving

Source:
- updateMotionConfidence() in [source/gsensrosView.mc](../source/gsensrosView.mc)

Meaning:
- A binary-like confidence flag indicating whether the system believes the user is moving.

How it is computed:
- The app builds a moving confidence from sensor motion evidence and other state checks.
- The field is written as:

$$
movingVal = 1 \ if\ (movingConfidence \ge MOVING\_CONFIDENCE\_ON\ and\ \!isStationary())\ else\ 0
$$

Why it matters:
- It is a simple interpretation of the motion state that is easier to analyze than a raw motion score.

### 6.8 GpsFix

Source:
- onPosition() in [source/gsensrosView.mc](../source/gsensrosView.mc)

Meaning:
- Whether a usable GPS fix was received.

How it is computed:
- The app checks whether a Position.Info object exists and whether the fix quality is acceptable for use.
- The field is written as:

$$
gpsFixVal = 1 \ if\ hasGpsFix\ else\ 0
$$

Why it matters:
- It provides a direct record of whether the path was aided by GPS at the time the sample was recorded.

### 6.9 DR_Lat / DR_Lon

Source:
- writeFitFieldsIfNeeded() in [source/gsensrosView.mc](../source/gsensrosView.mc)

Meaning:
- Synthetic latitude/longitude values derived from the DR coordinate estimate.

How it is computed:
- The app converts local east/north displacement into latitude/longitude using the entry reference point and Earth approximation:

$$
meterPerDegLat = 111000
$$

$$
meterPerDegLon = 111000 \cdot \cos(entryLatRad)
$$

$$
synthLat = entryLat + \frac{northVal}{metersPerDegLat}
$$

$$
synthLon = entryLon + \frac{eastVal}{metersPerDegLon}
$$

Why it matters:
- These values make the DR track compatible with lat/lon-based downstream tools and map displays even though the core estimate is local.

### 6.10 POI_Id / POI_Lat / POI_Lon

Source:
- markPoi() in [source/gsensrosView.mc](../source/gsensrosView.mc)

Meaning:
- User-placed point-of-interest markers associated with the recording session.

How it is computed:
- Each new POI receives an incrementing numeric id.
- The position is taken from either live GPS or the current DR/Kalman estimate depending on availability.
- The POI is stored with its position in lat/lon and a numeric id.

Why it matters:
- It allows the activity to be annotated with important places or events while recording.

### 6.11 DR_Diag

Source:
- packDrDiagnosticsValue() in [source/gsensrosView.mc](../source/gsensrosView.mc)

Meaning:
- A compact packed diagnostic snapshot from the DR/GPS-loss path.

How it is computed:
- The payload is packed into a single uint32 so that it fits the Garmin field budget more easily than creating several separate diagnostic fields.
- The value is assembled from four smaller pieces of information:

$$
value = (gpsBit \ll 24) \;|\; (headingByte \ll 16) \;|\; (motionByte \ll 8) \;|\; gyroByte
$$

Where:
- $gpsBit$ is 1 if GPS is usable, otherwise 0
- $headingByte$ is a quantized representation of the heading confidence or heading quality signal
- $motionByte$ is a quantized representation of the motion score
- $gyroByte$ is a quantized representation of gyro activity

The packing is intentionally lossy and compact, because the goal is to preserve the diagnostic state without consuming too many FIT developer fields.

Why it matters:
- It gives a lightweight way to inspect whether the app was in a GPS-good state, whether heading confidence was strong, and whether motion/gyro activity was high during the sample.

## 7. Write behavior and update policy

The app uses helpers such as writeFloatField() and writeUIntField() to avoid writing identical values repeatedly.

This means the record stream is not an unfiltered sample dump. Instead:

- float fields are written only if the difference from the previously written value exceeds an epsilon tolerance
- uint fields are written only when the value actually changes

This makes the FIT stream smaller and easier to interpret, while still capturing the important transitions and state changes.

## 8. Practical interpretation of the main fields

- DR_East / DR_North: the core local navigation estimate
- Depth: current dive depth
- Speed: estimated motion speed
- Heading: direction of travel used for DR propagation
- Underwater / Moving: state flags for dive and motion activity
- Motion: sensor-derived movement intensity
- GpsFix: whether GPS was available at that recording instant
- DR_Diag: compact DR/GPS-loss diagnostic state
- POI fields: user-place annotations during the session

## 9. Design notes

The field set is intentionally balanced between:

- usefulness for post-analysis
- compatibility with Garmin FIT field limits
- minimal overhead in the recording stream

The current design prioritizes the core path of navigation and dive state, while keeping a compact diagnostic channel available for debugging DR or GPS-loss behavior.
