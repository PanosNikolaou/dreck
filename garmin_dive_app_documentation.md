# DRFusionTrack Technical Documentation

## Overview

DRFusionTrack is a custom Garmin Connect IQ watch app for underwater navigation and recording. It is designed to estimate depth, heading, motion, and local positional drift using pressure, IMU data, and GPS when available. The app records custom FIT telemetry suitable for later review and analysis.

This project is not a native Garmin dive-computer mode. It is a custom underwater tracker that focuses on practical live estimation and post-session reconstruction.

## Final architecture

The current implementation includes five main responsibilities:

- sensor acquisition and listener setup,
- pressure-based depth estimation with live surface calibration,
- motion and heading estimation from IMU sensors,
- local dead reckoning with GPS correction,
- FIT recording and UI reporting.

## Runtime behavior

During a session, the app monitors GPS and motion, tracks underwater state, updates the local DR estimate, and writes FIT values at regular intervals. It is tuned to behave sensibly when the device is moving in shallow water, when GPS is weak, or when sensor noise rises.

The app records:

- depth,
- motion score and moving state,
- heading and heading confidence,
- GPS fix quality,
- underwater state,
- local East/North track,
- synthetic DR lat/lon values.

## Pressure-first depth logic

The final depth implementation is pressure-first and intentionally conservative.

The app:

- starts from the first valid pressure sample as the active surface reference,
- preserves realistic shallow readings instead of discarding them,
- treats altitude as a secondary signal,
- clamps invalid values and rejects impossible spikes,
- applies a low-pass filter to reduce jitter.

The main model is:

$$
depth \approx \frac{P_{ambient} - P_{surface}}{PA\_PER\_METER\_SEAWATER}
$$

with a seawater constant of approximately:

$$
PA\_PER\_METER\_SEAWATER \approx 10050 \; Pa/m
$$

## Motion and heading model

The app computes motion using accelerometer and gyroscope evidence, then applies hysteresis and confidence gating to avoid false transitions. Heading is resolved by highest-priority valid source:

1. true heading if available,
2. magnetometer heading with bias correction,
3. gyro-integrated heading when motion is valid,
4. previous valid heading as a fallback.

## Dead reckoning and GPS fusion

The app maintains a local East/North position estimate and updates it with speed and heading. GPS is used only as a correction signal when quality is usable. This prevents the position estimate from drifting or jumping too aggressively in weak-signal conditions.

The local state follows:

$$
\mathbf{x} = [E, N, v_E, v_N]^T
$$

The predictor uses speed and heading, while the GPS update corrects the estimate only if the fix is valid enough. This is the mechanism that keeps the runtime track usable through temporary GPS loss or multipath conditions.

## FIT fields

The app writes custom developer fields such as:

- DR East / North,
- Depth,
- Speed estimate,
- Heading,
- Underwater state,
- Motion / moving state,
- GPS fix quality,
- synthetic DR latitude / longitude.

This makes the session suitable for later review and analysis with external tools.

## Recommended usage notes

1. treat pressure as the primary depth source,
2. use GPS only as a sparse correction signal,
3. keep the baseline active from the first valid sample,
4. keep DR as a tracking aid when GPS quality is poor,
5. analyze FIT data after the session rather than trusting it as a certified dive computer output.

## Verification status

The current project builds successfully with the available Garmin Connect IQ toolchain. Verified checks are performed through the local project build flow and the generated app remains consistent with the DRFusionTrack branding and features.

## Final note

The current implementation is the authoritative project state: pressure-first depth, conservative motion gating, local dead-reckoning tracking, and practical FIT logging for underwater analysis.
