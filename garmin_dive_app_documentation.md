# Garmin Connect IQ Dive App Documentation

## Overview

This project is a custom Garmin Connect IQ dive/tracking app built around `gsensrosView`, delegates, and dead-reckoning helpers. It is designed to log a dive session, estimate depth, and record custom FIT fields for post-analysis.

The app is not a native Garmin dive computer mode. It runs as a surface activity with custom underwater logic and custom fields, which is the practical workaround available on Garmin devices under Connect IQ.

## Current architecture

The application has four main responsibilities:

- UI lifecycle handling through `WatchUi.View`
- sensor and GPS polling through `Sensor.getInfo()` and `Position.getInfo()`
- estimation and state tracking for motion, heading, speed, depth, and dive state
- FIT recording through `ActivityRecording` and custom contributor fields

## What changed in the depth logic

The current implementation corrects the earlier bug in the depth pipeline.

Previously, the app waited too long before trusting a valid pressure baseline, which caused real shallow depth to be treated as zero until the startup calibration window was done. The current fix does this instead:

- uses the first valid pressure sample as the active surface baseline,
- allows live depth updates during startup calibration when the pressure estimate is valid,
- treats altitude as a secondary signal rather than the primary source,
- clamps impossible values and smooths the result with a responsive low-pass filter.

This change was verified against the Suunto Ocean reference log: the reference contains realistic low-depth samples such as 1.56 m, 3.96 m, 4.47 m, and 5.91 m, whereas the earlier Garmin export flattened to zero.

## Depth estimation behavior

The corrected depth logic is built around an ambient-pressure model:

$$
depth \approx \frac{pressurePa - surfacePressurePa}{PA\_PER\_METER\_SEAWATER}
$$

If altitude is valid, it can add a secondary estimate:

$$
altitudeDepth = surfaceAltitude - rawAlt
$$

The app then blends the two when both are present, with pressure taking priority. This reduces noise from GPS or barometric drift while still preserving a realistic dive trace.

## Dive state behavior

The app uses a shallow-water threshold plus hysteresis and minimum-duration logic to avoid instant start-stop churn at the surface. It tracks a dive as underwater only after the depth and confidence conditions are met, and it requires a return to a shallow state before closure.

## Dead reckoning and motion model

The app estimates heading and speed using the strongest signal available, then advances DR position with the best signal combination it can trust. This remains a practical wearable model rather than a native dive-computer algorithm, but it is far more stable than treating every raw acceleration sample as a ground-truth displacement source.

## FIT output model

The app records custom FIT fields for:

- DR east / north
- depth
- speed estimate
- heading
- underwater state
- motion / moving state
- GPS fix state
- POI markers

This makes the recorded session usable for analysis outside the watch, even though the session still appears as a normal swimming/open-water activity from Garmin’s platform perspective.

## Recommended design principles

1. Pressure first for depth
2. Validate before trusting sensor values
3. Keep a live baseline instead of waiting for a delayed calibration to complete
4. Use hysteresis around dive-state changes
5. Treat the app as a custom logging tool, not as a native dive-mode replacement

## Final note

This project is now aligned with the actual pressure/reference behavior seen in the Suunto Ocean data. The app is no longer designed around an altitude-only approximation that collapses to zero depth; it is built around a pressure-calibrated dive trace that better matches the reference logs.
