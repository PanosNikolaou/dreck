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
import Toybox.Time;

class gsensrosView extends WatchUi.View {

    var accelX = 0, accelY = 0, accelZ = 0;
    var gyroX = 0.0f, gyroY = 0.0f, gyroZ = 0.0f;
    var magHeading = 0.0f;

    var latitude = 0.0;
    var longitude = 0.0;
    var speed = 0.0;

    var entryLat = 0.0;
    var entryLon = 0.0;
    var exitLat = 0.0;
    var exitLon = 0.0;

    var session = null;
    var isRecording = false;
    var isUnderwater = false;

    var updateTimer = null;
    var dr = null;

    var drEastField = null;
    var drNorthField = null;
    var depthField = null;

    // Depth handling
    var surfaceAltitude = 0.0;
    var depthFilter = 0.0;
    var calibrationSamples = 0;
    const CALIBRATION_COUNT = 30;
    var currentDepth = 0.0;

    function initialize() {
        View.initialize();
        try {
            dr = new DeadReckoning();
        } catch (e) {
            System.println("DeadReckoning init failed: " + e.getErrorMessage());
        }
    }

    function onLayout(dc as Dc) as Void {
        try { 
            setLayout(Rez.Layouts.MainLayout(dc)); 
        } catch (e) {
            System.println("Layout error: " + e.getErrorMessage());
        }
    }

    function onShow() as Void {
        try {
            System.println("=== Auto Dive DR App Started ===");
            surfaceAltitude = 0.0;
            calibrationSamples = 0;
            depthFilter = 0.0;
            
            updateTimer = new Timer.Timer();
            updateTimer.start(method(:timerCallback), 500, true);
        } catch (e) {
            System.println("onShow error: " + e.getErrorMessage());
        }
    }

    function timerCallback() as Void {
        try {
            var info = Sensor.getInfo();
            
            if (info has :accel && info.accel != null && info.accel.size() >= 3) {
                accelX = info.accel[0];
                accelY = info.accel[1];
                accelZ = info.accel[2];
            }
            
            if (info has :gyro && info.gyro != null && info.gyro.size() >= 3) {
                gyroX = info.gyro[0];
                gyroY = info.gyro[1];
                gyroZ = info.gyro[2];
            }
            
            if (info has :mag && info.mag != null && info.mag.size() >= 2) {
                magHeading = Math.atan2(info.mag[1].toFloat(), info.mag[0].toFloat());
            }

            // Depth with calibration
            if (info has :altitude && info.altitude != null) {
                var rawAlt = info.altitude;
                if (calibrationSamples < CALIBRATION_COUNT) {
                    surfaceAltitude += rawAlt;
                    calibrationSamples++;
                    if (calibrationSamples == CALIBRATION_COUNT) {
                        surfaceAltitude /= CALIBRATION_COUNT;
                    }
                    currentDepth = 0.0;
                } else {
                    var rawDepth = surfaceAltitude - rawAlt;
                    depthFilter = depthFilter * 0.75 + rawDepth * 0.25;
                    currentDepth = depthFilter > 0 ? depthFilter : 0.0;
                }
            }

            updateGPS();

            // Auto dive detection
            if (!isRecording && currentDepth > 3.0 && calibrationSamples >= CALIBRATION_COUNT) {
                startDive();
            } else if (isRecording && currentDepth < 1.0) {
                endDive();
            }

            if (isUnderwater && isRecording && dr != null) {
                var now = Time.now().value();
                var dt = (now - dr.prevTime).toFloat();
                dr.prevTime = now;
                if (dt > 0 && dt < 2) {
                    dr.update(accelX, accelY, accelZ, gyroZ, magHeading, dt);
                }
            }

        } catch (e) {
            System.println("CRITICAL Timer Error: " + e.getErrorMessage());
        }
        WatchUi.requestUpdate();
    }

    function updateGPS() as Void {
        try {
            var loc = Position.getInfo();
            if (loc != null && loc.position != null) {
                var coords = loc.position.toDegrees();
                latitude = coords[0];
                longitude = coords[1];
                speed = loc.speed != null ? loc.speed : 0.0;
            }
        } catch (e) {}
    }

    function onSelect() as Boolean {
        try {
            System.println("=== SELECT BUTTON PRESSED ===");
            if (isRecording) {
                System.println("→ Stopping dive (manual)");
                endDive();
            } else {
                System.println("→ Starting dive (manual)");
                startDive();
            }
        } catch (e) {
            System.println("Select button error: " + e.getErrorMessage());
        }
        return true;
    }

    function onBack() as Boolean {
        System.println("=== BACK BUTTON - Starting safe exit ===");
        
        try {
            if (isRecording) {
                System.println("Stopping recording before exit");
                stopRecording();   // Use direct stop instead of endDive()
            }
            
            // Direct pop without delay
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            
        } catch (e) {
            System.println("Back button crash prevented: " + e.getErrorMessage());
            // Last resort
            try {
                stopRecording();
            } catch (ex) {}
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        }
        return true;
    }

