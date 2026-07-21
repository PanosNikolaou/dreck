import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.Sensor;
import Toybox.Timer;
import Toybox.Lang;
import Toybox.System;
import Toybox.ActivityRecording;
import Toybox.Position;
import Toybox.Activity;
import Toybox.FitContributor;
import Toybox.Math;

class gsensrosView extends WatchUi.View {

    // Sensor snapshot values
    var accelX = 0;
    var accelY = 0;
    var accelZ = 0;

    var gyroX = 0.0f;
    var gyroY = 0.0f;
    var gyroZ = 0.0f;

    var magHeading = null;
    var trueHeading = null;

    // GPS / position
    var latitude = 0.0f;
    var longitude = 0.0f;
    var speed = 0.0f;

    var entryLat = 0.0f;
    var entryLon = 0.0f;
    var exitLat = 0.0f;
    var exitLon = 0.0f;

    // Recording
    var session = null;
    var isRecording = false;
    var isUnderwater = false;

    // Timing / DR
    var updateTimer = null;
    var dr = null;
    var lastUpdateMs = 0;

    // FIT fields
    var drEastField = null;
    var drNorthField = null;
    var depthField = null;
    var gpsLatField = null;
    var gpsLonField = null;

    // Depth handling
    var surfaceAltitudeSum = 0.0f;
    var surfaceAltitude = 0.0f;
    var depthFilter = 0.0f;
    var calibrationSamples = 0;
    const CALIBRATION_COUNT = 30;
    var currentDepth = 0.0f;

    // Thresholds
    const TIMER_PERIOD_MS = 500;
    const FALLBACK_SWIM_SPEED_MPS = 0.6f;
    const MIN_VALID_GPS_SPEED_MPS = 0.05f;
    const DIVE_START_DEPTH_M = 1.5f;
    const SURFACE_STOP_DEPTH_M = 0.5f;

    // Last FIT values
    var lastFitEast = null;
    var lastFitNorth = null;
    var lastFitDepth = null;

    var shallowSampleCount = 0;
    const SHALLOW_SAMPLES_TO_STOP = 5;

    function initialize() {
        View.initialize();

        try {
            dr = new DeadReckoning();
        } catch (e) {
            System.println("DeadReckoning init failed: " + errorToString(e));
        }
    }

    function onLayout(dc as Dc) as Void {
        try {
            setLayout(Rez.Layouts.MainLayout(dc));
        } catch (e) {
            System.println("Layout error: " + errorToString(e));
        }
    }

    function onShow() as Void {
        try {
            System.println("=== DR Tracker Started ===");
            resetDepthCalibration();
            lastUpdateMs = System.getTimer();

            if (updateTimer != null) {
                updateTimer.stop();
            }

            updateTimer = new Timer.Timer();
            updateTimer.start(method(:timerCallback), TIMER_PERIOD_MS, true);
        } catch (e) {
            System.println("onShow error: " + errorToString(e));
        }
    }

    function onHide() as Void {
        try {
            System.println("=== HIDING VIEW ===");
            stopTimerOnly();
        } catch (e) {
            System.println("onHide error: " + errorToString(e));
        }
    }

    function timerCallback() as Void {
        if (updateTimer == null) {
            return;
        }

        try {
            var nowMs = System.getTimer();
            var dt = (nowMs - lastUpdateMs).toFloat() / 1000.0f;
            lastUpdateMs = nowMs;

            if (dt <= 0.0f || dt > 2.0f) {
                WatchUi.requestUpdate();
                return;
            }

            readSensors();
            updateDepth();
            updateGPS();
            processDiveState();

            if (isRecording && dr != null) {
                var estSpeed = getEstimatedSpeedMps();
                var bestHeading = getBestHeading();
                dr.updateWithSpeed(accelX, accelY, accelZ, gyroZ, bestHeading, dt, estSpeed);
                writeFitFieldsIfNeeded();
            }
        } catch (e) {
            System.println("CRITICAL Timer Error: " + errorToString(e));
        }

        try {
            WatchUi.requestUpdate();
        } catch (e) {}
    }

