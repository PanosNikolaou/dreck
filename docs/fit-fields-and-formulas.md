# FIT Fields and Formulas

## 1. Scope

This document reflects the current implementation in [../source/gsensrosView.mc](../source/gsensrosView.mc), including the latest depth-source tracking and simulator fallback behavior.

## 2. Record Fields (Current)

Primary record fields created in-session:

- `DR_East` (float, m)
- `DR_North` (float, m)
- `Depth` (float, m)
- `Speed` (float, m/s)
- `Heading` (float, deg)
- `DepthActive` (uint32)
- `Motion` (float, mg)
- `Moving` (uint32)
- `GpsFix` (uint32)
- `DR_Lat` (float, deg)
- `DR_Lon` (float, deg)
- `POI_Id` (uint32)
- `POI_Lat` (float, deg)
- `POI_Lon` (float, deg)
- optional `DR_Diag` (uint32)

Note: `depthSourceTag` (`P`, `D`, `ALT`, `GPS_ALT`, `SIM`, `NONE`) is a runtime diagnostic signal and UI/log value, not a FIT field.

## 3. Depth Formulas

Pressure path:

$$
depth_P = \max\left(0,\ \frac{pressurePa - surfacePressurePa}{PA\_PER\_METER\_SEAWATER}\right)
$$

Altitude path (sign-robust):

$$
depth_{A1} = \max(0,\ surfaceAltitude - rawAlt)
$$

$$
depth_{A2} = \max(0,\ rawAlt - surfaceAltitude)
$$

If only altitude exists, the larger plausible branch is selected.

Blended path (when both pressure and altitude exist):

$$
depth_{raw} = depth_P \cdot w_P + depth_A \cdot w_A
$$

where pressure dominates and altitude weight is reduced when branches disagree.

Output depth is then:

1. rate-limited by maximum physical change per second
2. low-pass filtered
3. clamped to `[0, MAX_DEPTH_M]`

## 4. Depth Source Resolution

Order:

1. `depth` or `enhancedDepth` (`D`)
2. `pressure` or `ambientPressure` (`P`, normalized from Pa/hPa/kPa)
3. `altitude`, `enhancedAltitude`, or `Position.Info.altitude` (`ALT`/`GPS_ALT`)
4. simulator synthetic depth (`SIM`) if no real depth source exists and altitude is flat

## 5. Motion and Moving

Motion score is IMU-based when available. Moving confidence combines:

- IMU motion evidence
- GPS speed evidence
- Kalman displacement-derived fallback speed in simulator-limited runs

`Moving` FIT bit is set when confidence indicates movement and `isStationary()` is false.

## 6. DR Coordinate Formulas

$$
stepEast = speedMps \cdot \sin(headingRad) \cdot dt
$$

$$
stepNorth = speedMps \cdot \cos(headingRad) \cdot dt
$$

$$
eastMeters \leftarrow eastMeters + stepEast
$$

$$
northMeters \leftarrow northMeters + stepNorth
$$

Synthetic DR lat/lon projection:

$$
synthLat = entryLat + \frac{northMeters}{111000}
$$

$$
synthLon = entryLon + \frac{eastMeters}{111000 \cdot \cos(entryLatRad)}
$$

## 7. Write Policy

Write helpers avoid redundant values:

- float fields write only when delta exceeds epsilon
- uint fields write only on change

This keeps FIT records compact and reduces needless churn while preserving meaningful transitions.

## 8. Simulator Note

When simulator provides no pressure and constant altitude, real depth cannot be derived. In that mode source `SIM` is used to validate UI/FIT pipeline behavior end-to-end.

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
