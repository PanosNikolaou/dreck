# Version Changes - 2026-08-14

## Release Summary
This update improves GPS-assisted dead reckoning, keeps the app functional without GPS, and makes POI marking behave as custom FIT markers rather than lap splits.

## What Changed

### 1. Dead reckoning became more adaptive
- Added a motion-state and GPS-uncertainty filter to the dead-reckoning path.
- Movement acceptance and deadband now react more smoothly during GPS loss and sensor jitter.
- The filter helps avoid abrupt jumps and overly aggressive movement acceptance.

### 2. GPS fallback now works continuously
- Dead reckoning remains active even when GPS is unavailable or temporarily unusable.
- The app now uses the DR-only path more reliably instead of waiting for a prior GPS-loss event.

### 3. GPS handling was made more responsive
- The GPS loss hold window was shortened.
- GPS correction updates now happen more frequently.
- GPS fixes are treated as usable unless they are explicitly marked as unavailable.
- Kalman filter tuning was strengthened so available GPS corrections have a stronger effect.

### 4. POI behavior was corrected
- POI marking no longer creates a FIT lap/split event.
- POIs are now recorded as custom record data points instead of new laps.

### 5. FIT output improvements
- Custom fields for DR position, depth, speed, heading, motion, GPS fix state, and POI markers remain part of the FIT record stream.
- The system now better reflects the active GPS/DR state in the recorded data.

### 6. Suggested next improvements
- Adaptive Heading Alpha: the complementary blend factor used by heading corrections could be weighted dynamically based on magnetometer reliability, inclination quality, or estimated magnetic interference rather than relying on a fixed blend.
- Vertical Integration: if the tracking use case benefits from it, the state vector could be extended from a 2D East-North plane to include altitude and vertical velocity to better compensate for terrain gradients and improve ground-track distance estimates.

## Impact
- Better continuous tracking when GPS signal is weak or interrupted.
- Less jitter and smoother route progression during GPS transitions.
- Cleaner POI data without unintended lap creation.