    function readSensors() as Void {
        try {
            var info = Sensor.getInfo();
            if (info == null) { return; }

            if (info has :accel && info.accel != null && info.accel.size() >= 3) {
                accelX = info.accel[0];
                accelY = info.accel[1];
                accelZ = info.accel[2];
            }

            if (info has :gyro && info.gyro != null && info.gyro.size() >= 3) {
                gyroX = info.gyro[0].toFloat();
                gyroY = info.gyro[1].toFloat();
                gyroZ = info.gyro[2].toFloat();
            }

            trueHeading = null;
            if (info has :heading && info.heading != null) {
                trueHeading = info.heading.toFloat();
            }

            magHeading = null;
            if (info has :mag && info.mag != null && info.mag.size() >= 2) {
                magHeading = Math.atan2(info.mag[1].toFloat(), info.mag[0].toFloat());
            }
        } catch (e) {
            System.println("readSensors error: " + errorToString(e));
        }
    }

    function getBestHeading() as Float or Null {
        if (trueHeading != null) {
            return trueHeading;
        }

        if (magHeading != null) {
            return magHeading;
        }

        return null;
    }

    function updateDepth() as Void {
        try {
            var info = Sensor.getInfo();
            if (info == null || !(info has :altitude) || info.altitude == null) {
                return;
            }

            var rawAlt = info.altitude.toFloat();

            if (calibrationSamples < CALIBRATION_COUNT) {
                surfaceAltitudeSum += rawAlt;
                calibrationSamples += 1;

                if (calibrationSamples == CALIBRATION_COUNT) {
                    surfaceAltitude = surfaceAltitudeSum / CALIBRATION_COUNT.toFloat();
                    depthFilter = 0.0f;
                }

                currentDepth = 0.0f;
                return;
            }

            var rawDepth = surfaceAltitude - rawAlt;
            depthFilter = (depthFilter * 0.75f) + (rawDepth * 0.25f);

            if (depthFilter < 0.0f) {
                depthFilter = 0.0f;
            }

            currentDepth = depthFilter;
        } catch (e) {
            System.println("updateDepth error: " + errorToString(e));
        }
    }

    function updateGPS() as Void {
        try {
            var info = Sensor.getInfo();
            if (info != null && info has :speed && info.speed != null) {
                speed = info.speed.toFloat();
            } else {
                speed = 0.0f;
            }

            var loc = Position.getInfo();
            if (loc != null && loc.position != null) {
                var coords = loc.position.toDegrees();
                latitude = coords[0].toFloat();
                longitude = coords[1].toFloat();
            }
        } catch (e) {
            System.println("updateGPS error: " + errorToString(e));
        }
    }

    function processDiveState() as Void {
        try {
            if (!isRecording) {
                isUnderwater = false;
                shallowSampleCount = 0;
                return;
            }

            if (!isUnderwater && currentDepth > DIVE_START_DEPTH_M) {
                isUnderwater = true;
                shallowSampleCount = 0;
                return;
            }

            if (isUnderwater) {
                if (currentDepth <= SURFACE_STOP_DEPTH_M) {
                    shallowSampleCount += 1;

                    if (shallowSampleCount >= SHALLOW_SAMPLES_TO_STOP) {
                        shallowSampleCount = 0;
                        endDive();
                    }
                } else {
                    shallowSampleCount = 0;
                }
            }
        } catch (e) {
            System.println("processDiveState error: " + errorToString(e));
        }
    }

    function getEstimatedSpeedMps() as Float {
        try {
            if (speed > MIN_VALID_GPS_SPEED_MPS) {
                return speed;
            }

            if (currentDepth > 2.0f) {
                return FALLBACK_SWIM_SPEED_MPS;
            }

            return 0.0f;
        } catch (e) {
            return 0.0f;
        }
    }

    function onSelect() as Boolean {
        try {
            System.println("=== SELECT BUTTON PRESSED ===");

            if (isRecording) {
                endDive();
            } else {
                startDive();
            }
        } catch (e) {
            System.println("Select button error: " + errorToString(e));
        }

        return true;
    }

    function onBack() as Boolean {
        try {
            System.println("=== BACK BUTTON ===");

            if (isRecording) {
                endDive();
            }

            stopTimerOnly();
        } catch (e) {
            System.println("Back button error: " + errorToString(e));
        }

        return false;
    }

    function startDive() as Void {
        try {
            if (isRecording) { return; }

            System.println("MANUAL START");
            captureEntryPosition();
            startRecording();

            isUnderwater = (currentDepth > DIVE_START_DEPTH_M);
            shallowSampleCount = 0;

            if (dr != null) {
                var initialHeading = getBestHeading();
                if (initialHeading != null) {
                    dr.resetWithHeading(initialHeading);
                } else {
                    dr.reset();
                }
            }

            lastUpdateMs = System.getTimer();
            WatchUi.requestUpdate();
        } catch (e) {
            System.println("startDive error: " + errorToString(e));
        }
    }

