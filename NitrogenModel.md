# NitrogenModel documentation

## Purpose

`NitrogenModel` is a lightweight nitrogen-loading estimator for a Garmin Connect IQ dive tracker. It is intentionally simple and designed for display and FIT logging, not decompression planning.

This is a risk model, not a decompression algorithm. It does not implement Bühlmann, VPM, or any other formal dive-planning method.

## Model behaviour

The model tracks a single loading value from 0 to 100 and updates it with each timer tick.

The current logic is:

- on-gassing increases when the diver is underwater and depth is above a shallow threshold
- deeper depth increases the loading rate
- a small descent bonus increases loading while descending
- off-gassing follows an exponential decay toward zero at the surface
- underwater off-gassing is slower than surface off-gassing
- fast ascent reduces off-gassing and raises residual loading risk

The implementation is intentionally conservative and easy to compute on a watch.

## Constants used in the model

- `SURFACE_HALF_LIFE_MIN = 120.0f`
  - approximate half-life at the surface
- `DEPTH_RESPONSE_M = 10.0f`
  - depth at which the model reaches full uptake rate
- `MAX_LOADING = 100.0f`
  - cap on the loading value
- `DESCENT_BONUS = 1.15f`
  - extra loading on descent
- `FAST_ASCENT_FACTOR = 0.70f`
  - reduces off-gassing on fast ascent

## Public API

### `reset()`
Resets the model to a clean state.

### `update(depthM, dtSec, isUnderwater, ascentRateMps)`
Updates the loading estimate with the current depth and timing information.

Parameters:

- `depthM`: current depth in metres
- `dtSec`: time delta in seconds
- `isUnderwater`: whether the app currently treats the diver as underwater
- `ascentRateMps`: vertical speed in m/s; positive means ascending

### `getLoading()`
Returns the current loading percentage.

### `getMaxLoading()`
Returns the highest loading value seen since the last reset.

### `getRiskBand()`
Returns a discrete risk band:

- 0: low
- 1: moderate
- 2: elevated
- 3: high

## Risk-band mapping

The implementation uses a simple threshold model:

- `loading < 25`: low
- `loading < 50`: moderate
- `loading < 75`: elevated
- otherwise: high

## Practical use in this app

The model is used for:

- UI warning / risk indication
- FIT logging of loading and max loading
- summary risk classification during a session

It is not used for ascent guidance, decompression calculations, or any dive-planning decision.

## Limitations

This model is intentionally limited:

- one-compartment approximation only
- no real Bühlmann tissue model
- no multi-tissue or bubble model
- no surface-interval credit beyond exponential decay
- no formal decompression planning support

## Important safety note

This model is suitable for logging and display only. It must never be used as a substitute for proper decompression planning, certified dive software, or a dive computer’s actual decompression algorithm.