    function startDive() as Void {
        try {
            System.println("AUTO DIVE START DETECTED");
            startRecording();
            
            var loc = Position.getInfo();
            if (loc != null && loc.position != null) {
                var coords = loc.position.toDegrees();
                entryLat = coords[0];
                entryLon = coords[1];
            }
            
            isUnderwater = true;
            if (dr != null) { dr.reset(); }
            WatchUi.requestUpdate();
        } catch (e) {
            System.println("startDive error: " + e.getErrorMessage());
        }
    }

    function endDive() as Void {
        try {
            System.println("AUTO SURFACE DETECTED - Saving FIT");
            var loc = Position.getInfo();
            if (loc != null && loc.position != null) {
                var coords = loc.position.toDegrees();
                exitLat = coords[0];
                exitLon = coords[1];
            }
            
            isUnderwater = false;
            stopRecording();
            
            surfaceAltitude = 0.0;
            calibrationSamples = 0;
            depthFilter = 0.0;
            WatchUi.requestUpdate();
        } catch (e) {
            System.println("endDive error: " + e.getErrorMessage());
        }
    }

    function startRecording() as Void {
        try {
            if (session != null) { session = null; }

            session = ActivityRecording.createSession({
                :name => "Auto_Dive_DR",
                :sport => Activity.SPORT_SWIMMING,
                :subSport => Activity.SUB_SPORT_OPEN_WATER
            });

            if (session != null) {
                drEastField = session.createField("DR_East_m", 101, FitContributor.DATA_TYPE_FLOAT, {:mesgType => FitContributor.MESG_TYPE_RECORD});
                drNorthField = session.createField("DR_North_m", 102, FitContributor.DATA_TYPE_FLOAT, {:mesgType => FitContributor.MESG_TYPE_RECORD});
                depthField = session.createField("Depth_m", 103, FitContributor.DATA_TYPE_FLOAT, {:mesgType => FitContributor.MESG_TYPE_RECORD});

                session.start();
                isRecording = true;
                System.println("Recording STARTED");
            }
        } catch (e) {
            System.println("Start recording error: " + e.getErrorMessage());
        }
    }

    function stopRecording() as Void {
        if (session != null) {
            try {
                session.stop();
                session.save();
                System.println("FIT FILE SAVED SUCCESSFULLY!");
            } catch (e) {
                System.println("Save error: " + e.getErrorMessage());
            }
            session = null;
            isRecording = false;
            drEastField = null;
            drNorthField = null;
            depthField = null;
        }
    }

    function onHide() as Void {
        try {
            if (isRecording) { endDive(); }
            if (updateTimer != null) { updateTimer.stop(); }
        } catch (e) {
            System.println("onHide error: " + e.getErrorMessage());
        }
    }

    function onUpdate(dc as Dc) as Void {
        try {
            View.onUpdate(dc);

            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(dc.getWidth()/2, 8, Graphics.FONT_SMALL, "Auto Dive DR", Graphics.TEXT_JUSTIFY_CENTER);

            dc.setColor(isRecording ? Graphics.COLOR_GREEN : Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(dc.getWidth()/2, 35, Graphics.FONT_SMALL, isRecording ? "● DIVING" : "Surface", Graphics.TEXT_JUSTIFY_CENTER);
            
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(dc.getWidth()/2, 55, Graphics.FONT_XTINY, "Depth: " + currentDepth.format("%.1f") + "m", Graphics.TEXT_JUSTIFY_CENTER);

            if (dr != null) {
                var drData = dr.getDRData();
                dc.drawText(dc.getWidth()/2, 73, Graphics.FONT_XTINY, "DR E: " + drData[:east].format("%.1f") + "m", Graphics.TEXT_JUSTIFY_CENTER);
                dc.drawText(dc.getWidth()/2, 88, Graphics.FONT_XTINY, "DR N: " + drData[:north].format("%.1f") + "m", Graphics.TEXT_JUSTIFY_CENTER);
                dc.drawText(dc.getWidth()/2, 103, Graphics.FONT_XTINY, "Dist: " + drData[:distance].format("%.0f") + "m", Graphics.TEXT_JUSTIFY_CENTER);
                dc.drawText(dc.getWidth()/2, 118, Graphics.FONT_XTINY, "Hdg: " + drData[:headingDeg].format("%.0f") + "°", Graphics.TEXT_JUSTIFY_CENTER);
            }

            dc.drawText(dc.getWidth()/2, dc.getHeight() - 25, Graphics.FONT_XTINY, "Select: Manual Toggle", Graphics.TEXT_JUSTIFY_CENTER);

        } catch (e) {
            System.println("Draw error: " + e.getErrorMessage());
        }

        try {
            if (isRecording && session != null && drEastField != null && dr != null) {
                var drData = dr.getDRData();
                drEastField.setData(drData[:east]);
                drNorthField.setData(drData[:north]);
                depthField.setData(currentDepth);
            }
        } catch (e) {
            System.println("FIT write error: " + e.getErrorMessage());
        }
    }
}