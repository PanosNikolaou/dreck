# Simulation suite

This test suite is intentionally lightweight and runs in plain Python so it can validate the logic behind the Garmin app without requiring the watch simulator on every iteration.

## What it tests

- shallow-depth dive entry and exit thresholds
- underwater hysteresis logic
- NaN/Inf sanitization for DR values
- basic dead-reckoning movement integration
- presence of sample FIT artifacts for offline analysis work

## Run it

From the project root:

```bash
python3 -m unittest discover -s tests -p 'test_simulation_suite.py'
```

or, if you want the script form:

```bash
python3 tests/test_simulation_suite.py
```

## Files

- `simulations/gsensros_sim.py` — pure-Python simulation logic mirroring the key app decisions.
- `tests/test_simulation_suite.py` — regression tests for the critical logic paths.
