# Version Changes - 2026-08-21

## Release summary
This update fixes the core depth mismatch against the Suunto Ocean reference and aligns the app’s documented depth model with the actual observed dive trace.

## What changed

### 1. Pressure-first depth baseline was corrected
- The app now initializes `surfacePressurePa` from the first valid pressure sample instead of waiting for the full calibration window.
- Live pressure-based depth updates remain active during startup calibration when the pressure signal is valid.
- Negative pressure differences are clipped to zero so false negative depths are not reported.

### 2. Altitude is now secondary, not primary
- The altitude estimate is still used when valid, but it no longer dominates the underwater trace.
- Pressure is treated as the authoritative depth signal for real dive depth estimation.

### 3. Low-pass smoothing was tuned
- The filtering response was adjusted to track actual dive motion more quickly while still suppressing transient spikes.
- This keeps the trace responsive without the flat-zero startup artifact.

### 4. The earlier drift bug was clearly isolated
- The Garmin export previously flattened to zero because the app’s startup calibration logic was discarding real pressure values too early.
- The corrected implementation is consistent with Suunto Ocean data and the realistic shallow-depth trace seen in the reference logs.

## Comparison to Suunto reference

The Suunto Ocean log contains realistic depth values around:

- 1.56 m
- 3.96 m
- 4.47 m
- 5.91 m

The fixed implementation now follows that style of trace instead of stalling at 0 m while the calibration gate is waiting to complete.

## Impact

- Depth values are now much closer to the real dive trace.
- The app is less likely to report flat zero-depth behavior during initial calibration.
- The documented algorithm better reflects what the watch is actually doing in the field.

## Relevant notes

This update supersedes the earlier altitude-heavy explanation in the older release notes. The current app behavior is pressure-first and tuned to a realistic dive profile rather than a starter calibration artifact.
