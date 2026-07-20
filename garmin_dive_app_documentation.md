# Garmin Connect IQ Dive App Documentation

## Overview

This document describes the current architecture, known issues, root causes, and recommended fixes for the custom Garmin Connect IQ dive recording application built around `gsensrosView`, `gsensrosDelegate`, and `DeadReckoning`. The application records a custom swimming/open-water activity session, estimates depth from altitude sensor data, and stores custom FIT developer fields for dead-reckoning east, north, and depth values.[cite:1][cite:3][cite:9][cite:31]

The app is not a native Garmin dive activity. Garmin documents that Connect IQ features are not available while diving on supported Descent devices, which means a Connect IQ app cannot create or replace Garmin’s built-in dive mode behavior.[cite:47]

## Current architecture

The application has three main runtime responsibilities:

- UI rendering through a `WatchUi.View` implementation.[cite:61][cite:64]
- Input handling through a `BehaviorDelegate` implementation.[cite:66]
- Activity recording through `Toybox.ActivityRecording.Session` and FIT contributor fields.[cite:1][cite:3][cite:9]

Position is obtained through `Position.getInfo()`, which exposes position information and can provide coordinates through `position.toDegrees()`. Forum examples also confirm `Position.getInfo()` as a valid way to obtain GPS-related values such as speed in Connect IQ applications.[cite:31][cite:34][cite:35]

Sensor snapshots are obtained through `Sensor.getInfo()`, while Garmin separates snapshot-style sensor access from higher-rate sensor collection APIs. That distinction matters because timer-based polling is not ideal for dead reckoning or inertial tracking.[cite:19]

## Activity recording model

The app creates an activity session with `ActivityRecording.createSession()`, adds developer data fields via `session.createField()`, starts the session with `session.start()`, and later stops and saves it with `session.stop()` and `session.save()`.[cite:1][cite:3][cite:9]

Garmin’s FIT contributor field model stores data through `Field.setData()`. Garmin notes that the value is written at the next available recording opportunity, which means repeated overwrites can replace not-yet-written values if updates happen too aggressively.[cite:9]

Because the session is created as `SPORT_SWIMMING` with `SUB_SPORT_OPEN_WATER`, Garmin Connect will treat the result as a swimming/open-water activity rather than a native dive activity.[cite:3][cite:47]

## Why recording appears as a surface activity

The app records as a surface activity because Connect IQ does not create native dive activities in this setup, and the selected sport/subsport values identify the session as swimming/open water rather than diving.[cite:3][cite:47]

This is expected behavior, not a Garmin Connect display bug. Third-party Connect IQ dive-style apps commonly use pressure-based detection and custom state machines, but they still operate within normal Connect IQ activity constraints rather than native dive-computer modes.[cite:48][cite:49]

## Depth detection behavior

The current implementation estimates depth by calibrating a surface altitude baseline and then subtracting live altitude from that baseline. This is a heuristic built on altitude/barometric behavior, not a dedicated dive-depth API, so it is suitable only as an approximation.[cite:19][cite:49]

The current auto-start and auto-stop thresholds are vulnerable to false transitions near the surface. If depth briefly drops below the stop threshold immediately after a manual or automatic start, the app will end the dive and save the FIT file at once, which matches the observed logs showing `DIVE START` followed almost immediately by `SURFACE DETECTED - Saving FIT`.[cite:49]

A safer design is to add hysteresis and a minimum dive duration before allowing auto-stop. This avoids instant `start -> stop` loops caused by depth noise or shallow-water transitions.[cite:49]

## Dead reckoning limitations

The original `DeadReckoning` implementation attempted to integrate raw accelerometer values into velocity and position. Garmin documents accelerometer data in milli-g units, so converting them with an arbitrary scale factor and subtracting 9.81 directly mixes incompatible units.[cite:13]

Wrist IMU data is also in the device frame, not automatically in east/north world coordinates. Without proper orientation compensation and robust sensor fusion, double integration of acceleration will drift rapidly and produce unreliable underwater tracks.[cite:13][cite:19]

A more realistic model on Garmin hardware is to use filtered heading plus a speed estimate to advance east/north position, while keeping depth as a separate pressure/altitude-derived value. This reduces false precision and aligns better with the available sensor quality and API model.[cite:19][cite:31]

## Back button black-screen issue

The black GARMIN screen observed after pressing Back is most likely caused by handling the Back event in both the delegate/view chain and the navigation stack at the same time. Garmin’s behavior model indicates that returning `false` from `onBack()` allows the default back behavior to occur, which is to pop the top view, while returning `true` means the event was handled manually.[cite:62][cite:66][cite:68]

The earlier implementation forwarded `BehaviorDelegate.onBack()` to `view.onBack()`, and the view then called `WatchUi.popView()` directly. Garmin forum reports describe similar cases where manually popping the view inside back handling leads to blank screens or stuck transitions on some devices.[cite:57][cite:60][cite:68]

The recommended fix is:

