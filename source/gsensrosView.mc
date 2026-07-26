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
import Toybox.Time.Gregorian;

class gsensrosView extends WatchUi.View {

    var accelX = 0.0f;
    var accelY = 0.0f;
    var accelZ = 0.0f;

    var gyroX = 0.0f;
    var gyroY = 0.0f;
    var gyroZ = 0.0f;

    var magHeading = null as Float or Null;
    var trueHeading = null as Float or Null;

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
    var hasEntryPosition = false;

    var session = null as ActivityRecording.Session or Null;
    var isRecording = false;
    var isUnderwater = false;

    var updateTimer = null as Timer.Timer or Null;
    var dr = null;
    var kalman = null;

    var lastUpdateMs = 0;
    var fitWriteTick = 0;

    var movingConfidence = 0;
    const MOVING_CONFIDENCE_ON = 3;
    const MOVING_CONFIDENCE_MAX = 10;

    const STATIONARY_GYRO_MAG_RAD_S = 0.05f;

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

    var n2Model = null;
    var n2LoadField = null as FitContributor.Field or Null;
    var n2MaxField = null as FitContributor.Field or Null;
    var n2BandField = null as FitContributor.Field or Null;

    var lastFitN2Load = null as Float or Null;
    var lastFitN2Max = null as Float or Null;
    var lastFitN2Band = null as Number or Null;

    var lastDepthForAscent = 0.0f;
    var currentAscentRateMps = 0.0f;

    var heartRate = 0;

    const SURFACE_RECAL_ALPHA   = 0.02f;
    const DEPTH_NOISE_FLOOR_M   = 0.4f;
    const DIVE_START_DEPTH_M    = 1.5f;
    const SURFACE_STOP_DEPTH_M  = 0.5f;

    // FIT field IDs
    const FIELD_DR_EAST    = 101;
    const FIELD_DR_NORTH   = 102;
    const FIELD_DEPTH      = 103;
    const FIELD_GPS_LAT    = 104;
    const FIELD_GPS_LON    = 105;
    const FIELD_MOTION     = 106;
    const FIELD_SPEED_EST  = 107;
    const FIELD_UNDERWATER = 108;
    const FIELD_GPS_FIX    = 109;
    const FIELD_HEADING    = 110;
    const FIELD_MOVING     = 111;
    const FIELD_DR_LAT     = 112;
    const FIELD_DR_LON     = 113;
    const FIELD_N2_LOAD    = 114;
    const FIELD_N2_MAX     = 115;
    const FIELD_N2_BAND    = 116;
    const FIELD_HR         = 117;
    const FIELD_ASCENT     = 118;

    var drLatField = null as FitContributor.Field or Null;
    var drLonField = null as FitContributor.Field or Null;
    var drEastField = null as FitContributor.Field or Null;
    var drNorthField = null as FitContributor.Field or Null;
    var depthField = null as FitContributor.Field or Null;
    var gpsLatField = null as FitContributor.Field or Null;
    var gpsLonField = null as FitContributor.Field or Null;
    var motionField = null as FitContributor.Field or Null;
    var speedEstField = null as FitContributor.Field or Null;
    var underwaterField = null as FitContributor.Field or Null;
    var gpsFixField = null as FitContributor.Field or Null;
    var headingField = null as FitContributor.Field or Null;
    var movingField = null as FitContributor.Field or Null;
    var hrField = null as FitContributor.Field or Null;
    var ascentField = null as FitContributor.Field or Null;

    var surfaceAltitudeSum = 0.0f;
    var surfaceAltitude = 0.0f;
    var depthFilter = 0.0f;
    var calibrationSamples = 0;
    const CALIBRATION_COUNT = 15;
    var currentDepth = 0.0f;

    var motionScoreMg = 0.0f;
    var motionBaselineMg = 15.0f; // Initialized to a sane floor
    var motionBaselineReady = false;
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

    const MOTION_FILTER_ALPHA = 0.5f; // Faster response time to reduce lag