    function endDive() as Void {
        try {
            if (!isRecording) {
                isUnderwater = false;
                shallowSampleCount = 0;
                return;
            }

            System.println("MANUAL STOP - Saving FIT");
            captureExitPosition();
            isUnderwater = false;
            shallowSampleCount = 0;
            shutdownSessionSafe();
            resetDepthCalibration();
            WatchUi.requestUpdate();
        } catch (e) {
            System.println("endDive error: " + errorToString(e));
        }
    }

    function captureEntryPosition() as Void {
        try {
            var loc = Position.getInfo();
            if (loc != null && loc.position != null) {
                var coords = loc.position.toDegrees();
                entryLat = coords[0].toFloat();
                entryLon = coords[1].toFloat();
            }
        } catch (e) {
            System.println("captureEntryPosition error: " + errorToString(e));
        }
    }

    function captureExitPosition() as Void {
        try {
            var loc = Position.getInfo();
            if (loc != null && loc.position != null) {
                var coords = loc.position.toDegrees();
                exitLat = coords[0].toFloat();
                exitLon = coords[1].toFloat();
            }
        } catch (e) {
            System.println("captureExitPosition error: " + errorToString(e));
        }
    }

    function startRecording() as Void {
        try {
            shutdownSessionWithoutSave();

            session = ActivityRecording.createSession({
                :name => "DR_Track",
                :sport => Activity.SPORT_GENERIC
            });

            if (session == null) {
                System.println("createSession returned null");
                return;
            }

            drEastField = session.createField("DR_East_m", 101, FitContributor.DATA_TYPE_FLOAT, {
                :mesgType => FitContributor.MESG_TYPE_RECORD,
                :units => "m"
            });

            drNorthField = session.createField("DR_North_m", 102, FitContributor.DATA_TYPE_FLOAT, {
                :mesgType => FitContributor.MESG_TYPE_RECORD,
                :units => "m"
            });

            depthField = session.createField("Depth_m", 103, FitContributor.DATA_TYPE_FLOAT, {
                :mesgType => FitContributor.MESG_TYPE_RECORD,
                :units => "m"
            });

            gpsLatField = session.createField("GPS_Lat", 104, FitContributor.DATA_TYPE_FLOAT, {
                :mesgType => FitContributor.MESG_TYPE_RECORD,
                :units => "deg"
            });

            gpsLonField = session.createField("GPS_Lon", 105, FitContributor.DATA_TYPE_FLOAT, {
                :mesgType => FitContributor.MESG_TYPE_RECORD,
                :units => "deg"
            });

            var started = session.start();
            if (started) {
                isRecording = true;
                lastFitEast = null;
                lastFitNorth = null;
                lastFitDepth = null;
                System.println("Recording STARTED with GPS");
            } else {
                clearFitFields();
                session = null;
                isRecording = false;
            }
        } catch (e) {
            System.println("Start recording error: " + errorToString(e));
            clearFitFields();
            session = null;
            isRecording = false;
        }
    }

    function shutdownSessionSafe() as Void {
        if (session == null) {
            isRecording = false;
            clearFitFields();
            return;
        }

        try {
            if (session.isRecording()) {
                session.stop();
            }

            session.save();
            System.println("FIT FILE SAVED SUCCESSFULLY!");
        } catch (e) {
            System.println("session save error: " + errorToString(e));
        }

        forceCleanup();
    }

    function shutdownSessionWithoutSave() as Void {
        if (session == null) {
            isRecording = false;
            clearFitFields();
            return;
        }

        try {
            if (session.isRecording()) {
                session.stop();
            }
        } catch (e) {}

        forceCleanup();
    }

    function stopTimerOnly() as Void {
        if (updateTimer != null) {
            try {
                updateTimer.stop();
            } catch (e) {}
            updateTimer = null;
        }
    }

    function forceCleanup() as Void {
        session = null;
        isRecording = false;
        drEastField = null;
        drNorthField = null;
        depthField = null;
        gpsLatField = null;
        gpsLonField = null;
        lastFitEast = null;
        lastFitNorth = null;
        lastFitDepth = null;
        isUnderwater = false;
    }

