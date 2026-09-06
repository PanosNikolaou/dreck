# Version Changes - 2026-08-21

## Release Summary

This revision consolidates the last implementation wave: depth-source correction, motion-state hardening, simulator fallback for depth-path validation, and documentation alignment.

## Code Changes

### 1. Depth Source Resolution Reworked

- `updateDepth(info, posInfo)` now resolves sources in explicit priority order:
	- direct depth (`depth`, `enhancedDepth`)
	- pressure (`pressure`, `ambientPressure`)
	- altitude (`altitude`, `enhancedAltitude`, GPS altitude)
	- simulator synthetic fallback (`SIM`) when no real source is available
- Pressure unit normalization is now robust for Pa/hPa/kPa-like inputs.
- Altitude-only mode uses sign-robust handling to avoid baseline polarity mistakes.

### 2. Depth Stuck-at-Zero Failure Path Fixed

- Real-device depth now starts from first valid pressure baseline and is no longer blocked by startup sequencing.
- Clamping and filtering behavior was retained but applied after stronger source validation.
- Runtime diagnostics now make source and intermediate computations observable.

### 3. Motion Confidence Updated with KF Fallback

- `isStationary`, `isProbablyMoving`, and `updateMotionConfidence` now include Kalman displacement-derived speed fallback.
- This avoids false stationary lock in simulator sessions where IMU payload is sparse but DR/KF displacement exists.

### 4. Simulator Validation Path Added

- When simulator has no pressure and flat altitude, runtime can emit synthetic depth (`SIM`) during recording.
- This is an explicit simulator-only continuity mechanism to validate UI/FIT plumbing; it is not a replacement for real pressure depth.

### 5. Diagnostics and UI Visibility

- `DEPTHDBG` logs include source tag and intermediate values (altitude baseline, normalized pressure, pressure depth, altitude depth, final depth).
- `Dsrc` was surfaced on-screen to verify active source in real time.
- Debug logging defaults were made safer for investigation when settings are absent.

## Validation Outcomes

- Build verification succeeded repeatedly via `./run_simulation.sh --build-only`.
- Python simulation suite passed (`tests/test_simulation_suite.py`: 6 tests).
- Logs confirmed simulator constraints (`pPa=NA`, flat altitude) and subsequent non-zero depth under `SIM` source.

## Documentation Synchronization

The following docs were updated to match implementation:

- `README.md`
- `docs/overview.md`
- `docs/architecture.md`
- `docs/data-flow.md`
- `docs/DOCUMENTATION.md`
- `docs/fit-fields-and-formulas.md`
- `developerguide.md`
- `docs/command-reference.md`
- this file (`docs/version-changes-2026-08-14.md`)

## Operational Notes

- Prefer `./run_simulation.sh` for build/run because it tracks current SDK layout and avoids stale hardcoded SDK paths.
- Simulator evidence should be interpreted as pipeline validation; depth truth evaluation must come from real-device sensor streams.