    var lastFitEast = null as Float or Null;
    var lastFitNorth = null as Float or Null;
    var lastFitDepth = null as Float or Null;
    var lastFitMotion = null as Float or Null;
    var lastFitSpeedEst = null as Float or Null;
    var lastFitUnderwater = null as Number or Null;
    var lastFitGpsFix = null as Number or Null;
    var lastFitHeading = null as Float or Null;
    var lastFitMoving = null as Number or Null;
    var lastFitHr = null as Number or Null;
    var lastFitAscent = null as Float or Null;

    var scrollY = 0;
    const SCROLL_STEP = 20;
    const SCROLL_MIN = -180;
    const SCROLL_MAX = 0;

    // --- Improved Motion Engine Constants ---
    var lastAccelMag     = 0.0f;
    var motionVar        = 0.0f;
    var motionStateCount = 0;

    const MOTION_HP_ALPHA      = 0.20f;
    const MOTION_VAR_ALPHA     = 0.30f;
    const MIN_BASELINE_MG      = 12.0f; // Floor to stop baseline decaying to zero

    const MOTION_ON_MG  = 35.0f;
    const MOTION_OFF_MG = 15.0f;
    const CONF_RISE     = 2;
    const CONF_FALL     = 4;

// --- Rhythm & Frequency Detection ---
    var lastHpSample = 0.0f;
    var zeroCrossCount = 0;
    var sampleCountForPeriod = 0;
    var estimatedFrequencyHz = 0.0f;

    // --- Dynamic Speed Estimation Constants ---
    const MIN_MOTION_SWIM_MG = 20.0f;
    const MAX_MOTION_SWIM_MG = 120.0f;
    const MIN_SWIM_SPEED_MPS = 0.25f;
    const MAX_SWIM_SPEED_MPS = 0.70f;

    const MIN_MOTION_LAND_MG = 25.0f;
    const MAX_MOTION_LAND_MG = 200.0f;
    const MIN_LAND_SPEED_MPS = 0.35f;
    const MAX_LAND_SPEED_MPS = 1.40f;

