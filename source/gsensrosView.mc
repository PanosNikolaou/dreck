import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.Sensor;
import Toybox.Timer;
import Toybox.Lang;
import Toybox.System;
import Toybox.ActivityRecording;
import Toybox.Position;
import Toybox.Activity;

class gsensrosView extends WatchUi.View {

    var accelX = 0, accelY = 0, accelZ = 0;
    var gyroX = 0.0f, gyroY = 0.0f, gyroZ = 0.0f;
    
    var latitude = 0.0;
    var longitude = 0.0;
    var speed = 0.0;

    var session = null;
    var isRecording = false;

    var updateTimer = null;

    function initialize() {
        View.initialize();
    }

    function onLayout(dc as Dc) as Void {
        try { setLayout(Rez.Layouts.MainLayout(dc)); } catch (e) {}
    }

    function onShow() as Void {
        System.println("=== App Started - Timer Mode ===");
        updateTimer = new Timer.Timer();
        updateTimer.start(method(:timerCallback), 250, true);
    }

    function onHide() as Void {
        System.println("=== Cleanup on exit ===");
        if (isRecording) {
            stopRecording();
        }
        if (updateTimer != null) {
            updateTimer.stop();
        }
    }

    function timerCallback() as Void {
        try {
            var info = Sensor.getInfo();
            if (info has :accel && info.accel != null) {
                accelX = info.accel[0]; accelY = info.accel[1]; accelZ = info.accel[2];
            }
            updateGPS();
        } catch (e) {}
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
        System.println("=== SELECT BUTTON ===");
        try {
            if (isRecording) {
                stopRecording();
            } else {
                startRecording();
            }
        } catch (e) {
            System.println("Button crash prevented: " + e.getErrorMessage());
            isRecording = false;
            session = null;
        }
        return true;
    }

    function onBack() as Boolean {
        if (isRecording) {
            stopRecording();
        }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }

    function startRecording() as Void {
        System.println("Attempting start recording...");
        try {
            if (session != null) {
                session = null;
            }

            session = ActivityRecording.createSession({
                :name => "SensorLog",
                :sport => Activity.SPORT_GENERIC,
                :subSport => Activity.SUB_SPORT_GENERIC
            });

            if (session != null) {
                session.start();
                isRecording = true;
                System.println("SUCCESS: Recording STARTED");
            } else {
                System.println("createSession returned null");
            }
        } catch (e) {
            System.println("CRITICAL START ERROR: " + e.getErrorMessage());
            isRecording = false;
            session = null;
        }
        WatchUi.requestUpdate();
    }

    function stopRecording() as Void {
        System.println("Attempting stop recording...");
        if (session != null) {
            try {
                session.stop();
                session.save();
                System.println("SUCCESS: FIT SAVED!");
            } catch (e) {
                System.println("Save error: " + e.getErrorMessage());
            }
            session = null;
            isRecording = false;
        }
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        try {
            View.onUpdate(dc);

            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(dc.getWidth()/2, 8, Graphics.FONT_SMALL, "Sensor+GPS", Graphics.TEXT_JUSTIFY_CENTER);

            dc.setColor(isRecording ? Graphics.COLOR_GREEN : Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(dc.getWidth()/2, 35, Graphics.FONT_SMALL, isRecording ? "● RECORDING" : "Stopped", Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);

            dc.drawText(dc.getWidth()/2, 62, Graphics.FONT_XTINY, "A: " + accelX + " " + accelY + " " + accelZ, Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(dc.getWidth()/2, 79, Graphics.FONT_XTINY, "G: " + gyroX.format("%.1f") + " " + gyroY.format("%.1f") + " " + gyroZ.format("%.1f"), Graphics.TEXT_JUSTIFY_CENTER);

            dc.drawText(dc.getWidth()/2, 105, Graphics.FONT_XTINY, "Lat: " + latitude.format("%.4f"), Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(dc.getWidth()/2, 120, Graphics.FONT_XTINY, "Lon: " + longitude.format("%.4f"), Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(dc.getWidth()/2, 135, Graphics.FONT_XTINY, "Spd: " + (speed * 3.6).format("%.1f") + "km/h", Graphics.TEXT_JUSTIFY_CENTER);

            dc.drawText(dc.getWidth()/2, dc.getHeight() - 22, Graphics.FONT_XTINY, "Select: " + (isRecording ? "STOP" : "START"), Graphics.TEXT_JUSTIFY_CENTER);
        } catch (e) {
            System.println("Draw error: " + e.getErrorMessage());
        }
    }
}