- Perform cleanup in one place, preferably in the delegate.[cite:66]
- Do not call `WatchUi.popView()` inside the back path.[cite:62][cite:68]
- Return `false` from `BehaviorDelegate.onBack()` so Garmin performs the default pop itself.[cite:62][cite:68]
- Keep `onHide()` passive and idempotent, only stopping timers and sessions if they still exist.[cite:64]

## Recommended delegate pattern

A safer delegate implementation is shown below:

```monkeyc
import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.System;

class gsensrosDelegate extends WatchUi.BehaviorDelegate {

    var view as gsensrosView;

    function initialize(view as gsensrosView) {
        BehaviorDelegate.initialize();
        self.view = view;
    }

    function onSelect() as Boolean {
        return view.onSelect();
    }

    function onBack() as Boolean {
        System.println("Delegate: onBack called");

        try {
            view.prepareToExit();
        } catch (e) {
        }

        return false;
    }
}
```

This approach uses the delegate as the single Back-event owner and lets Garmin perform the actual navigation transition.[cite:62][cite:66][cite:68]

## Recommended view exit pattern

The view should expose a cleanup method and avoid manual navigation in the back path:

```monkeyc
function prepareToExit() as Void {
    try {
        if (updateTimer != null) {
            updateTimer.stop();
            updateTimer = null;
        }

        shutdownSession();
        isUnderwater = false;

    } catch (e) {
    }
}
```

Then `onHide()` should simply call the same cleanup method, making shutdown idempotent and reducing the chance of leaving the app in an inconsistent state during transitions.[cite:64][cite:3]

## Recommended dive-state logic

To avoid immediate stop after a manual or automatic start, add a minimum dive duration and shallow-sample hysteresis:

```monkeyc
var diveStartMs = 0;
var shallowSampleCount = 0;
const MIN_DIVE_DURATION_MS = 10000;
const SHALLOW_SAMPLES_TO_STOP = 5;

function startDive() as Void {
    diveStartMs = System.getTimer();
    shallowSampleCount = 0;
}

function processDiveState() as Void {
    if (!isRecording && calibrationSamples >= CALIBRATION_COUNT && currentDepth >= AUTO_START_DEPTH_M) {
        startDive();
        return;
    }

    if (isRecording) {
        var elapsed = System.getTimer() - diveStartMs;

        if (elapsed < MIN_DIVE_DURATION_MS) {
            return;
        }

        if (currentDepth <= 0.5f) {
            shallowSampleCount += 1;
            if (shallowSampleCount >= SHALLOW_SAMPLES_TO_STOP) {
                endDive();
                shallowSampleCount = 0;
            }
        } else {
            shallowSampleCount = 0;
        }
    }
}
```

This pattern is more robust for noisy near-surface depth estimates and aligns with the behavior described by existing dive-style Connect IQ apps that use pressure-based thresholds and state transitions such as Surface, Dive, and Suspect.[cite:49]

## Recommended dead-reckoning approach

The safer `DeadReckoning` replacement should avoid raw acceleration double integration and instead update position from heading plus speed estimate. `System.getTimer()` provides a millisecond timer suitable for elapsed time handling in Connect IQ.[cite:21][cite:22]

A simplified pattern is:

```monkeyc
var nowMs = System.getTimer();
var dt = (nowMs - prevMs).toFloat() / 1000.0f;
prevMs = nowMs;

heading = blendAngle(heading, magHeading, 0.15f);
var dx = speedMps * Math.cos(heading) * dt;
var dy = speedMps * Math.sin(heading) * dt;
```

This is less ambitious than full inertial navigation, but more realistic for a wrist-worn Garmin device and the available Connect IQ sensor model.[cite:13][cite:19][cite:21]

## Implementation checklist

| Area | Recommended action | Why it matters |
|---|---|---|
| Back handling | Move cleanup to delegate, return `false`, do not call `popView()` manually. [cite:62][cite:66][cite:68] | Prevents double-pop and black-screen transitions. |
| Session lifecycle | Use one shutdown path for `stop()` + `save()`. [cite:3] | Avoids duplicate stop/save state errors. |
| FIT writes | Write values from timer/sample path, not `onUpdate()`. [cite:9] | Prevents UI/render logic from interfering with recording. |
| Dive auto-stop | Add minimum dive duration and hysteresis. [cite:49] | Prevents instant start/stop loops at the surface. |
| Dead reckoning | Use heading + speed estimate, not acceleration double integration. [cite:13][cite:19] | Reduces severe drift and unit errors. |
| Sensor strategy | Prefer a sensor listener for serious IMU sampling. [cite:19] | Timer polling is too low-rate for meaningful inertial tracking. |
| Activity type | Expect swimming/open-water output, not native dive. [cite:3][cite:47] | This is a platform limitation, not a display bug. |

## Final notes

The current app can be turned into a more stable custom underwater logging tool, but it should be treated as an experimental training/logger application rather than a dive computer. Garmin’s own device guidance and Connect IQ limitations make that distinction especially important on dive-capable watches.[cite:47][cite:49]

The highest-priority fixes are the Back handling change, the anti-immediate-auto-stop guard, and the simplified dead-reckoning model. Those three changes address the main observed failures: black screen on exit, instant save at the surface, and unreliable position estimation.[cite:57][cite:62][cite:68][cite:13]
