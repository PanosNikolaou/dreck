# Version History

## v0.9.0 - 2026-08-14

### Summary
This release focuses on improving GPS-assisted dead reckoning reliability, keeping DR active without GPS, and making POI recording behave as custom FIT markers instead of lap splits.

### Changes
- Added a motion-state / GPS uncertainty filter to the dead-reckoning path so movement acceptance and deadband become less abrupt during GPS loss or sensor jitter.
- Enabled the DR-only fallback path so dead reckoning continues to advance when GPS is unavailable or temporarily unusable.
- Reduced the GPS-loss hold window and GPS correction interval so the system reuses available GPS fixes more quickly.
- Made GPS quality handling more permissive by accepting fixes that are not marked as "not available".
- Strengthened Kalman filter responsiveness to GPS updates by reducing measurement noise and increasing correction gain for usable and good-quality fixes.
- Removed the automatic lap creation from POI marking so POIs are stored as custom FIT record data rather than creating lap/split events.

### Notes
- The FIT output now records custom DR/POI fields in the record stream.
- The app still preserves a DR fallback path when GPS is absent, but it now reacts more decisively to available GPS fixes.
