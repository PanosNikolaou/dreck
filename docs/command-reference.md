# Garmin Connect IQ Command Reference

This command reference reflects the current workflow and SDK auto-detection used in this repository.

## 1. Preferred Entry Point

Use the wrapper script from project root:

```bash
cd /home/panagiotis/Documents/gsensors/gsensros
./run_simulation.sh --build-only
./run_simulation.sh --run-only
```

## 2. SDK Auto-Detection

The wrapper script auto-selects the newest installed Connect IQ SDK under:

```bash
~/.Garmin/ConnectIQ/Sdks
```

Quick check:

```bash
ls -1 ~/.Garmin/ConnectIQ/Sdks | sort -V
```

Recent validated SDK in this workspace was 9.2.0 (not the older hardcoded 9.1 path).

## 3. Developer Key Validation

```bash
cd /home/panagiotis/Documents/gsensors/gsensros
ls -l developer_key
```

If key is missing, Monkey C signing/build steps will fail.

## 4. Build Commands (Direct)

If you need direct commands (without wrapper), first resolve SDK path:

```bash
SDK="$(ls -d ~/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-* | sort -V | tail -n1)"
echo "$SDK"
```

Then compile:

```bash
"$SDK/bin/monkeyc" \
  -y /home/panagiotis/Documents/gsensors/gsensros/developer_key \
  -o /tmp/gsensros_test.prg \
  -d instinct2x \
  -f /home/panagiotis/Documents/gsensors/gsensros/monkey.jungle
```

## 5. Run Commands (Direct)

Start simulator:

```bash
"$SDK/bin/simulator"
```

Push app:

```bash
"$SDK/bin/monkeydo" /tmp/gsensros_test.prg instinct2x
```

Headless environments may require `xvfb-run -a`.

## 6. Validation Helpers

Build artifact checks:

```bash
ls -l /tmp/gsensros_test.prg
file /tmp/gsensros_test.prg
```

Project outputs:

```bash
ls -l /home/panagiotis/Documents/gsensors/gsensros/bin
ls -l /home/panagiotis/Documents/gsensors/gsensros/build
```

Python simulation tests:

```bash
cd /home/panagiotis/Documents/gsensors/gsensros
python -m unittest tests/test_simulation_suite.py
```

## 7. Troubleshooting Notes

Common issues:

- `monkeydo` cannot connect: simulator not running or startup race
- headless simulator closes: missing display or unsupported GUI environment
- depth remains zero in simulator: simulator may not provide pressure and can keep altitude flat; current runtime has `SIM` fallback for pipeline validation

Useful quick checks:

```bash
ps -ef | grep -E 'simulator|monkeydo' | grep -v grep
echo "$DISPLAY"
```