    function initialize() {
        View.initialize();
        try {
            dr = new DeadReckoning();
            kalman = new KalmanDR();
            n2Model = new NitrogenModel();
        } catch (e) {
            System.println("Init failed: " + errorToString(e));
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
            heartRate = 0;
            currentAscentRateMps = 0.0f;

            startMotionListener();
            startStartupCalibration();

            if (n2Model != null) {
                n2Model.reset();
            }
            lastDepthForAscent = currentDepth;

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

            currentAscentRateMps = 0.0f;
            if (dt > 0.0f) {
                currentAscentRateMps = (lastDepthForAscent - currentDepth) / dt;
            }
            lastDepthForAscent = currentDepth;

            if (n2Model != null) {
                n2Model.update(currentDepth, dt, isUnderwater, currentAscentRateMps);
            }

            if (calibrationActive && (nowMs - calibrationStartMs) >= CALIBRATION_DURATION_MS) {
                finishStartupCalibration();
            }

            if (isRecording && !calibrationActive) {
                var estSpeed = getEstimatedSpeedMps();
                var bestHeading = getBestHeading(dt);

                if (isStationary()) {
                    estSpeed = 0.0f;
                }

                if (kalman != null) {
                    if (hasGpsFix && isGpsQualityUsable(gpsQuality)) {
                        kalman.updateGps(latitude, longitude, gpsQuality);
                    } else if (bestHeading != null) {
                        kalman.predict(estSpeed, bestHeading, dt);
                    }
                }

                if (dr != null && shouldAdvanceDR(bestHeading, estSpeed)) {
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

        WatchUi.requestUpdate();
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
        } catch (e) {
        }

        gpsActive = false;
        System.println("GPS disabled");
    }

    function getPositionQuality(info as Position.Info or Null) as Number or Null {
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
        } catch (e) {
        }

        sensorListenerActive = false;
    }

    // function updateMotionFromAccel(ax as Float, ay as Float, az as Float) as Void {
    //     // Convert mG -> G
    //     var gX = ax / 1000.0f;
    //     var gY = ay / 1000.0f;
    //     var gZ = az / 1000.0f;
        
    //     var mag = Math.sqrt(gX * gX + gY * gY + gZ * gZ);

    //     // High-pass filter
    //     var hp = mag - lastAccelMag;
    //     lastAccelMag = (1.0f - MOTION_HP_ALPHA) * lastAccelMag + MOTION_HP_ALPHA * mag;

    //     // Exponential variance
    //     motionVar = (1.0f - MOTION_VAR_ALPHA) * motionVar + MOTION_VAR_ALPHA * (hp * hp);
    // }

    function updateMotionState() as Void {
        var onTh  = isUnderwater ? 18.0f : MOTION_ON_MG;
        var offTh = isUnderwater ?  8.0f : MOTION_OFF_MG;

        if (motionScoreMg >= onTh) {
            if (motionStateCount < CONF_RISE) {
                motionStateCount += 1;
            }
            if (motionStateCount >= CONF_RISE) {
                isMotionDetected = true;
            }
        } else if (motionScoreMg <= offTh) {
            if (motionStateCount > -CONF_FALL) {
                motionStateCount -= 1;
            }
            if (motionStateCount <= -CONF_FALL) {
                isMotionDetected = false;
            }
        }
    }

function sensorDataCallback(sensorData as Sensor.SensorData) as Void {
        try {
            if (sensorData == null || !(sensorData has :accelerometerData) || sensorData.accelerometerData == null) {
                return;
            }

            var accData = sensorData.accelerometerData;

            if (accData has :x && accData.x != null && accData.x.size() > 0) {
                var count = accData.x.size();
                var i = 0;
                while (i < count) {
                    var ax = accData.x[i].toFloat();
                    var ay = (accData has :y && accData.y != null) ? accData.y[i].toFloat() : 0.0f;
                    var az = (accData has :z && accData.z != null) ? accData.z[i].toFloat() : 0.0f;

                    processAccelSample(ax, ay, az);
                    i += 1;
                }
            } else {
                return;
            }

            // Convert variance to RMS deviation in mG
            var accelRMS_mG = Math.sqrt(motionVar) * 1000.0f;
            var rawScore = accelRMS_mG;

            // Adaptive Baseline: track noise floor actively
            if (!motionBaselineReady) {
                motionBaselineMg = (rawScore > MIN_BASELINE_MG) ? rawScore : MIN_BASELINE_MG;
                motionBaselineReady = true;
            } else if (!isMotionDetected) {
                // Adapt baseline faster while resting to reject vessel/body noise
                motionBaselineMg = (0.90f * motionBaselineMg) + (0.10f * rawScore);
                if (motionBaselineMg < MIN_BASELINE_MG) {
                    motionBaselineMg = MIN_BASELINE_MG;
                }
            } else {
                // Adapt very slowly during active movement
                motionBaselineMg = (0.997f * motionBaselineMg) + (0.003f * rawScore);
            }

            var delta = rawScore - motionBaselineMg;
            if (delta < 0.0f) { delta = 0.0f; }

            // Smooth motion score
            motionScoreMg = (MOTION_FILTER_ALPHA * motionScoreMg) + ((1.0f - MOTION_FILTER_ALPHA) * delta);

            // Calculate dominant frequency over 1-second sample buffer
            if (sampleCountForPeriod > 0) {
                // Hz = (Half-cycles / 2) / (Samples / SampleRate)
                var durationSec = sampleCountForPeriod.toFloat() / SENSOR_SAMPLE_RATE_HZ.toFloat();
                if (durationSec > 0.0f) {
                    estimatedFrequencyHz = (zeroCrossCount.toFloat() / 2.0f) / durationSec;
                }
                zeroCrossCount = 0;
                sampleCountForPeriod = 0;
            }

            updateMotionState();

        } catch (e) {
            System.println("sensorDataCallback error: " + errorToString(e));
        }
    }

    function processAccelSample(ax as Float, ay as Float, az as Float) as Void {
        // Convert mG -> G
        var gX = ax / 1000.0f;
        var gY = ay / 1000.0f;
        var gZ = az / 1000.0f;

        var mag = Math.sqrt(gX * gX + gY * gY + gZ * gZ);

        // High-pass filter
        var hp = mag - lastAccelMag;
        lastAccelMag = (1.0f - MOTION_HP_ALPHA) * lastAccelMag + MOTION_HP_ALPHA * mag;

        // Rhythm / Zero-crossing detection (indicates kick/stride cycles)
        if ((hp > 0.002f && lastHpSample <= 0.002f) || (hp < -0.002f && lastHpSample >= -0.002f)) {
            zeroCrossCount += 1;
        }
        lastHpSample = hp;
        sampleCountForPeriod += 1;

        // Exponential variance
        motionVar = (1.0f - MOTION_VAR_ALPHA) * motionVar + MOTION_VAR_ALPHA * (hp * hp);
    }

function isStationary() as Boolean {
        if (speed >= MIN_VALID_GPS_SPEED_MPS) {
            return false;
        }

        // Check angular rate magnitude via Gyroscope to verify body stillness
        var gyroMag = Math.sqrt(gyroX * gyroX + gyroY * gyroY + gyroZ * gyroZ);
        if (gyroMag > STATIONARY_GYRO_MAG_RAD_S) {
            return false;
        }

        // Motion detected within realistic human cadence (0.3 Hz to 3.0 Hz)
        if (isMotionDetected && estimatedFrequencyHz >= 0.3f && estimatedFrequencyHz <= 3.0f) {
            return false;
        }

        return !isMotionDetected;
    }

    function getEstimatedSpeedMps() as Float {
        try {
            // Priority 1: Valid GPS speed
            if (speed >= MIN_VALID_GPS_SPEED_MPS) {
                return speed;
            }

            // Priority 2: Confidence Check
            if (movingConfidence < MOVING_CONFIDENCE_ON) {
                return 0.0f;
            }

            // Priority 3: Dynamic proportional speed based on motion intensity (mG)
            var targetSpeed = 0.0f;

            if (isUnderwater) {
                if (motionScoreMg <= MIN_MOTION_SWIM_MG) {
                    targetSpeed = MIN_SWIM_SPEED_MPS;
                } else if (motionScoreMg >= MAX_MOTION_SWIM_MG) {
                    targetSpeed = MAX_SWIM_SPEED_MPS;
                } else {
                    var norm = (motionScoreMg - MIN_MOTION_SWIM_MG) / (MAX_MOTION_SWIM_MG - MIN_MOTION_SWIM_MG);
                    targetSpeed = MIN_SWIM_SPEED_MPS + (norm * (MAX_SWIM_SPEED_MPS - MIN_SWIM_SPEED_MPS));
                }
            } else {
                if (motionScoreMg <= MIN_MOTION_LAND_MG) {
                    targetSpeed = MIN_LAND_SPEED_MPS;
                } else if (motionScoreMg >= MAX_MOTION_LAND_MG) {
                    targetSpeed = MAX_LAND_SPEED_MPS;
                } else {
                    var norm = (motionScoreMg - MIN_MOTION_LAND_MG) / (MAX_MOTION_LAND_MG - MIN_MOTION_LAND_MG);
                    targetSpeed = MIN_LAND_SPEED_MPS + (norm * (MAX_LAND_SPEED_MPS - MIN_LAND_SPEED_MPS));
                }
            }

            // Frequency Scaling: Scale speed up/down depending on stride or stroke tempo
            if (estimatedFrequencyHz > 0.3f) {
                if (estimatedFrequencyHz < 0.8f) {
                    targetSpeed *= 0.85f;
                } else if (estimatedFrequencyHz > 2.2f) {
                    targetSpeed *= 1.15f;
                }
            }

            return targetSpeed;

        } catch (e) {
            return 0.0f;
        }
    }

    function isProbablyMoving() as Boolean {
        if (speed >= MIN_VALID_GPS_SPEED_MPS) {
            return true;
        }
        return isMotionDetected;
    }

    function updateMotionConfidence() as Void {
        if (isProbablyMoving()) {
            if (movingConfidence < MOVING_CONFIDENCE_MAX) {
                movingConfidence += 2;
                if (movingConfidence > MOVING_CONFIDENCE_MAX) {
                    movingConfidence = MOVING_CONFIDENCE_MAX;
                }
            }
        } else {
            // Rapid decay when stationary to prevent Dead Reckoning over-shooting
            movingConfidence -= 4; 
            if (movingConfidence < 0) {
                movingConfidence = 0;
            }
        }
    }

    function resetMotionState() as Void {
        motionScoreMg       = 0.0f;
        motionBaselineMg    = MIN_BASELINE_MG;
        motionBaselineReady = false;
        motionVar           = 0.0f;
        lastAccelMag        = 0.0f;
        motionStateCount    = 0;
        isMotionDetected    = false;
        movingConfidence    = 0;
        
        // Reset cadence trackers
        zeroCrossCount       = 0;
        sampleCountForPeriod = 0;
        estimatedFrequencyHz = 0.0f;
        lastHpSample         = 0.0f;
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

    function isGpsQualityUsable(q as Number or Null) as Boolean {
        if (q == null) {
            return false;
        }
        return q == Position.QUALITY_USABLE || q == Position.QUALITY_GOOD;
    }

    function readSensors(info as Sensor.Info or Null) as Void {
        try {
            if (info == null) {
                return;
            }

            if (info has :heartRate && info.heartRate != null) {
                heartRate = info.heartRate;
            } else {
                heartRate = 0;
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

    function updateDepth(info as Sensor.Info or Null) as Void {
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

            if (!isUnderwater && currentDepth <= DEPTH_NOISE_FLOOR_M) {
                surfaceAltitude = (1.0f - SURFACE_RECAL_ALPHA) * surfaceAltitude
                                + SURFACE_RECAL_ALPHA * rawAlt;
            }

            var rawDepth = surfaceAltitude - rawAlt;
            depthFilter = (depthFilter * 0.75f) + (rawDepth * 0.25f);

            if (depthFilter < DEPTH_NOISE_FLOOR_M) {
                depthFilter = 0.0f;
            }

            currentDepth = depthFilter;
        } catch (e) {
            System.println("updateDepth error: " + errorToString(e));
        }
    }

    function updateGPS(sensorInfo as Sensor.Info or Null, posInfo as Position.Info or Null) as Void {
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

            if (!isUnderwater && currentDepth > DIVE_START_DEPTH_M) {
                isUnderwater = true;
            } else if (isUnderwater && currentDepth <= SURFACE_STOP_DEPTH_M) {
                isUnderwater = false;
            }
        } catch (e) {
            System.println("processDiveState error: " + errorToString(e));
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
                var dialog = new WatchUi.Confirmation("Stop & Save?");
                WatchUi.pushView(
                    dialog,
                    new ConfirmStopDelegate(self),
                    WatchUi.SLIDE_IMMEDIATE
                );
                return true;
            }

            prepareToExit();
            return false;

        } catch (e) {
            System.println("Back button error: " + errorToString(e));
            return false;
        }
    }

    function startSession() as Void {
        try {
            if (isRecording) {
                return;
            }

            System.println("MANUAL START");
            startGps();
            captureEntryPosition();
            startRecording();

            if (!isRecording) {
                return;
            }

            isUnderwater = (currentDepth > DIVE_START_DEPTH_M);
            resetHeadingEstimate();
            resetMotionState();
            movingConfidence = 0;
            fitWriteTick = 0;
            heartRate = 0;
            currentAscentRateMps = 0.0f;

            startMotionListener();

            if (kalman != null) {
                kalman.reset();
                if (hasGpsFix) {
                    kalman.setReference(entryLat, entryLon);
                }
            }

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
            if (n2Model != null) {
                n2Model.reset();
            }
            lastDepthForAscent = 0.0f;
            currentAscentRateMps = 0.0f;
            System.println("MANUAL STOP - Saving FIT");
            captureExitPosition();
            isUnderwater = false;
            shutdownSessionSafe();
            stopGps();
            stopMotionListener();
            resetDepthCalibration();
            resetMotionState();
            resetHeadingEstimate();
            hasEntryPosition = false;
            heartRate = 0;
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
                hasEntryPosition = true;
            } else {
                hasEntryPosition = false;
            }
        } catch (e) {
            System.println("captureEntryPosition error: " + errorToString(e));
            hasEntryPosition = false;
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

    function safeCreateField(name as String, id as Number, type as Number, units as String) as FitContributor.Field or Null {
        if (session == null) {
            return null;
        }
        try {
            return session.createField(name, id, type, {
                :mesgType => FitContributor.MESG_TYPE_RECORD,
                :units => units
            });
        } catch (e) {
            System.println("createField failed: " + name + " -> " + errorToString(e));
            return null;
        }
    }

    function startRecording() as Void {
        try {
            shutdownSessionWithoutSave();

            var now = Time.now();
            var info = Gregorian.info(now, Time.FORMAT_SHORT);

            var name = Lang.format("DR $1$-$2$-$3$ $4$:$5$", [
                info.year.format("%04d"),
                info.month.format("%02d"),
                info.day.format("%02d"),
                info.hour.format("%02d"),
                info.min.format("%02d")
            ]);


            session = ActivityRecording.createSession({
                :name => name,
                :sport => Activity.SPORT_GENERIC
            });

            if (session == null) {
                System.println("createSession returned null");
                return;
            }

            drEastField     = safeCreateField("DR_East_m",    FIELD_DR_EAST,    FitContributor.DATA_TYPE_FLOAT,  "m");
            drNorthField    = safeCreateField("DR_North_m",   FIELD_DR_NORTH,   FitContributor.DATA_TYPE_FLOAT,  "m");
            depthField      = safeCreateField("Depth_m",      FIELD_DEPTH,      FitContributor.DATA_TYPE_FLOAT,  "m");
            motionField     = safeCreateField("Motion_mg",    FIELD_MOTION,     FitContributor.DATA_TYPE_FLOAT,  "mg");
            speedEstField   = safeCreateField("Speed_Est",    FIELD_SPEED_EST,  FitContributor.DATA_TYPE_FLOAT,  "m/s");
            underwaterField = safeCreateField("Underwater",   FIELD_UNDERWATER, FitContributor.DATA_TYPE_UINT32, "bool");
            gpsFixField     = safeCreateField("GPS_Fix",      FIELD_GPS_FIX,    FitContributor.DATA_TYPE_UINT32, "bool");
            headingField    = safeCreateField("Heading_deg",  FIELD_HEADING,    FitContributor.DATA_TYPE_FLOAT,  "deg");
            movingField     = safeCreateField("Moving",       FIELD_MOVING,     FitContributor.DATA_TYPE_UINT32, "bool");
            drLatField      = safeCreateField("DR_Lat",       FIELD_DR_LAT,     FitContributor.DATA_TYPE_FLOAT,  "deg");
            drLonField      = safeCreateField("DR_Lon",       FIELD_DR_LON,     FitContributor.DATA_TYPE_FLOAT,  "deg");

            n2LoadField     = safeCreateField("N2_Load",      FIELD_N2_LOAD,    FitContributor.DATA_TYPE_FLOAT,  "%");
            n2MaxField      = safeCreateField("N2_Load_Max",  FIELD_N2_MAX,     FitContributor.DATA_TYPE_FLOAT,  "%");
            n2BandField     = safeCreateField("N2_Risk_Band", FIELD_N2_BAND,    FitContributor.DATA_TYPE_UINT32, "band");

            gpsLatField     = safeCreateField("GPS_Lat",      FIELD_GPS_LAT,    FitContributor.DATA_TYPE_FLOAT,  "deg");
            gpsLonField     = safeCreateField("GPS_Lon",      FIELD_GPS_LON,    FitContributor.DATA_TYPE_FLOAT,  "deg");

            hrField     = null; // safeCreateField("Heart_Rate", FIELD_HEART_RATE, FitContributor.DATA_TYPE_UINT32, "bpm");
            ascentField = null; // safeCreateField("Ascent_Rate", FIELD_ASCENT, FitContributor.DATA_TYPE_FLOAT, "m/s");

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
        } catch (e) {
        }

        forceCleanup();
    }

    function stopTimerOnly() as Void {
        if (updateTimer != null) {
            try {
                updateTimer.stop();
            } catch (e) {
            }
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
        lastFitN2Load = null;
        lastFitN2Max = null;
        lastFitN2Band = null;
        lastFitHr = null;
        lastFitAscent = null;
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
        drLatField = null;
        drLonField = null;
        n2LoadField = null;
        n2MaxField = null;
        n2BandField = null;
        hrField = null;
        ascentField = null;
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

    function isFiniteValue(v as Float or Null) as Boolean {
        if (v == null) {
            return false;
        }

        try {
            var s = v.format("%.6f");
            if (s.equals("nan") || s.equals("NaN") || s.equals("inf") || s.equals("-inf")) {
                return false;
            }
        } catch (e) {
            return false;
        }

        return true;
    }

    function writeFloatField(field as FitContributor.Field or Null, value as Float, lastValue as Float or Null, eps as Float) as Float or Null {
        if (field == null || !isFiniteValue(value)) {
            return lastValue;
        }

        if (lastValue == null || !floatEquals(lastValue, value, eps)) {
            field.setData(value);
            return value;
        }

        return lastValue;
    }

    function writeUIntField(field as FitContributor.Field or Null, value as Number, lastValue as Number or Null) as Number or Null {
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
            if (!isRecording || session == null) {
                return;
            }

            var eastVal = (kalman != null) ? kalman.getEast() : (dr != null ? dr.getDRData()[:east] : 0.0f);
            var northVal = (kalman != null) ? kalman.getNorth() : (dr != null ? dr.getDRData()[:north] : 0.0f);

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

            if (hasEntryPosition && isFiniteValue(eastVal) && isFiniteValue(northVal)) {
                var latRefRad = entryLat * 0.017453292519943295f;
                var metersPerDegLat = 111000.0f;
                var metersPerDegLon = 111000.0f * Math.cos(latRefRad);

                if (metersPerDegLon < 1000.0f) {
                    metersPerDegLon = 1000.0f;
                }

                var synthLat = entryLat + (northVal / metersPerDegLat);
                var synthLon = entryLon + (eastVal / metersPerDegLon);

                if (drLatField != null && isFiniteValue(synthLat)) {
                    drLatField.setData(synthLat);
                }
                if (drLonField != null && isFiniteValue(synthLon)) {
                    drLonField.setData(synthLon);
                }
            }

            if (bestHeading != null) {
                lastFitHeading = writeFloatField(headingField, headingDegVal, lastFitHeading, 0.5f);
            }

            if (gpsLatField != null && hasGpsFix && isFiniteValue(latitude)) {
                gpsLatField.setData(latitude);
            }

            if (gpsLonField != null && hasGpsFix && isFiniteValue(longitude)) {
                gpsLonField.setData(longitude);
            }

            if (n2Model != null) {
                lastFitN2Load = writeFloatField(n2LoadField, n2Model.getLoading(), lastFitN2Load, 0.1f);
                lastFitN2Max = writeFloatField(n2MaxField, n2Model.getMaxLoading(), lastFitN2Max, 0.1f);
                lastFitN2Band = writeUIntField(n2BandField, n2Model.getRiskBand(), lastFitN2Band);
            }

            if (heartRate > 0) {
                lastFitHr = writeUIntField(hrField, heartRate, lastFitHr);
            }
            lastFitAscent = writeFloatField(ascentField, currentAscentRateMps, lastFitAscent, 0.05f);

        } catch (e) {
            System.println("FIT write error: " + errorToString(e));
        }
    }

    function floatEquals(a as Float, b as Float, eps as Float) as Boolean {
        try {
            var diff = a - b;
            if (diff < 0.0f) {
                diff = -diff;
            }
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
            var y = 8 + scrollY;
            var rowH = 18;

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
            dc.drawText(leftX, y, font, "Asc:", Graphics.TEXT_JUSTIFY_LEFT);
            dc.drawText(rightX, y, font, currentAscentRateMps.format("%.2f") + "m/s", Graphics.TEXT_JUSTIFY_LEFT);

            y += rowH;
            dc.drawText(leftX, y, font, "HR:", Graphics.TEXT_JUSTIFY_LEFT);
            if (heartRate > 0) {
                dc.drawText(rightX, y, font, heartRate.format("%d") + " bpm", Graphics.TEXT_JUSTIFY_LEFT);
            } else {
                dc.drawText(rightX, y, font, "--", Graphics.TEXT_JUSTIFY_LEFT);
            }

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

            if (kalman != null) {
                var kd = kalman.getDRData();
                dc.drawText(leftX, y, font, "KF E:", Graphics.TEXT_JUSTIFY_LEFT);
                dc.drawText(rightX, y, font, kd[:east].format("%.1f") + "m", Graphics.TEXT_JUSTIFY_LEFT);
                y += rowH;
                dc.drawText(leftX, y, font, "KF N:", Graphics.TEXT_JUSTIFY_LEFT);
                dc.drawText(rightX, y, font, kd[:north].format("%.1f") + "m", Graphics.TEXT_JUSTIFY_LEFT);
                y += rowH;
            } else if (dr != null) {
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
            }

            dc.drawText(leftX, y, font, "Spd:", Graphics.TEXT_JUSTIFY_LEFT);
            dc.drawText(rightX, y, font, speed.format("%.2f") + "m/s", Graphics.TEXT_JUSTIFY_LEFT);

            if (n2Model != null) {
                y += rowH;
                dc.drawText(leftX, y, font, "N2:", Graphics.TEXT_JUSTIFY_LEFT);
                dc.drawText(rightX, y, font, n2Model.getLoading().format("%.0f") + "%", Graphics.TEXT_JUSTIFY_LEFT);

                y += rowH;
                dc.drawText(leftX, y, font, "Max:", Graphics.TEXT_JUSTIFY_LEFT);
                dc.drawText(rightX, y, font, n2Model.getMaxLoading().format("%.0f") + "%", Graphics.TEXT_JUSTIFY_LEFT);

                y += rowH;
                var band = n2Model.getRiskBand();
                var bandText = "LOW";
                var bandColor = Graphics.COLOR_GREEN;

                if (band == 1) {
                    bandText = "MOD";
                    bandColor = Graphics.COLOR_YELLOW;
                } else if (band == 2) {
                    bandText = "ELEV";
                    bandColor = Graphics.COLOR_ORANGE;
                } else if (band == 3) {
                    bandText = "HIGH";
                    bandColor = Graphics.COLOR_RED;
                }

                dc.setColor(bandColor, Graphics.COLOR_TRANSPARENT);
                dc.drawText(leftX, y, font, "Risk:", Graphics.TEXT_JUSTIFY_LEFT);
                dc.drawText(rightX, y, font, bandText, Graphics.TEXT_JUSTIFY_LEFT);

                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            }
        } catch (e) {
            System.println("Draw error: " + errorToString(e));
        }
    }

    function prepareToExit() as Void {
        if (isRecording) {
            stopSession();
        }
        stopTimerOnly();
        stopMotionListener();
        stopGps();
    }
}