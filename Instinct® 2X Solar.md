# Instinct® 2X Solar target notes

## Device summary

- Model: Garmin Instinct 2X Solar
- Device ID: instinct2x
- Display: 176 x 176 semi-octagon
- Colors: 2-color monochrome
- Touchscreen: no
- Buttons: Enter, Up, Menu, Down, Esc
- Memory target for watch app: 98 KB

## Why this device matters for the app

This device is a good fit for a custom Connect IQ dive tracker because it provides the core sensors needed for the app to function:

- 3-axis accelerometer
- 3-axis gyroscope
- 3-axis magnetometer
- barometric pressure / altitude
- GPS position

The app is designed to run as a practical watch app with conservative memory and CPU use. It does not depend on an unsupported native dive mode, and it remains compatible with the memory envelope available to a watch application on this platform.

## App constraints on this watch

The app intentionally keeps its logic compact:

- local East/North state only for DR
- small UKF state vector
- simple pressure-based depth processing
- conservative motion and GPS thresholds
- reduced FIT field count to stay within device limits

## Sensor and UI realities

This watch has a small monochrome field and a compact UI, so the app uses:

- minimal text and compact layout blocks
- a scrollable status view
- low-frequency FIT writes
- simple state transitions with hysteresis

This is enough to track a dive session, handle motion detection, and log a useful track without exceeding the watch’s practical limits.

## Final design note

The app is tuned to this hardware and to the real operating conditions that matter on a watch: noisy water GPS, imperfect heading estimates, and a limited battery and CPU budget. The platform is therefore treated as a practical custom dive tracker rather than a replacement for a certified dive computer.
