# Garmin Connect IQ Dive App Documentation

## Overview

This project is a custom Garmin Connect IQ dive-tracking app that runs on Instinct-class devices and records underwater activity, depth, motion, heading, and DR/GPS position data. The implementation is built around the real device APIs and the actual constraints of the target hardware: limited memory, constrained CPU, noisy GPS in water, and a watch UI that must remain responsive while recording.

The app is not a native Garmin dive-computer mode. It is a custom activity tracker that logs dive-relevant telemetry and produces fit fields suitable for post-session analysis.

## Final architecture

The current implementation has five main responsibilities:

- sensor acquisition and listener setup via `Sensor.getInfo()` and the sensor callback path
- pressure-based depth estimation with a live baseline and smoothing
- motion and heading estimation using accelerometer, gyroscope, and magnetometer
- dead reckoning plus GPS correction through a lightweight UKF in local East/North coordinates
- FIT recording and UI updates with custom developer fields

## Runtime behavior

The recorded session can be started with the Select button and stopped with Back. During recording, the app keeps the GPS and motion listeners active, calculates depth continuously, advances the DR state when motion is plausible, and writes FIT fields at a regular interval.

The app also tracks:

- depth
- motion score and moving state
- heading and heading confidence
- GPS fix quality
- underwater state
- DR position and synthetic lat/lon
- POI markers

## Pressure-first depth logic

The final depth implementation is pressure-first and matches the actual runtime code.

The app does this:

- uses the first valid pressure sample as the live reference baseline
- accepts real shallow pressure values instead of zeroing them out during startup
- treats altitude as a secondary estimate rather than the dominant one
- clamps invalid negative or unreasonable values
- applies a responsive low-pass smoothing step to avoid jitter

The core relationship is:

$$
depth \approx \frac{P_{ambient} - P_{surface}}{PA\_PER\_METER\_SEAWATER}
$$

where the seawater constant is approximately:

$$
PA\_PER\_METER\_SEAWATER \approx 10050 \; Pa/m
$$

This is the source of the app’s final behavior and is the design that is now reflected in the code and validation work.

## Why the earlier issue happened

The previous issue was not a reference-data problem alone. The root cause was a combination of:

- delayed baseline adoption while waiting for startup calibration
- altitude being trusted too early
- pressure-derived depth being discarded during the warm-up phase
- zero-valued runtime diagnostics caused by missing gyro listener registration

The final implementation fixes those issues by preserving live values, registering the needed sensors, and using actual pressure as the primary depth source.

## Motion and heading model

The app estimates motion using a combination of:

- accelerometer magnitude and high-pass variance
- gyroscope magnitude
- motion hysteresis and confidence counters

Heading is resolved in priority order:

1. true heading if available
2. magnetometer heading after bias correction
3. gyro-integrated heading when the device is not stationary
4. previous valid heading estimate

This prevents the heading estimate from collapsing to a random or stale value while the device is in motion.

## Dead reckoning and GPS fusion

The app uses a lightweight local 2-D UKF in an East/North frame. The state is:

$$
\mathbf{x} = [E, N, v_E, v_N]^T
$$

The state is propagated using estimated speed and heading; GPS is only used as a measurement correction when quality is usable. The implementation uses conservative noise values so the filter remains stable when GPS is noisy or subject to water multipath.

The final tuned values in the code are:

- $\alpha = 0.30$
- $\beta = 2.0$
- $\kappa = 0.0$
- $Q_{pos} = 0.018$
- $Q_{vel} = 0.026$
- $R_{gps,good} = 1.2$
- $R_{gps,usable} = 4.0$
- $R_{gps,poor} = 14.0$

These values are intentionally conservative for watch-class marine use.

## FIT field model

The app writes custom FIT developer fields at regular intervals. The main ones are:

- DR East / North
- Depth
- Speed estimate
- Heading
- Underwater state
- Motion / moving state
- GPS fix state
- synthetic DR latitude / longitude
- POI markers

The device keeps the number of created developer record fields low enough to stay within the practical field limit of Instinct-class devices while still logging enough information for post-analysis.

## Nitrogen model

The app includes a simple nitrogen-loading estimator used for UI and FIT logging, not for medical or decompression decisions. It calculates a current loading percentage and a risk band (low, moderate, elevated, high), based on depth, time underwater, and ascent behavior.

The model is intentionally simple and should be treated as a convenience indicator, not as a certified dive-planning algorithm.

## Recommended usage notes

1. Treat pressure as the primary source of depth.
2. Validate live sensor data before trusting it.
3. Keep the baseline active rather than waiting for a delayed calibration step.
4. Use DR only as a tracking aid when GPS is weak or absent.
5. Use the FIT output for analysis and review, not as a substitute for certified dive instrumentation.

## Verification status

The project builds successfully with the Garmin Connect IQ toolchain available in this environment. Verified command:

```bash
monkeyc -y /home/panagiotis/Documents/gsensors/gsensros/developer_key \
  -o /tmp/gsensros_test.prg -d instinct2x -f monkey.jungle
```

Observed result:

```text
BUILD SUCCESSFUL
```

This confirms the current implementation compiles correctly with the real SDK installed in the workspace.

## Final note

This is the authoritative implementation state of the project: pressure-first depth, corrected runtime sensor registration, conservative local UKF tuning, and practical FIT logging for underwater data analysis.
