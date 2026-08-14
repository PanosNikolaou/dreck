# FIT fields and formulas

This document is a detailed reference for the FIT record fields written during tracking and recording. It explains what each field represents, where it is created in the app, how the value is computed, and why it is included in the current recording stream.

## 1. Recording pipeline overview

The FIT writing path is centered in [source/gsensrosView.mc](../source/gsensrosView.mc), with the navigation and state estimates coming from [source/DeadReckoning.mc](../source/DeadReckoning.mc) and [source/KalmanDR.mc](../source/KalmanDR.mc).

The high-level flow is:

1. Sensor and GPS callbacks update the current state.
2. The app updates dive state, motion confidence, heading, and position estimates.
3. The values are converted into FIT-ready scalars.
4. The values are written to the active recording stream through the FIT contributor field interface.

The implementation is designed to be compact and practical for Garmin devices, so the app favors a small set of useful record fields rather than a very large diagnostic payload.

## 2. FIT fields currently stored

The following record fields are created during recording in [source/gsensrosView.mc](../source/gsensrosView.mc):

- DR_East (id 0, float, m)
- DR_North (id 1, float, m)
- Depth (id 2, float, m)
- Speed (id 3, float, m/s)
- Heading (id 4, float, deg)
- Underwater (id 5, uint32, unitless)
- Motion (id 6, float, mg)
- Moving (id 7, uint32, unitless)
- GpsFix (id 8, uint32, unitless)
- DR_Lat (id 9, float, deg)
- DR_Lon (id 10, float, deg)
- POI_Id (id 11, uint32, unitless)
- POI_Lat (id 12, float, deg)
- POI_Lon (id 13, float, deg)
- DR_Diag (id 28, uint32, unitless, optional)

The most important practical meaning of this set is:

- navigation: DR_East, DR_North, DR_Lat, DR_Lon
- environment / dive state: Depth, Underwater
- motion / activity: Speed, Heading, Motion, Moving
- GPS availability: GpsFix
- debugging / diagnostics: DR_Diag
- user markers: POI_Id, POI_Lat, POI_Lon

## 3. Fields declared but not currently active

These are declared in the source, but they are not created as live record fields in the current build:

- FIELD_GPS_LAT (id 14) / FIELD_GPS_LON (id 15)
  - Intended for direct GPS lat/lon logging, but not created because the current recording path stores synthetic DR-derived lat/lon instead.
- FIELD_N2_LOAD (id 16) / FIELD_N2_MAX (id 17) / FIELD_N2_BAND (id 18)
  - Reserved for nitrogen model outputs, but not written because the current app keeps those values as UI/model state rather than streaming them into FIT.
- FIELD_HR (id 19)
  - Reserved for heart-rate logging, but not enabled in the current record stream to preserve field budget and keep the FIT payload focused on navigation and motion.
- FIELD_ASCENT (id 20)
  - Reserved for ascent-rate logging, but not connected to the active streaming path.
- FIELD_SPO2 (id 21)
  - Reserved for SpO2 data, but not currently created to avoid expanding the field set further.
- FIELD_TEMP (id 22)
  - Reserved for temperature logging, but not active in the current live record pipeline.
- FIELD_MAX_DEPTH (id 23) / FIELD_DIVE_TIME (id 24) / FIELD_MAX_N2 (id 25)
  - Declared as session-summary style fields, but not emitted because the app does not currently write session-level summary values.
- FIELD_POI_EAST (id 26) / FIELD_POI_NORTH (id 27)
  - Intended as local coordinate POI fields, but not used because the app currently records POI data as lat/lon rather than local east/north values.

This distinction is important because it separates:

- fields that are actively being recorded now
- fields that are prepared for future expansion
- fields that are intentionally left unused for now

## 4. Where the fields are created

Field creation happens in the recording setup path in [source/gsensrosView.mc](../source/gsensrosView.mc), inside the startRecording() flow.

The active record fields are created with a helper such as safeCreateField(), and the optional diagnostic field is conditionally created when the feature toggle is enabled.

