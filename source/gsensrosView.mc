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

    var accelX = 0.0f;
    var accelY = 0.0f;
    var accelZ = 0.0f;

    var gyroX = 0.0f;
    var gyroY = 0.0f;
    var gyroZ = 0.0f;

    var magHeading = null;
    var trueHeading = null;

    var headingEstimate = 0.0f;
    var hasHeadingEstimate = false;

    var latitude = 0.0f;
    var longitude = 0.0f;
    var speed = 0.0f;
    var hasGpsFix = false;
    var gpsQuality = -1;
    var gpsActive = false;

    var entryLat = 0.0f;
    var entryLon = 0.0f;
    var exitLat = 0.0f;
    var exitLon = 0.0f;

    var session = null;
    var isRecording = false;
    var isUnderwater = false;

    var updateTimer = null;
    var dr = null;
    var lastUpdateMs = 0;
    var fitWriteTick = 0;

    var movingConfidence = 0;
    const MOVING_CONFIDENCE_ON = 3;
    const MOVING_CONFIDENCE_MAX = 10;
    const STATIONARY_GYRO_Z_RAD_S = 0.03f;
    const STATIONARY_MOTION_MG = 18.0f;

    var calibrationActive = false;
    var calibrationStartMs = 0;
    const CALIBRATION_DURATION_MS = 5000;

    var gyroBiasX = 0.0f;
    var gyroBiasY = 0.0f;
    var gyroBiasZ = 0.0f;
    var gyroCalSamples = 0;

    var magBiasX = 0.0f;
    var magBiasY = 0.0f;
    var magBiasZ = 0.0f;
    var magCalSamples = 0;

    const FIELD_DR_EAST = 101;
    const FIELD_DR_NORTH = 102;
    const FIELD_DEPTH = 103;
    const FIELD_GPS_LAT = 104;
    const FIELD_GPS_LON = 105;
    const FIELD_MOTION = 106;
    const FIELD_SPEED_EST = 107;
    const FIELD_UNDERWATER = 108;
    const FIELD_GPS_FIX = 109;
    const FIELD_HEADING = 110;
    const FIELD_MOVING = 111;

    var drEastField = null;
    var drNorthField = null;
    var depthField = null;
    var gpsLatField = null;
    var gpsLonField = null;
    var motionField = null;
    var speedEstField = null;
    var underwaterField = null;
    var gpsFixField = null;
    var headingField = null;
    var movingField = null;

    var surfaceAltitudeSum = 0.0f;
    var surfaceAltitude = 0.0f;
    var depthFilter = 0.0f;
    var calibrationSamples = 0;
    const CALIBRATION_COUNT = 15;
    var currentDepth = 0.0f;

    var motionScoreMg = 0.0f;
    var isMotionDetected = false;
    var sensorListenerActive = false;

    const TIMER_PERIOD_MS = 500;
    const SENSOR_PERIOD_SEC = 1;
    const SENSOR_SAMPLE_RATE_HZ = 10;

    const GPS_ZERO_SPEED_MPS = 0.20f;
    const MIN_VALID_GPS_SPEED_MPS = 0.35f;
    const DR_MOVE_SPEED_THRESHOLD_MPS = 0.05f;

    const FALLBACK_SWIM_SPEED_MPS_HIGH = 0.45f;
    const FALLBACK_SWIM_SPEED_MPS_MED = 0.30f;

    const LAND_SPEED_LOW_MPS = 0.30f;
    const LAND_SPEED_MED_MPS = 0.65f;
    const LAND_SPEED_HIGH_MPS = 1.00f;

    const MOTION_ON_THRESHOLD_MG = 25.0f;
    const MOTION_OFF_THRESHOLD_MG = 12.0f;
    const MOTION_FILTER_ALPHA = 0.7f;

    const DIVE_START_DEPTH_M = 1.5f;
    const SURFACE_STOP_DEPTH_M = 0.5f;

    var lastFitEast = null;
    var lastFitNorth = null;
    var lastFitDepth = null;
    var lastFitMotion = null;
    var lastFitSpeedEst = null;
    var lastFitUnderwater = null;
    var lastFitGpsFix = null;
    var lastFitHeading = null;
    var lastFitMoving = null;

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
            resetMotionState();
            resetHeadingEstimate();
            movingConfidence = 0;
            fitWriteTick = 0;
            lastUpdateMs = System.getTimer();

            startMotionListener();
            startStartupCalibration();

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
            stopMotionListener();
            stopGps();
        } catch (e) {
            System.println("onHide error: " + errorToString(e));
        }
    }

    function startStartupCalibration() as Void {
        calibrationActive = true;
        calibrationStartMs = System.getTimer();
        gyroBiasX = 0.0f;
        gyroBiasY = 0.0f;
        gyroBiasZ = 0.0f;
        magBiasX = 0.0f;
        magBiasY = 0.0f;
        magBiasZ = 0.0f;
        gyroCalSamples = 0;
        magCalSamples = 0;
        resetHeadingEstimate();
    }

    function finishStartupCalibration() as Void {
        if (gyroCalSamples > 0) {
            gyroBiasX /= gyroCalSamples.toFloat();
            gyroBiasY /= gyroCalSamples.toFloat();
            gyroBiasZ /= gyroCalSamples.toFloat();
        }

        if (magCalSamples > 0) {
            magBiasX /= magCalSamples.toFloat();
            magBiasY /= magCalSamples.toFloat();
            magBiasZ /= magCalSamples.toFloat();
        }

        calibrationActive = false;
        System.println("Calibration complete");
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

            var sensorInfo = Sensor.getInfo();
            var posInfo = Position.getInfo();

            readSensors(sensorInfo);
            updateDepth(sensorInfo);
            updateGPS(sensorInfo, posInfo);
            processDiveState();
            updateMotionConfidence();

            if (calibrationActive && (nowMs - calibrationStartMs) >= CALIBRATION_DURATION_MS) {
                finishStartupCalibration();
            }

            if (isRecording && dr != null && !calibrationActive) {
                var estSpeed = getEstimatedSpeedMps();
                var bestHeading = getBestHeading(dt);

                if (isStationary()) {
                    estSpeed = 0.0f;
                }

                if (shouldAdvanceDR(bestHeading, estSpeed)) {
                    dr.updateWithSpeed(accelX, accelY, accelZ, gyroZ, bestHeading, dt, estSpeed);
                }

                fitWriteTick += 1;
                if (fitWriteTick >= 2) {
                    fitWriteTick = 0;
                    writeFitFieldsIfNeeded(estSpeed, bestHeading);
                }
            }
        } catch (e) {
            System.println("CRITICAL Timer Error: " + errorToString(e));
        }

        try {
            WatchUi.requestUpdate();
        } catch (e) {}
    }

    function startGps() as Void {
        if (gpsActive) {
            return;
        }

        try {
            Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
            gpsActive = true;
            System.println("GPS continuous enabled");
        } catch (e) {
            gpsActive = false;
            System.println("startGps error: " + errorToString(e));
        }
    }

    function stopGps() as Void {
        if (!gpsActive) {
            return;
        }

        try {
            Position.enableLocationEvents(Position.LOCATION_DISABLE, null);
        } catch (e) {}

        gpsActive = false;
        System.println("GPS disabled");
    }

    function getPositionQuality(info) {
        try {
            return info != null ? info.accuracy : null;
        } catch (e) {
            return null;
        }
    }

    function onPosition(info as Position.Info) as Void {
        try {
            if (info == null) {
                hasGpsFix = false;
                gpsQuality = -1;
                return;
            }

            gpsQuality = getPositionQuality(info);

            if (info.position != null && isGpsQualityUsable(gpsQuality)) {
                var coords = info.position.toDegrees();
                latitude = coords[0].toFloat();
                longitude = coords[1].toFloat();
                hasGpsFix = true;
            } else {
                hasGpsFix = false;
            }
        } catch (e) {
            System.println("onPosition error: " + errorToString(e));
        }
    }

    function startMotionListener() as Void {
        try {
            stopMotionListener();

            var sampleRate = SENSOR_SAMPLE_RATE_HZ;
            var maxRate = Sensor.getMaxSampleRate();
            if (maxRate != null && maxRate < sampleRate) {
                sampleRate = maxRate;
            }

            var options = {
                :period => SENSOR_PERIOD_SEC,
                :accelerometer => {
                    :enabled => true,
                    :sampleRate => sampleRate,
                    :includePower => true
                }
            };

            Sensor.registerSensorDataListener(method(:sensorDataCallback), options);
            sensorListenerActive = true;
        } catch (e) {
            sensorListenerActive = false;
            System.println("startMotionListener error: " + errorToString(e));
        }
    }

    function stopMotionListener() as Void {
        if (!sensorListenerActive) {
            return;
        }

        try {
            Sensor.unregisterSensorDataListener();
        } catch (e) {}

        sensorListenerActive = false;
    }

    function sensorDataCallback(sensorData as Sensor.SensorData) as Void {
        try {
            if (sensorData == null || !(sensorData has :accelerometerData) || sensorData.accelerometerData == null) {
                return;
            }

            var accData = sensorData.accelerometerData;
            if (!(accData has :power) || accData.power == null) {
                return;
            }

            var p = accData.power;
            var count = p.size();
            if (count <= 0) {
                return;
            }

            var sumPower = 0.0f;
            var validCount = 0;
            var i = 0;
            while (i < count) {
                if (p[i] != null) {
                    sumPower += p[i].toFloat();
                    validCount += 1;
                }
                i += 1;
            }

            if (validCount <= 0) {
                return;
            }

            var avgPower = sumPower / validCount.toFloat();
            motionScoreMg = (MOTION_FILTER_ALPHA * motionScoreMg) + ((1.0f - MOTION_FILTER_ALPHA) * avgPower);

            if (!isMotionDetected && motionScoreMg >= MOTION_ON_THRESHOLD_MG) {
                isMotionDetected = true;
            } else if (isMotionDetected && motionScoreMg <= MOTION_OFF_THRESHOLD_MG) {
                isMotionDetected = false;
            }
        } catch (e) {
            System.println("sensorDataCallback error: " + errorToString(e));
        }
    }

    function resetMotionState() as Void {
        motionScoreMg = 0.0f;
        isMotionDetected = false;
        movingConfidence = 0;
    }

    function resetHeadingEstimate() as Void {
        headingEstimate = 0.0f;
        hasHeadingEstimate = false;
    }

    function absf(v as Float) as Float {
        if (v < 0.0f) {
            return -v;
        }
        return v;
    }

    function isGpsQualityUsable(q) as Boolean {
        if (q == null) {
            return false;
        }
        return q == Position.QUALITY_USABLE || q == Position.QUALITY_GOOD;
    }

    function readSensors(info) as Void {
        try {
            if (info == null) {
                return;
            }

            if (info has :accel && info.accel != null && info.accel.size() >= 3) {
                accelX = info.accel[0].toFloat();
                accelY = info.accel[1].toFloat();
                accelZ = info.accel[2].toFloat();
            } else {
                accelX = 0.0f;
                accelY = 0.0f;
                accelZ = 0.0f;
            }

            if (info has :gyro && info.gyro != null && info.gyro.size() >= 3) {
                gyroX = info.gyro[0].toFloat();
                gyroY = info.gyro[1].toFloat();
                gyroZ = info.gyro[2].toFloat();

                if (calibrationActive) {
                    gyroBiasX += gyroX;
                    gyroBiasY += gyroY;
                    gyroBiasZ += gyroZ;
                    gyroCalSamples += 1;
                } else {
                    gyroX -= gyroBiasX;
                    gyroY -= gyroBiasY;
                    gyroZ -= gyroBiasZ;
                }
            } else {
                gyroX = 0.0f;
                gyroY = 0.0f;
                gyroZ = 0.0f;
            }

            trueHeading = null;
            magHeading = null;

            if (info has :heading && info.heading != null) {
                trueHeading = normalizeAngleRad(info.heading.toFloat());
                headingEstimate = trueHeading;
                hasHeadingEstimate = true;
            }

            if (info has :mag && info.mag != null && info.mag.size() >= 3) {
                var mx = info.mag[0].toFloat();
                var my = info.mag[1].toFloat();
                var mz = info.mag[2].toFloat();

                if (calibrationActive) {
                    magBiasX += mx;
                    magBiasY += my;
                    magBiasZ += mz;
                    magCalSamples += 1;
                } else if (trueHeading == null) {
                    mx -= magBiasX;
                    my -= magBiasY;
                    mz -= magBiasZ;
                    magHeading = normalizeAngleRad(Math.atan2(my, mx));
                }
            }
        } catch (e) {
            System.println("readSensors error: " + errorToString(e));
        }
    }

    function getBestHeading(dt as Float) as Float or Null {
        if (trueHeading != null) {
            return trueHeading;
        }

        if (magHeading != null) {
            headingEstimate = magHeading;
            hasHeadingEstimate = true;
            return headingEstimate;
        }

        if (hasHeadingEstimate) {
            if (!isStationary()) {
                headingEstimate = normalizeAngleRad(headingEstimate + (gyroZ * dt));
            }
            return headingEstimate;
        }

        if (dr != null && dr.hasValidHeading()) {
            return dr.getHeadingRad();
        }

        return null;
    }

    function normalizeAngleRad(a as Float) as Float {
        var twoPi = 6.2831853f;
        while (a < 0.0f) {
            a += twoPi;
        }
        while (a >= twoPi) {
            a -= twoPi;
        }
        return a;
    }

    function radToDeg(a as Float) as Float {
        return a * 57.2957795f;
    }

    function updateDepth(info) as Void {
        try {
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

    function updateGPS(sensorInfo, posInfo) as Void {
        try {
            hasGpsFix = false;
            speed = 0.0f;

            if (sensorInfo != null && sensorInfo has :speed && sensorInfo.speed != null) {
                var rawSpeed = sensorInfo.speed.toFloat();
                speed = rawSpeed < GPS_ZERO_SPEED_MPS ? 0.0f : rawSpeed;
            }

            if (posInfo != null) {
                gpsQuality = getPositionQuality(posInfo);

                if (posInfo.position != null && isGpsQualityUsable(gpsQuality)) {
                    var coords = posInfo.position.toDegrees();
                    latitude = coords[0].toFloat();
                    longitude = coords[1].toFloat();
                    hasGpsFix = true;
                }
            }

            if (!hasGpsFix) {
                latitude = 0.0f;
                longitude = 0.0f;
            }
        } catch (e) {
            System.println("updateGPS error: " + errorToString(e));
            speed = 0.0f;
            latitude = 0.0f;
            longitude = 0.0f;
            hasGpsFix = false;
            gpsQuality = -1;
        }
    }

    function processDiveState() as Void {
        try {
            if (!isRecording) {
                isUnderwater = false;
                return;
            }

            if (currentDepth > DIVE_START_DEPTH_M) {
                isUnderwater = true;
            } else if (currentDepth <= SURFACE_STOP_DEPTH_M) {
                isUnderwater = false;
            }
        } catch (e) {
            System.println("processDiveState error: " + errorToString(e));
        }
    }

    function isProbablyMoving() as Boolean {
        if (speed >= MIN_VALID_GPS_SPEED_MPS) {
            return true;
        }
        if (isUnderwater) {
            return motionScoreMg >= 28.0f;
        }
        if (motionScoreMg >= 35.0f) {
            return true;
        }
        return false;
    }

    function updateMotionConfidence() as Void {
        if (isProbablyMoving()) {
            if (movingConfidence < MOVING_CONFIDENCE_MAX) {
                movingConfidence += 1;
            }
        } else {
            if (movingConfidence > 0) {
                movingConfidence -= 1;
            }
        }
    }

    function isStationary() as Boolean {
        if (speed >= MIN_VALID_GPS_SPEED_MPS) {
            return false;
        }
        if (motionScoreMg > STATIONARY_MOTION_MG) {
            return false;
        }
        if (absf(gyroZ) > STATIONARY_GYRO_Z_RAD_S) {
            return false;
        }
        return true;
    }

    function getEstimatedSpeedMps() as Float {
        try {
            if (speed >= MIN_VALID_GPS_SPEED_MPS) {
                return speed;
            }

            if (movingConfidence < MOVING_CONFIDENCE_ON) {
                return 0.0f;
            }

            if (isUnderwater) {
                if (motionScoreMg >= 60.0f) {
                    return FALLBACK_SWIM_SPEED_MPS_HIGH;
                } else if (motionScoreMg >= 35.0f) {
                    return FALLBACK_SWIM_SPEED_MPS_MED;
                } else {
                    return 0.0f;
                }
            }

            if (motionScoreMg >= 70.0f) {
                return LAND_SPEED_HIGH_MPS;
            } else if (motionScoreMg >= 50.0f) {
                return LAND_SPEED_MED_MPS;
            } else if (motionScoreMg >= 35.0f) {
                return LAND_SPEED_LOW_MPS;
            }

            return 0.0f;
        } catch (e) {
            return 0.0f;
        }
    }

    function shouldAdvanceDR(bestHeading as Float or Null, estSpeed as Float) as Boolean {
        if (bestHeading == null) {
            return false;
        }
        if (estSpeed < DR_MOVE_SPEED_THRESHOLD_MPS) {
            return false;
        }
        if (movingConfidence < MOVING_CONFIDENCE_ON) {
            return false;
        }
        if (isStationary()) {
            return false;
        }
        return true;
    }

    function onSelect() as Boolean {
        try {
            System.println("=== SELECT BUTTON PRESSED ===");
            if (isRecording) {
                stopSession();
            } else {
                startSession();
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
                stopSession();
            }
            stopTimerOnly();
            stopMotionListener();
            stopGps();
        } catch (e) {
            System.println("Back button error: " + errorToString(e));
        }
        return false;
    }

    function startSession() as Void {
        try {
            if (isRecording) { return; }

            System.println("MANUAL START");
            startGps();
            captureEntryPosition();
            startRecording();

            if (!isRecording) {
                return;
            }

            isUnderwater = (currentDepth > DIVE_START_DEPTH_M);
            resetHeadingEstimate();
            movingConfidence = 0;
            fitWriteTick = 0;

            if (dr != null) {
                var initialHeading = getBestHeading(0.0f);
                if (initialHeading != null) {
                    dr.resetWithHeading(initialHeading);
                    headingEstimate = initialHeading;
                    hasHeadingEstimate = true;
                } else {
                    dr.reset();
                }
            }

            lastUpdateMs = System.getTimer();
            WatchUi.requestUpdate();
        } catch (e) {
            System.println("startSession error: " + errorToString(e));
        }
    }

    function stopSession() as Void {
        try {
            if (!isRecording) {
                isUnderwater = false;
                stopGps();
                return;
            }

            System.println("MANUAL STOP - Saving FIT");
            captureExitPosition();
            isUnderwater = false;
            shutdownSessionSafe();
            stopGps();
            resetDepthCalibration();
            resetMotionState();
            resetHeadingEstimate();
            WatchUi.requestUpdate();
        } catch (e) {
            System.println("stopSession error: " + errorToString(e));
        }
    }

    function captureEntryPosition() as Void {
        try {
            var loc = Position.getInfo();
            if (loc != null && loc.position != null && isGpsQualityUsable(getPositionQuality(loc))) {
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
            if (loc != null && loc.position != null && isGpsQualityUsable(getPositionQuality(loc))) {
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

            drEastField = session.createField("DR_East_m", FIELD_DR_EAST, FitContributor.DATA_TYPE_FLOAT, {
                :mesgType => FitContributor.MESG_TYPE_RECORD,
                :units => "m"
            });

            drNorthField = session.createField("DR_North_m", FIELD_DR_NORTH, FitContributor.DATA_TYPE_FLOAT, {
                :mesgType => FitContributor.MESG_TYPE_RECORD,
                :units => "m"
            });

            depthField = session.createField("Depth_m", FIELD_DEPTH, FitContributor.DATA_TYPE_FLOAT, {
                :mesgType => FitContributor.MESG_TYPE_RECORD,
                :units => "m"
            });

            gpsLatField = session.createField("GPS_Lat", FIELD_GPS_LAT, FitContributor.DATA_TYPE_FLOAT, {
                :mesgType => FitContributor.MESG_TYPE_RECORD,
                :units => "deg"
            });

            gpsLonField = session.createField("GPS_Lon", FIELD_GPS_LON, FitContributor.DATA_TYPE_FLOAT, {
                :mesgType => FitContributor.MESG_TYPE_RECORD,
                :units => "deg"
            });

            motionField = session.createField("Motion_mg", FIELD_MOTION, FitContributor.DATA_TYPE_FLOAT, {
                :mesgType => FitContributor.MESG_TYPE_RECORD,
                :units => "mg"
            });

            speedEstField = session.createField("Speed_Est", FIELD_SPEED_EST, FitContributor.DATA_TYPE_FLOAT, {
                :mesgType => FitContributor.MESG_TYPE_RECORD,
                :units => "m/s"
            });

            underwaterField = session.createField("Underwater", FIELD_UNDERWATER, FitContributor.DATA_TYPE_UINT32, {
                :mesgType => FitContributor.MESG_TYPE_RECORD,
                :units => "bool"
            });

            gpsFixField = session.createField("GPS_Fix", FIELD_GPS_FIX, FitContributor.DATA_TYPE_UINT32, {
                :mesgType => FitContributor.MESG_TYPE_RECORD,
                :units => "bool"
            });

            headingField = session.createField("Heading_deg", FIELD_HEADING, FitContributor.DATA_TYPE_FLOAT, {
                :mesgType => FitContributor.MESG_TYPE_RECORD,
                :units => "deg"
            });

            movingField = session.createField("Moving", FIELD_MOVING, FitContributor.DATA_TYPE_UINT32, {
                :mesgType => FitContributor.MESG_TYPE_RECORD,
                :units => "bool"
            });

            var started = session.start();
            if (started) {
                isRecording = true;
                clearLastFitValues();
                System.println("Recording STARTED");
            } else {
                System.println("session.start() returned false");
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
                System.println("session.stop() done");
            }

            var saved = session.save();
            System.println("session.save() returned: " + saved);
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
        clearFitFields();
        isUnderwater = false;
        hasGpsFix = false;
    }

    function clearLastFitValues() as Void {
        lastFitEast = null;
        lastFitNorth = null;
        lastFitDepth = null;
        lastFitMotion = null;
        lastFitSpeedEst = null;
        lastFitUnderwater = null;
        lastFitGpsFix = null;
        lastFitHeading = null;
        lastFitMoving = null;
    }

    function clearFitFields() as Void {
        drEastField = null;
        drNorthField = null;
        depthField = null;
        gpsLatField = null;
        gpsLonField = null;
        motionField = null;
        speedEstField = null;
        underwaterField = null;
        gpsFixField = null;
        headingField = null;
        movingField = null;
        clearLastFitValues();
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

    function isFiniteValue(v) as Boolean {
        if (v == null) {
            return false;
        }

        try {
            var s = v.format("%.6f");
            if (s == "nan" || s == "NaN" || s == "inf" || s == "-inf") {
                return false;
            }
        } catch (e) {
            return false;
        }

        return true;
    }

    function writeFloatField(field, value as Float, lastValue, eps as Float) {
        if (field == null || !isFiniteValue(value)) {
            return lastValue;
        }

        if (lastValue == null || !floatEquals(lastValue, value, eps)) {
            field.setData(value);
            return value;
        }

        return lastValue;
    }

    function writeUIntField(field, value as Number, lastValue) {
        if (field == null || value == null) {
            return lastValue;
        }

        if (lastValue == null || lastValue != value) {
            field.setData(value);
            return value;
        }

        return lastValue;
    }

    function writeFitFieldsIfNeeded(estSpeed as Float, bestHeading as Float or Null) as Void {
        try {
            if (!isRecording || session == null || dr == null) {
                return;
            }

            var drData = dr.getDRData();
            if (drData == null) {
                return;
            }

            var eastVal = drData[:east];
            var northVal = drData[:north];
            var depthVal = currentDepth;
            var motionVal = motionScoreMg;
            var speedVal = estSpeed;
            var underwaterVal = isUnderwater ? 1 : 0;
            var gpsFixVal = hasGpsFix ? 1 : 0;
            var movingVal = (movingConfidence >= MOVING_CONFIDENCE_ON && !isStationary()) ? 1 : 0;
            var headingDegVal = bestHeading != null ? radToDeg(bestHeading) : -1.0f;

            lastFitEast = writeFloatField(drEastField, eastVal, lastFitEast, 0.01f);
            lastFitNorth = writeFloatField(drNorthField, northVal, lastFitNorth, 0.01f);
            lastFitDepth = writeFloatField(depthField, depthVal, lastFitDepth, 0.01f);
            lastFitMotion = writeFloatField(motionField, motionVal, lastFitMotion, 0.1f);
            lastFitSpeedEst = writeFloatField(speedEstField, speedVal, lastFitSpeedEst, 0.01f);
            lastFitUnderwater = writeUIntField(underwaterField, underwaterVal, lastFitUnderwater);
            lastFitGpsFix = writeUIntField(gpsFixField, gpsFixVal, lastFitGpsFix);
            lastFitMoving = writeUIntField(movingField, movingVal, lastFitMoving);

            if (bestHeading != null) {
                lastFitHeading = writeFloatField(headingField, headingDegVal, lastFitHeading, 0.5f);
            }

            if (gpsLatField != null && hasGpsFix && isFiniteValue(latitude)) {
                gpsLatField.setData(latitude);
            }

            if (gpsLonField != null && hasGpsFix && isFiniteValue(longitude)) {
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

            var font = Graphics.FONT_XTINY;
            var w = dc.getWidth();
            var leftX = 8;
            var rightX = w / 2 + 4;
            var y = 8;
            var rowH = 14;

            dc.setColor(isRecording ? Graphics.COLOR_GREEN : Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, y, font, isRecording ? "RECORDING" : "Stopped", Graphics.TEXT_JUSTIFY_CENTER);

            y += rowH;

            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(leftX, y, font, "Mode:", Graphics.TEXT_JUSTIFY_LEFT);
            dc.drawText(rightX, y, font, isUnderwater ? "Underwater" : "Land/Surf", Graphics.TEXT_JUSTIFY_LEFT);

            y += rowH;
            dc.drawText(leftX, y, font, "GPS:", Graphics.TEXT_JUSTIFY_LEFT);
            dc.drawText(rightX, y, font, hasGpsFix ? "Yes" : "No", Graphics.TEXT_JUSTIFY_LEFT);

            y += rowH;
            dc.drawText(leftX, y, font, "Q:", Graphics.TEXT_JUSTIFY_LEFT);
            dc.drawText(rightX, y, font, "" + gpsQuality, Graphics.TEXT_JUSTIFY_LEFT);

            y += rowH;
            dc.drawText(leftX, y, font, "Moving:", Graphics.TEXT_JUSTIFY_LEFT);
            dc.drawText(rightX, y, font, ((movingConfidence >= MOVING_CONFIDENCE_ON && !isStationary()) ? "Yes" : "No"), Graphics.TEXT_JUSTIFY_LEFT);

            y += rowH;
            dc.drawText(leftX, y, font, "Depth:", Graphics.TEXT_JUSTIFY_LEFT);
            dc.drawText(rightX, y, font, currentDepth.format("%.1f") + "m", Graphics.TEXT_JUSTIFY_LEFT);

            y += rowH;
            dc.drawText(leftX, y, font, "Motion:", Graphics.TEXT_JUSTIFY_LEFT);
            dc.drawText(rightX, y, font, motionScoreMg.format("%.0f") + "mg", Graphics.TEXT_JUSTIFY_LEFT);

            y += rowH - 2;

            if (calibrationActive) {
                var elapsed = System.getTimer() - calibrationStartMs;
                var remain = CALIBRATION_DURATION_MS - elapsed;
                if (remain < 0) {
                    remain = 0;
                }
                dc.drawText(leftX, y, font, "Cal:", Graphics.TEXT_JUSTIFY_LEFT);
                dc.drawText(rightX, y, font, remain + "ms", Graphics.TEXT_JUSTIFY_LEFT);
                y += rowH;
            }

            if (dr != null) {
                var drData = dr.getDRData();

                dc.drawText(leftX, y, font, "DR E:", Graphics.TEXT_JUSTIFY_LEFT);
                dc.drawText(rightX, y, font, drData[:east].format("%.1f") + "m", Graphics.TEXT_JUSTIFY_LEFT);
                y += rowH;

                dc.drawText(leftX, y, font, "DR N:", Graphics.TEXT_JUSTIFY_LEFT);
                dc.drawText(rightX, y, font, drData[:north].format("%.1f") + "m", Graphics.TEXT_JUSTIFY_LEFT);
                y += rowH;

                dc.drawText(leftX, y, font, "Dist:", Graphics.TEXT_JUSTIFY_LEFT);
                dc.drawText(rightX, y, font, drData[:distance].format("%.0f") + "m", Graphics.TEXT_JUSTIFY_LEFT);
                y += rowH;

                dc.drawText(leftX, y, font, "Spd:", Graphics.TEXT_JUSTIFY_LEFT);
                dc.drawText(rightX, y, font, speed.format("%.2f") + "m/s", Graphics.TEXT_JUSTIFY_LEFT);
            }
        } catch (e) {
            System.println("Draw error: " + errorToString(e));
        }
    }
}