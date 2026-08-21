# gsensros

Garmin Connect IQ dive-tracking app for underwater motion estimation, GPS-assisted dead reckoning, depth tracking, and FIT logging.

## Overview

`gsensros` is a wearable app for Garmin devices that combines pressure-derived depth, motion detection, heading estimation, local dead reckoning, and FIT recording. It is designed to work as a custom watch app for underwater and GPS-denied tracking rather than as a native Garmin dive-computer mode.

The app is designed to:

- estimate current depth from pressure with a live baseline,
- preserve realistic shallow values instead of zeroing them during startup,
- detect underwater state using depth thresholds and hysteresis,
- use the best available heading and speed source,
- continue dead reckoning through GPS gaps,
- expose a FIT log with custom developer fields for analysis.

## Current implementation status

The final implementation is the authoritative state of the project.

The key fixes in the current codebase are:

- the first valid pressure sample becomes the live surface baseline immediately,
- shallow pressure values are preserved instead of being discarded,
- altitude is treated as a secondary validation signal, not the main depth source,
- gyro and magnetometer registration match the actual runtime callback path,
- the UKF uses conservative process and GPS noise values for water and multipath conditions,
- the app builds successfully with the real Garmin SDK in this environment.

## Core runtime model

The app follows a timer-driven processing loop with a few major subsystems:

### 1. Sensor and GPS layer
- accelerometer, gyroscope, and magnetometer sampling
- GPS speed and quality checks
- ambient pressure and altitude data

### 2. Estimation layer
- `updateDepth()`
- `processDiveState()`
- `getBestHeading()`
- `getEstimatedSpeedMps()`
- `updateMotionConfidence()`
- `DeadReckoning` / `KalmanDR` integration

### 3. Recording layer
- FIT field creation
- custom FIT writes on the active recording session
- dive summary and risk tracking

## Main processing flow

1. `onShow()` starts calibration, starts sensors, and launches the periodic timer.
2. `timerCallback()` runs every 500 ms and reads sensor and GPS state.
3. `readSensors()` and `updateDepth()` refresh the live motion and depth estimates.
4. `processDiveState()` classifies the user as underwater or at the surface.
5. `updateMotionConfidence()` updates the movement confidence signal.
6. DR and UKF values are advanced when the state is valid.
7. FIT values are written to the active recording session.
8. `onHide()` and `prepareToExit()` shut everything down cleanly.

## Important design notes

### Depth estimation
The current depth estimate is pressure-first:

- pressure is preferred as the primary depth source,
- altitude is used for secondary validation,
- negative pressure differences are clipped to zero,
- non-physical spikes are rejected before smoothing.

The core formulation is:

$$
depth \approx \frac{pressurePa - surfacePressurePa}{PA\_PER\_METER\_SEAWATER}
$$

with a low-pass filter applied after validation so the value follows real dive motion without reacting to transient noise.

### Motion and heading
The app chooses the strongest available source for heading and uses a conservative motion model to avoid false movement. Gyro and magnetometer inputs are both used, and the device only advances DR when the movement and heading state are valid.

### UKF and GPS fusion
The project uses a local East/North UKF to propagate position when GPS is weak or unavailable. The filter is tuned conservatively because water GPS and wrist-mounted motion both produce noisy data.

### FIT output
The app records custom FIT fields for DR position, depth, speed, motion, heading, GPS state, and underwater status. These values are used to reconstruct the dive context after the session is saved.

## Relevant files

- [source/gsensrosView.mc](source/gsensrosView.mc)
- [source/DeadReckoning.mc](source/DeadReckoning.mc)
- [source/KalmanDR.mc](source/KalmanDR.mc)
- [source/NitrogenModel.mc](source/NitrogenModel.mc)
- [manifest.xml](manifest.xml)
- [docs/](docs/)

## Verification status

The project was validated by building with the real Garmin Connect IQ SDK installed in this environment.

Verified command:

```bash
cd /home/panagiotis/Documents/gsensors/gsensros
/home/panagiotis/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-9.2.0-2026-06-09-92a1605b2/bin/monkeyc -y /home/panagiotis/Documents/gsensors/gsensros/developer_key -o /tmp/gsensros_test.prg -d instinct2x -f monkey.jungle
```

Observed result:

```text
BUILD SUCCESSFUL
```

This confirms the current code builds successfully with the actual installed toolchain.

## Runtime validation note

A full simulated dive run is limited by the available headless Linux environment. The watch simulator is available through the installed SDK, but without a desktop session or physical watch it is not practical to trigger a real dive session in this container. The build is therefore the verified proof in this environment; runtime device-side session validation remains the next stage on a GUI-enabled machine or actual watch.

## Final note

This project is now aligned with the actual implementation: pressure-first depth, corrected live sensor registration, conservative UKF tuning, and practical FIT logging for underwater analysis.

5. **Hysteresis**  
   Separate thresholds prevent noisy on/off switching.

6. **Confidence tracking**  
   Motion must persist before the app trusts it.

This is a practical design for wearable tracking because it handles noise and brief sensor spikes much better than a single threshold.

## FIT fields

The following custom FIT fields are created:

- `DR_East_m`
- `DR_North_m`
- `Depth_m`
- `GPS_Lat`
- `GPS_Lon`
- `Motion_mg`
- `Speed_Est`
- `Underwater`
- `GPS_Fix`
- `Heading_deg`
- `Moving`

These fields make it possible to analyze motion, tracking, and sensor behavior after the session ends.

## Data model

The app maintains three important internal states:

### Motion state
Represents whether the user is likely moving and how strong that confidence is.

### Tracking state
Represents current heading, depth, GPS quality, underwater state, and dead reckoning position.

### Recording state
Represents whether a FIT session is active and what data fields are available.

## Notes on performance

The app is designed to reduce unnecessary processing by:

- writing FIT fields only when values change enough,
- using motion confidence instead of raw motion spikes,
- smoothing sensor signals,
- keeping expensive processing in a timer loop rather than inside the UI render path.

## Known limitations

- Accelerometer power is still noisy and device-dependent.
- Heading can drift if true heading is unavailable.
- Altitude-based depth is approximate.
- Motion thresholds may need tuning per device.
- Dead reckoning quality depends heavily on correct motion detection.

## Suggested improvements

If you want to refine the app further, the best next steps are:

1. Split the motion logic into its own helper class.
2. Make thresholds configurable.
3. Add debug logs for raw motion and calibration data.
4. Separate timer processing into smaller functions.
5. Add device-specific tuning for motion and depth behavior.