    function clearFitFields() as Void {
        drEastField = null;
        drNorthField = null;
        depthField = null;
        gpsLatField = null;
        gpsLonField = null;
        lastFitEast = null;
        lastFitNorth = null;
        lastFitDepth = null;
    }

    function resetDepthCalibration() as Void {
        try {
            surfaceAltitudeSum = 0.0f;
            surfaceAltitude = 0.0f;
            depthFilter = 0.0f;
            calibrationSamples = 0;
            currentDepth = 0.0f;
        } catch (e) {
            System.println("resetDepthCalibration error: " + errorToString(e));
        }
    }

    function writeFitFieldsIfNeeded() as Void {
        try {
            if (!isRecording || session == null || dr == null) {
                return;
            }

            var drData = dr.getDRData();
            var eastVal = drData[:east];
            var northVal = drData[:north];
            var depthVal = currentDepth;

            if (drEastField != null && (lastFitEast == null || !floatEquals(lastFitEast, eastVal, 0.01f))) {
                drEastField.setData(eastVal);
                lastFitEast = eastVal;
            }

            if (drNorthField != null && (lastFitNorth == null || !floatEquals(lastFitNorth, northVal, 0.01f))) {
                drNorthField.setData(northVal);
                lastFitNorth = northVal;
            }

            if (depthField != null && (lastFitDepth == null || !floatEquals(lastFitDepth, depthVal, 0.01f))) {
                depthField.setData(depthVal);
                lastFitDepth = depthVal;
            }

            if (gpsLatField != null && latitude != 0.0f) {
                gpsLatField.setData(latitude);
            }

            if (gpsLonField != null && longitude != 0.0f) {
                gpsLonField.setData(longitude);
            }
        } catch (e) {
            System.println("FIT write error: " + errorToString(e));
        }
    }

    function floatEquals(a as Float, b as Float, eps as Float) as Boolean {
        try {
            var diff = a - b;
            if (diff < 0.0f) { diff = -diff; }
            return diff <= eps;
        } catch (e) {
            return false;
        }
    }

    function errorToString(e) as String {
        try {
            return e.getErrorMessage();
        } catch (ex) {
            return "unknown error";
        }
    }

    function onUpdate(dc as Dc) as Void {
        try {
            View.onUpdate(dc);

            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(dc.getWidth() / 2, 8, Graphics.FONT_SMALL, "DR Tracker", Graphics.TEXT_JUSTIFY_CENTER);

            dc.setColor(isRecording ? Graphics.COLOR_GREEN : Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(dc.getWidth() / 2, 35, Graphics.FONT_SMALL, isRecording ? "RECORDING" : "Stopped", Graphics.TEXT_JUSTIFY_CENTER);

            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(dc.getWidth() / 2, 55, Graphics.FONT_XTINY, "Depth: " + currentDepth.format("%.1f") + "m", Graphics.TEXT_JUSTIFY_CENTER);

            if (dr != null) {
                var drData = dr.getDRData();
                dc.drawText(dc.getWidth() / 2, 73, Graphics.FONT_XTINY, "DR E: " + drData[:east].format("%.1f") + "m", Graphics.TEXT_JUSTIFY_CENTER);
                dc.drawText(dc.getWidth() / 2, 88, Graphics.FONT_XTINY, "DR N: " + drData[:north].format("%.1f") + "m", Graphics.TEXT_JUSTIFY_CENTER);
                dc.drawText(dc.getWidth() / 2, 103, Graphics.FONT_XTINY, "Dist: " + drData[:distance].format("%.0f") + "m", Graphics.TEXT_JUSTIFY_CENTER);
                dc.drawText(dc.getWidth() / 2, 118, Graphics.FONT_XTINY, "Hdg: " + drData[:headingDeg].format("%.0f") + "°", Graphics.TEXT_JUSTIFY_CENTER);
                dc.drawText(dc.getWidth() / 2, 133, Graphics.FONT_XTINY, "Spd: " + drData[:speed].format("%.2f") + "m/s", Graphics.TEXT_JUSTIFY_CENTER);
            }

            dc.drawText(dc.getWidth() / 2, dc.getHeight() - 25, Graphics.FONT_XTINY, "Select: Start / Stop", Graphics.TEXT_JUSTIFY_CENTER);
        } catch (e) {
            System.println("Draw error: " + errorToString(e));
        }
    }
}