In practice, the field creation step establishes the FIT schema for the session before data recording begins. Once a field exists, the app can write values into it repeatedly as the recording progresses.

## 5. Where values are written

Values are written from writeFitFieldsIfNeeded() in [source/gsensrosView.mc](../source/gsensrosView.mc).

This function is called periodically from the main timer loop. It does not write every value on every tick. Instead, it checks whether the new value has changed enough to be worth updating, which reduces unnecessary FIT traffic and improves efficiency.

The write flow is effectively:

- read the latest state estimate
- convert it into the required FIT value type
- compare with the previous value
- write only if the change is significant

## 6. Field-by-field details

### 6.1 DR_East / DR_North

Source:
- Dead reckoning propagation in [source/DeadReckoning.mc](../source/DeadReckoning.mc)
- Kalman state update in [source/KalmanDR.mc](../source/KalmanDR.mc)

Meaning:
- The current local position estimate in meters relative to the entry point or local coordinate frame.

How it is computed:
- The dead-reckoning part integrates heading and speed into incremental movement:

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

- The Kalman filter also maintains a state vector roughly of the form $[east, north, velEast, velNorth]$ and propagates it over time using a constant-velocity motion model.

Why it matters:
- These are the core navigation coordinates used for the DR track.

### 6.2 Depth

Source:
- updateDepth() in [source/gsensrosView.mc](../source/gsensrosView.mc)

Meaning:
- Current dive depth in meters.

How it is computed:
- The app estimates a reference pressure at the surface and then compares the current ambient pressure to that reference.
- The depth estimate is derived from pressure difference using the water-density approximation:

$$
depth = \frac{surfacePressurePa - pressurePa}{PA\_PER\_METER\_SEAWATER}
$$

- The result is clamped and smoothed to avoid jumps from noisy pressure samples.

Why it matters:
- Depth is one of the core environmental values for the dive context and is used to drive underwater state logic.

### 6.3 Speed

Source:
- getEstimatedSpeedMps() in [source/gsensrosView.mc](../source/gsensrosView.mc)

Meaning:
- The app’s best estimate of forward speed in meters per second.

How it is computed:
- The logic prioritizes the most trustworthy source available:
  1. GPS speed if it is reliable
  2. sensor-based motion estimation if the confidence is good
  3. a fallback map from motion score to a plausible speed range

The fallback uses motion thresholds. For land and swim modes, the app maps motion score into a target speed range using interpolation.

Example structure:

$$
if\ motionScoreMg \le MIN\_MOTION\_LAND\_MG \Rightarrow target = MIN\_LAND\_SPEED\_MPS
$$

$$
if\ motionScoreMg \ge MAX\_MOTION\_LAND\_MG \Rightarrow target = MAX\_LAND\_SPEED\_MPS
$$

For underwater values, the same idea applies with swim thresholds:

$$
if\ motionScoreMg \le MIN\_MOTION\_SWIM\_MG \Rightarrow target = MIN\_SWIM\_SPEED\_MPS
$$

$$
if\ motionScoreMg \ge MAX\_MOTION\_SWIM\_MG \Rightarrow target = MAX\_SWIM\_SPEED\_MPS
$$

- Between the lower and upper bounds, a linear interpolation produces the final speed estimate.

Why it matters:
- Speed is the main quantity that drives the DR position propagation.

### 6.4 Heading

Source:
- getBestHeading() in [source/gsensrosView.mc](../source/gsensrosView.mc)

Meaning:
- The best heading estimate used by the DR model, expressed in degrees.

How it is computed:
- The app first prefers a trusted true heading if available.
- If that is unavailable, it falls back to the magnetometer heading if that estimate is accepted.
- If neither is usable, it falls back to the DR heading estimate.
- Final conversion from radians to degrees is:

$$
headingDeg = headingRad \cdot \frac{180}{\pi}
$$

Why it matters:
- Heading defines the direction of travel for the dead-reckoning update.

### 6.5 Underwater

Source:
- processDiveState() in [source/gsensrosView.mc](../source/gsensrosView.mc)

Meaning:
- A boolean-like state flag that marks whether the app considers the user underwater.

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
