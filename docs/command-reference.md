# Garmin Connect IQ Command Reference

This document contains the exact commands used to validate, build, and run the gsensros app in this environment.

## 1. Prerequisites

The project expects the Garmin Connect IQ SDK and a valid developer key.

```bash
ls -ld /home/panagiotis/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-9.1.0-2026-03-09-6a872a80b
ls -l /home/panagiotis/Documents/gsensors/gsensros/developer_key
```

Expected result:
- SDK directory exists
- developer key file exists and is readable

## 2. Verify the SDK and simulator binary

```bash
file /home/panagiotis/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-9.1.0-2026-03-09-6a872a80b/bin/simulator
ls -l /home/panagiotis/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-9.1.0-2026-03-09-6a872a80b/bin/simulator
ldd /home/panagiotis/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-9.1.0-2026-03-09-6a872a80b/bin/simulator 2>/dev/null | head -50
```

Check the compiler and runner commands:

```bash
/home/panagiotis/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-9.1.0-2026-03-09-6a872a80b/bin/monkeyc --help 2>&1 | head -n 40
/home/panagiotis/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-9.1.0-2026-03-09-6a872a80b/bin/monkeydo --help 2>&1 | head -n 60
```

## 3. Build the app with the developer key

From the project root:

```bash
cd /home/panagiotis/Documents/gsensors/gsensros
/home/panagiotis/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-9.1.0-2026-03-09-6a872a80b/bin/monkeyc \
  -y /home/panagiotis/Documents/gsensors/gsensros/developer_key \
  -o /tmp/gsensros_test.prg \
  -d instinct2x \
  -f monkey.jungle
```

This is the exact verified build command that produced:

```text
BUILD SUCCESSFUL
```

## 4. Validate the generated package

```bash
ls -l /tmp/gsensros_test.prg
file /tmp/gsensros_test.prg
```

Optional check of the project build outputs:

```bash
ls -l /home/panagiotis/Documents/gsensors/gsensros/bin /home/panagiotis/Documents/gsensors/gsensros/build 2>/dev/null | sed -n '1,200p'
```

## 5. Start the Connect IQ simulator

This environment is headless, so the simulator must be launched via Xvfb for compatibility.

```bash
which xvfb-run || command -v xvfb-run || echo 'NO_XVFB'
echo "DISPLAY=$DISPLAY"
```

Launch the simulator:

```bash
cd /home/panagiotis/Documents/gsensors/gsensros
xvfb-run -a /home/panagiotis/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-9.1.0-2026-03-09-6a872a80b/bin/simulator
```

Important note:
- The simulator is a GUI application and needs a display.
- In a real desktop environment, this command opens the Garmin simulator window.
- In a headless or CI environment, the simulator may not remain usable for interactive validation.

## 6. Push and run the app in the simulator

Once the simulator is already running, use:

```bash
/home/panagiotis/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-9.1.0-2026-03-09-6a872a80b/bin/monkeydo \
  /tmp/gsensros_test.prg \
  instinct2x
```

If you want to run in native pairing mode:

```bash
/home/panagiotis/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-9.1.0-2026-03-09-6a872a80b/bin/monkeydo \
  /tmp/gsensros_test.prg \
  instinct2x \
  -n
```

## 7. Useful diagnostic commands

Check whether the simulator process is still alive:

```bash
ps -ef | grep -E 'xvfb|simulator|connectiq' | grep -v grep | sed -n '1,80p'
ls -l /tmp/.X11-unix 2>/dev/null | sed -n '1,40p'
```

Capture logs when needed:

```bash
cd /home/panagiotis/Documents/gsensors/gsensros
xvfb-run -a /home/panagiotis/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-9.1.0-2026-03-09-6a872a80b/bin/simulator >/tmp/ciq_sim.log 2>&1 &
cat /tmp/ciq_sim.log
```

## 8. Typical full validation flow

```bash
cd /home/panagiotis/Documents/gsensors/gsensros

/home/panagiotis/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-9.1.0-2026-03-09-6a872a80b/bin/monkeyc \
  -y /home/panagiotis/Documents/gsensors/gsensros/developer_key \
  -o /tmp/gsensros_test.prg \
  -d instinct2x \
  -f monkey.jungle

ls -l /tmp/gsensros_test.prg
file /tmp/gsensros_test.prg

xvfb-run -a /home/panagiotis/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-9.1.0-2026-03-09-6a872a80b/bin/simulator

/home/panagiotis/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-9.1.0-2026-03-09-6a872a80b/bin/monkeydo \
  /tmp/gsensros_test.prg \
  instinct2x
```

## 9. Environment note

The exact commands above were validated in this workspace. The build itself succeeded; the interactive simulator run is limited by the headless environment and requires a real desktop GUI session for full watch-side runtime verification.
