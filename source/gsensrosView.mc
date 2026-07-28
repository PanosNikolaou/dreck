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
    var currentAscentRateMps = 0.0f;          // NEW – exposed for UI / FIT

    // Heart-rate (health data)
    var heartRate = 0;                        // NEW

    const SURFACE_RECAL_ALPHA   = 0.02f;   // how fast surface reference adapts on land
    const DEPTH_NOISE_FLOOR_M   = 0.4f;    // ignore anything below this
    const DIVE_START_DEPTH_M    = 1.5f;
    const SURFACE_STOP_DEPTH_M  = 0.5f;

    // Physical limits – stops the 100–2000 m spikes seen in FIT telemetry
    const MAX_DEPTH_M           = 80.0f;   // hard clamp (tech diving upper bound)
    const MAX_DEPTH_RATE_MPS    = 3.0f;    // max |d(depth)/dt| accepted (~180 m/min)
    const MIN_VALID_ALT_M       = -120.0f; // reject GPS/baro altitude garbage
    const MAX_VALID_ALT_M       = 5000.0f;
    // Seawater approx: 1 m depth ≈ 10050 Pa over surface pressure
    const PA_PER_METER_SEAWATER = 10050.0f;
    const DEFAULT_SURFACE_PA    = 101325.0f;

    // Dive-state hysteresis (prevents instant start->stop at the surface)
    var diveStartMs = 0;
    var shallowSampleCount = 0;
    const MIN_DIVE_DURATION_MS = 10000;
    const SHALLOW_SAMPLES_TO_STOP = 5;

    // Additional health data
    var spo2 = 0;                          // NEW - pulse oximetry, %
    var ambientTempC = 0.0f;                // NEW - ambient/water temperature

    // Session-summary tracking (written once at stopSession())
    var maxDepthSeen = 0.0f;                // NEW
    var diveTimeMs = 0;                     // NEW - time spent underwater
    var maxN2LoadSeen = 0.0f;               // NEW

    // FIT field IDs
    // FIT developer field IDs must be unique 0–255.
    // Instinct-class devices only allow ~16 developer fields total – keep ≤14.
    const FIELD_DR_EAST    = 0;
    const FIELD_DR_NORTH   = 1;
    const FIELD_DEPTH      = 2;
    const FIELD_SPEED_EST  = 3;
    const FIELD_HEADING    = 4;
    const FIELD_UNDERWATER = 5;
    const FIELD_MOTION     = 6;
    const FIELD_MOVING     = 7;
    const FIELD_GPS_FIX    = 8;
    const FIELD_DR_LAT     = 9;
    const FIELD_DR_LON     = 10;
    const FIELD_POI_ID     = 11;
    const FIELD_POI_LAT    = 12;
    const FIELD_POI_LON    = 13;
    // Kept as constants for code that still references them (fields not created)
    const FIELD_GPS_LAT    = 14;
    const FIELD_GPS_LON    = 15;
    const FIELD_N2_LOAD    = 16;
    const FIELD_N2_MAX     = 17;
    const FIELD_N2_BAND    = 18;
    const FIELD_HR         = 19;
    const FIELD_ASCENT     = 20;
    const FIELD_SPO2       = 21;
    const FIELD_TEMP       = 22;
    const FIELD_MAX_DEPTH  = 23;
    const FIELD_DIVE_TIME  = 24;
    const FIELD_MAX_N2     = 25;
    const FIELD_POI_EAST   = 26;
    const FIELD_POI_NORTH  = 27;

    const MAX_POIS = 30;

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
    var hrField = null as FitContributor.Field or Null;          // NEW
    var ascentField = null as FitContributor.Field or Null;      // NEW
    var spo2Field = null as FitContributor.Field or Null;        // NEW
    var tempField = null as FitContributor.Field or Null;        // NEW

    // Session-level summary fields (written once, not per-record)
    var maxDepthField = null as FitContributor.Field or Null;    // NEW
    var diveTimeField = null as FitContributor.Field or Null;    // NEW
    var maxN2Field = null as FitContributor.Field or Null;       // NEW

    // POI marker fields (written once per mark into the record stream)
    var poiIdField = null as FitContributor.Field or Null;
    var poiLatField = null as FitContributor.Field or Null;
    var poiLonField = null as FitContributor.Field or Null;
    var poiEastField = null as FitContributor.Field or Null;
    var poiNorthField = null as FitContributor.Field or Null;

    var poiCount = 0;
    var poiFlashMs = 0;           // UI: show "POI #n" briefly after mark
    const POI_FLASH_MS = 2000;

    var surfaceAltitudeSum = 0.0f;
    var surfaceAltitude = 0.0f;
    var surfacePressurePa = 101325.0f;
    var surfacePressureSum = 0.0f;
    var depthFilter = 0.0f;
    var calibrationSamples = 0;
    const CALIBRATION_COUNT = 20;   // a bit longer for a stable surface reference
    var currentDepth = 0.0f;
    var lastDepthUpdateMs = 0;
    var usePressureDepth = false;   // true once we have a pressure-based surface cal

    var motionScoreMg = 0.0f;
    var motionBaselineMg = 0.0f;
    var motionBaselineReady = false;
    var isMotionDetected = false;
    var sensorListenerActive = false;

    const TIMER_PERIOD_MS = 500;
    const SENSOR_PERIOD_SEC = 1;
    const SENSOR_SAMPLE_RATE_HZ = 10;

    const GPS_ZERO_SPEED_MPS = 0.20f;
    const MIN_VALID_GPS_SPEED_MPS = 0.35f;
    const DR_MOVE_SPEED_THRESHOLD_MPS = 0.05f;

    // Continuous motion→speed mapping (replaces coarse step buckets)
    const MIN_MOTION_SWIM_MG = 18.0f;
    const MAX_MOTION_SWIM_MG = 100.0f;
    const MIN_SWIM_SPEED_MPS = 0.20f;
    const MAX_SWIM_SPEED_MPS = 0.65f;

    const MIN_MOTION_LAND_MG = 22.0f;
    const MAX_MOTION_LAND_MG = 160.0f;
    const MIN_LAND_SPEED_MPS = 0.30f;
    const MAX_LAND_SPEED_MPS = 1.35f;

    const SPEED_SMOOTH_RISE = 0.35f;   // respond faster when accelerating
    const SPEED_SMOOTH_FALL = 0.18f;   // decay slower when stopping

    const MOTION_FILTER_ALPHA = 0.55f; // slightly more responsive motion score

    var filteredSpeedEst = 0.0f;       // smoothed output of getEstimatedSpeedMps

    var lastFitEast = null as Float or Null;
    var lastFitNorth = null as Float or Null;
    var lastFitDepth = null as Float or Null;
    var lastFitMotion = null as Float or Null;
    var lastFitSpeedEst = null as Float or Null;
    var lastFitUnderwater = null as Number or Null;
    var lastFitGpsFix = null as Number or Null;
    var lastFitHeading = null as Float or Null;
    var lastFitMoving = null as Number or Null;
    var lastFitHr = null as Number or Null;          // NEW
    var lastFitAscent = null as Float or Null;       // NEW
    var lastFitSpo2 = null as Number or Null;        // NEW
    var lastFitTemp = null as Float or Null;         // NEW

    var scrollY = 0;
    const SCROLL_STEP = 20;
    const SCROLL_MIN = -180;   // increased a bit for extra lines
    const SCROLL_MAX = 0;

    // --- Improved motion detection ---
    var lastAccelMag     = 0.0f;
    var motionVar        = 0.0f;          // exponential variance of high-pass accel
    var motionStateCount = 0;             // unified hysteresis counter

    const MOTION_HP_ALPHA      = 0.18f;   // high-pass for gravity removal
    const MOTION_VAR_ALPHA     = 0.25f;   // variance smoothing
    const GYRO_WEIGHT          = 60.0f;   // scale rad/s → similar range as mg
    const MIN_BASELINE_MG      = 10.0f;   // floor so baseline cannot collapse to 0

    const BASELINE_ADAPT_FAST  = 0.10f;   // when stationary
    const BASELINE_ADAPT_SLOW  = 0.012f;  // when moving

    const MOTION_ON_MG         = 20.0f;
    const MOTION_OFF_MG        = 9.0f;
    const CONF_RISE            = 2;       // samples to declare moving
    const CONF_FALL            = 5;       // samples to declare stationary (stickier off)

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

            // Ascent rate (positive = ascending)
            currentAscentRateMps = 0.0f;
            if (dt > 0.0f) {
                currentAscentRateMps = (lastDepthForAscent - currentDepth) / dt;
            }
            lastDepthForAscent = currentDepth;

            if (n2Model != null) {
                n2Model.update(currentDepth, dt, isUnderwater, currentAscentRateMps);
            }

            // Track session-summary values while recording
            if (isRecording) {
                if (currentDepth > maxDepthSeen) {
                    maxDepthSeen = currentDepth;
                }
                if (isUnderwater) {
                    diveTimeMs += (dt * 1000.0f).toNumber();
                }
                if (n2Model != null && n2Model.getMaxLoading() > maxN2LoadSeen) {
                    maxN2LoadSeen = n2Model.getMaxLoading();
                }
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
                    // Always propagate with UKF kinematics, then correct with GPS.
                    var h = (bestHeading != null) ? bestHeading : 0.0f;
                    kalman.predict(estSpeed, h, dt);
                    if (hasGpsFix && isGpsQualityUsable(gpsQuality)) {
                        kalman.updateGps(latitude, longitude, gpsQuality);
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
                    :includePower => true,
                    // raw axes are usually available by default when sampleRate is set
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

    function updateMotionFromAccel(ax as Float, ay as Float, az as Float) as Void {
        var mag = Math.sqrt(ax * ax + ay * ay + az * az);

        // High-pass filter (removes gravity)
        var hp = mag - lastAccelMag;
        lastAccelMag = (1.0f - MOTION_HP_ALPHA) * lastAccelMag + MOTION_HP_ALPHA * mag;

        // Exponential variance of the high-pass signal
        motionVar = (1.0f - MOTION_VAR_ALPHA) * motionVar
                + MOTION_VAR_ALPHA * (hp * hp);
    }

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
        // else: stay in current state (dead-band / hysteresis)
    }

    function sensorDataCallback(sensorData as Sensor.SensorData) as Void {
        try {
            if (sensorData == null || !(sensorData has :accelerometerData) || sensorData.accelerometerData == null) {
                return;
            }

            var accData = sensorData.accelerometerData;

            // Prefer the raw samples if available (better than power)
            if (accData has :x && accData.x != null && accData.x.size() > 0) {
                var count = accData.x.size();
                var i = 0;
                while (i < count) {
                    var ax = accData.x[i].toFloat();
                    var ay = (accData has :y && accData.y != null) ? accData.y[i].toFloat() : 0.0f;
                    var az = (accData has :z && accData.z != null) ? accData.z[i].toFloat() : 0.0f;

                    updateMotionFromAccel(ax, ay, az);
                    i += 1;
                }
            }
            // Fallback to power if raw axes are not present
            else if (accData has :power && accData.power != null) {
                var p = accData.power;
                var count = p.size();
                if (count <= 0) { return; }

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
                if (validCount <= 0) { return; }

                var avgPower = sumPower / validCount.toFloat();
                // Treat power as a crude magnitude for the high-pass path
                updateMotionFromAccel(avgPower, 0.0f, 0.0f);
            } else {
                return;
            }

            // --- Combined score ---
            var gyroMag = Math.sqrt(gyroX * gyroX + gyroY * gyroY + gyroZ * gyroZ);
            var rawScore = Math.sqrt(motionVar) * 1000.0f + gyroMag * GYRO_WEIGHT;

            // Adaptive baseline with floor
            if (!motionBaselineReady) {
                motionBaselineMg = (rawScore > MIN_BASELINE_MG) ? rawScore : MIN_BASELINE_MG;
                motionBaselineReady = true;
            } else {
                var alpha = isMotionDetected ? BASELINE_ADAPT_SLOW : BASELINE_ADAPT_FAST;
                motionBaselineMg = (1.0f - alpha) * motionBaselineMg + alpha * rawScore;
                if (motionBaselineMg < MIN_BASELINE_MG) {
                    motionBaselineMg = MIN_BASELINE_MG;
                }
            }

            // Only positive excess over baseline counts as motion energy
            var delta = rawScore - motionBaselineMg;
            if (delta < 0.0f) {
                delta = 0.0f;
            }
            motionScoreMg = (MOTION_FILTER_ALPHA * motionScoreMg)
                        + ((1.0f - MOTION_FILTER_ALPHA) * delta);

            // Unified hysteresis
            updateMotionState();

        } catch (e) {
            System.println("sensorDataCallback error: " + errorToString(e));
        }
    }

    function isStationary() as Boolean {
        if (speed >= MIN_VALID_GPS_SPEED_MPS) {
            return false;
        }
        var gyroMag = Math.sqrt(gyroX * gyroX + gyroY * gyroY + gyroZ * gyroZ);
        if (gyroMag > STATIONARY_GYRO_MAG_RAD_S) {
            return false;
        }
        return !isMotionDetected;
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
                movingConfidence += 1;
            }
        } else {
            if (movingConfidence > 0) {
                movingConfidence -= 1;
            }
        }
    }

    function resetMotionState() as Void {
        motionScoreMg       = 0.0f;
        motionBaselineMg    = 0.0f;
        motionBaselineReady = false;
        motionVar           = 0.0f;
        lastAccelMag        = 0.0f;
        motionStateCount    = 0;
        isMotionDetected    = false;
        movingConfidence    = 0;
        filteredSpeedEst    = 0.0f;
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

            // Heart rate (health data)
            if (info has :heartRate && info.heartRate != null) {
                heartRate = info.heartRate;
            } else {
                heartRate = 0;
            }

            // SpO2 (health data) - unreliable when wet, log for surface intervals only
            if (info has :oxygenSaturation && info.oxygenSaturation != null) {
                spo2 = info.oxygenSaturation;
            } else {
                spo2 = 0;
            }

            // Ambient / water temperature
            if (info has :temperature && info.temperature != null) {
                ambientTempC = info.temperature.toFloat();
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
            if (info == null) {
                return;
            }

            var nowMs = System.getTimer();
            var dt = 0.5f;
            if (lastDepthUpdateMs > 0) {
                dt = (nowMs - lastDepthUpdateMs).toFloat() / 1000.0f;
                if (dt < 0.05f) { dt = 0.05f; }
                if (dt > 2.0f)  { dt = 2.0f; }
            }
            lastDepthUpdateMs = nowMs;

            // Prefer ambient pressure (Pa) when the device exposes it.
            // Altitude alone is polluted by GPS and hard-clamped near -500 m,
            // which produced the 100–2000 m depth spikes in the FIT logs.
            var hasPressure = (info has :pressure) && (info.pressure != null);
            var pressurePa = hasPressure ? info.pressure.toFloat() : 0.0f;

            var hasAlt = (info has :altitude) && (info.altitude != null);
            var rawAlt = hasAlt ? info.altitude.toFloat() : 0.0f;
            var altValid = hasAlt && rawAlt >= MIN_VALID_ALT_M && rawAlt <= MAX_VALID_ALT_M;

            // ---------- Initial surface calibration ----------
            if (calibrationSamples < CALIBRATION_COUNT) {
                if (hasPressure && pressurePa > 80000.0f && pressurePa < 110000.0f) {
                    surfacePressureSum += pressurePa;
                    usePressureDepth = true;
                }
                if (altValid) {
                    surfaceAltitudeSum += rawAlt;
                }
                calibrationSamples += 1;

                if (calibrationSamples == CALIBRATION_COUNT) {
                    if (usePressureDepth && surfacePressureSum > 0.0f) {
                        surfacePressurePa = surfacePressureSum / CALIBRATION_COUNT.toFloat();
                    } else {
                        usePressureDepth = false;
                        surfacePressurePa = DEFAULT_SURFACE_PA;
                    }
                    if (surfaceAltitudeSum != 0.0f) {
                        surfaceAltitude = surfaceAltitudeSum / CALIBRATION_COUNT.toFloat();
                    }
                    depthFilter = 0.0f;
                    System.println("Depth cal done: P0=" + surfacePressurePa.format("%.0f")
                        + " Pa  alt0=" + surfaceAltitude.format("%.1f")
                        + " useP=" + usePressureDepth);
                }
                currentDepth = 0.0f;
                return;
            }

            // ---------- Continuous surface recalibration (only on surface) ----------
            if (!isUnderwater && currentDepth <= DEPTH_NOISE_FLOOR_M) {
                if (usePressureDepth && hasPressure
                    && pressurePa > 80000.0f && pressurePa < 110000.0f) {
                    surfacePressurePa = (1.0f - SURFACE_RECAL_ALPHA) * surfacePressurePa
                                      + SURFACE_RECAL_ALPHA * pressurePa;
                }
                if (altValid) {
                    surfaceAltitude = (1.0f - SURFACE_RECAL_ALPHA) * surfaceAltitude
                                    + SURFACE_RECAL_ALPHA * rawAlt;
                }
            }

            // ---------- Raw depth ----------
            var rawDepth = 0.0f;
            if (usePressureDepth && hasPressure && pressurePa > 50000.0f) {
                // Positive depth when pressure rises above surface reference
                rawDepth = (pressurePa - surfacePressurePa) / PA_PER_METER_SEAWATER;
            } else if (altValid) {
                // Fallback: altitude drop relative to surface altitude
                rawDepth = surfaceAltitude - rawAlt;
            } else {
                // No usable sensor this tick – hold previous filtered value
                return;
            }

            // Reject non-physical jumps (GPS altitude jumps, baro glitches)
            var maxDelta = MAX_DEPTH_RATE_MPS * dt;
            var prev = depthFilter;
            if (rawDepth - prev > maxDelta) {
                rawDepth = prev + maxDelta;
            } else if (prev - rawDepth > maxDelta) {
                rawDepth = prev - maxDelta;
            }

            // Low-pass
            depthFilter = (depthFilter * 0.70f) + (rawDepth * 0.30f);

            // Noise floor
            if (depthFilter < DEPTH_NOISE_FLOOR_M) {
                depthFilter = 0.0f;
            }

            // Absolute clamp – never report depths that recreational/tech sensors
            // cannot produce; this is what stopped the 1500 m+ FIT values.
            if (depthFilter > MAX_DEPTH_M) {
                depthFilter = MAX_DEPTH_M;
            }
            if (depthFilter < 0.0f) {
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
                shallowSampleCount = 0;
                return;
            }

            if (!isUnderwater && currentDepth > DIVE_START_DEPTH_M) {
                isUnderwater = true;
                diveStartMs = System.getTimer();
                shallowSampleCount = 0;
                return;
            }

            if (isUnderwater) {
                var elapsed = System.getTimer() - diveStartMs;

                // Don't allow auto-stop until a minimum dive duration has passed;
                // avoids the instant start->stop loop caused by depth noise.
                if (elapsed < MIN_DIVE_DURATION_MS) {
                    return;
                }

                if (currentDepth <= SURFACE_STOP_DEPTH_M) {
                    shallowSampleCount += 1;
                    if (shallowSampleCount >= SHALLOW_SAMPLES_TO_STOP) {
                        isUnderwater = false;
                        shallowSampleCount = 0;
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
            // Priority 1: trustworthy GPS speed
            if (speed >= MIN_VALID_GPS_SPEED_MPS) {
                filteredSpeedEst = speed;
                return filteredSpeedEst;
            }

            // Priority 2: not confident we are moving
            if (movingConfidence < MOVING_CONFIDENCE_ON || isStationary()) {
                // Soft decay toward zero
                filteredSpeedEst *= 0.70f;
                if (filteredSpeedEst < 0.05f) {
                    filteredSpeedEst = 0.0f;
                }
                return filteredSpeedEst;
            }

            // Priority 3: continuous intensity → speed map
            var target = 0.0f;
            if (isUnderwater) {
                if (motionScoreMg <= MIN_MOTION_SWIM_MG) {
                    target = MIN_SWIM_SPEED_MPS;
                } else if (motionScoreMg >= MAX_MOTION_SWIM_MG) {
                    target = MAX_SWIM_SPEED_MPS;
                } else {
                    var n = (motionScoreMg - MIN_MOTION_SWIM_MG)
                          / (MAX_MOTION_SWIM_MG - MIN_MOTION_SWIM_MG);
                    target = MIN_SWIM_SPEED_MPS + n * (MAX_SWIM_SPEED_MPS - MIN_SWIM_SPEED_MPS);
                }
            } else {
                if (motionScoreMg <= MIN_MOTION_LAND_MG) {
                    target = MIN_LAND_SPEED_MPS;
                } else if (motionScoreMg >= MAX_MOTION_LAND_MG) {
                    target = MAX_LAND_SPEED_MPS;
                } else {
                    var n2 = (motionScoreMg - MIN_MOTION_LAND_MG)
                           / (MAX_MOTION_LAND_MG - MIN_MOTION_LAND_MG);
                    target = MIN_LAND_SPEED_MPS + n2 * (MAX_LAND_SPEED_MPS - MIN_LAND_SPEED_MPS);
                }
            }

            // Asymmetric low-pass: rise faster than fall
            var a = (target > filteredSpeedEst) ? SPEED_SMOOTH_RISE : SPEED_SMOOTH_FALL;
            filteredSpeedEst = filteredSpeedEst + a * (target - filteredSpeedEst);
            if (filteredSpeedEst < 0.05f) {
                filteredSpeedEst = 0.0f;
            }
            return filteredSpeedEst;
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

    // CTRL / Menu button → drop a POI on the current DR route while recording
    function onMenu() as Boolean {
        try {
            if (!isRecording) {
                System.println("POI ignored – not recording");
                return true;
            }
            markPoi();
        } catch (e) {
            System.println("onMenu/POI error: " + errorToString(e));
        }
        return true;
    }

    function markPoi() as Void {
        if (!isRecording || session == null) {
            return;
        }
        if (poiCount >= MAX_POIS) {
            System.println("POI limit reached (" + MAX_POIS + ")");
            poiFlashMs = System.getTimer(); // still flash so user knows press was seen
            WatchUi.requestUpdate();
            return;
        }

        var eastVal = 0.0f;
        var northVal = 0.0f;
        if (kalman != null) {
            eastVal = kalman.getEast();
            northVal = kalman.getNorth();
        } else if (dr != null) {
            var dd = dr.getDRData();
            eastVal = dd[:east];
            northVal = dd[:north];
        }

        // Prefer live GPS; else synthesise lat/lon from entry + DR offset
        var poiLat = 0.0f;
        var poiLon = 0.0f;
        var haveLatLon = false;

        if (hasGpsFix && isFiniteValue(latitude) && isFiniteValue(longitude)) {
            poiLat = latitude;
            poiLon = longitude;
            haveLatLon = true;
        } else if (hasEntryPosition) {
            var latRefRad = entryLat * 0.017453292519943295f;
            var mPerDegLat = 111000.0f;
            var mPerDegLon = 111000.0f * Math.cos(latRefRad);
            if (mPerDegLon < 1000.0f) {
                mPerDegLon = 1000.0f;
            }
            poiLat = entryLat + (northVal / mPerDegLat);
            poiLon = entryLon + (eastVal / mPerDegLon);
            haveLatLon = true;
        }

        poiCount += 1;

        // Stamp into the FIT record stream at this moment
        if (poiIdField != null) {
            poiIdField.setData(poiCount);
        }
        if (poiEastField != null && isFiniteValue(eastVal)) {
            poiEastField.setData(eastVal);
        }
        if (poiNorthField != null && isFiniteValue(northVal)) {
            poiNorthField.setData(northVal);
        }
        if (haveLatLon) {
            if (poiLatField != null && isFiniteValue(poiLat)) {
                poiLatField.setData(poiLat);
            }
            if (poiLonField != null && isFiniteValue(poiLon)) {
                poiLonField.setData(poiLon);
            }
        }

        // Optional lap marker – shows as a split in Garmin Connect
        try {
            if (session != null && (session has :addLap)) {
                session.addLap();
            }
        } catch (e) {
            // not all devices expose addLap
        }

        poiFlashMs = System.getTimer();
        System.println("POI #" + poiCount + " E=" + eastVal.format("%.1f")
            + " N=" + northVal.format("%.1f")
            + (haveLatLon ? (" lat=" + poiLat.format("%.5f") + " lon=" + poiLon.format("%.5f")) : ""));
        WatchUi.requestUpdate();
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
            maxDepthSeen = 0.0f;
            diveTimeMs = 0;
            maxN2LoadSeen = 0.0f;
            poiCount = 0;
            poiFlashMs = 0;

            // stopSession() stops the accelerometer listener to save power
            // while not recording; bring it back with a clean baseline now.
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

            // Write session-level summary fields while the session is still open
            if (maxDepthField != null) {
                maxDepthField.setData(maxDepthSeen);
            }
            if (diveTimeField != null) {
                diveTimeField.setData(diveTimeMs.toFloat() / 1000.0f);
            }
            if (maxN2Field != null) {
                maxN2Field.setData(maxN2LoadSeen);
            }

            shutdownSessionSafe();
            maxDepthSeen = 0.0f;
            diveTimeMs = 0;
            maxN2LoadSeen = 0.0f;
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
            var u = (units == null || units.length() == 0) ? " " : units;
            var f = session.createField(name, id, type, {
                :mesgType => FitContributor.MESG_TYPE_RECORD,
                :units => u
            });
            System.println("createField OK: " + name + " id=" + id);
            return f;
        } catch (e) {
            System.println("createField failed: " + name + " id=" + id + " -> " + errorToString(e));
            return null;
        }
    }

    function safeCreateSessionField(name as String, id as Number, type as Number, units as String) as FitContributor.Field or Null {
        if (session == null) {
            return null;
        }
        try {
            var u = (units == null || units.length() == 0) ? " " : units;
            return session.createField(name, id, type, {
                :mesgType => FitContributor.MESG_TYPE_SESSION,
                :units => u
            });
        } catch (e) {
            System.println("createSessionField failed: " + name + " -> " + errorToString(e));
            return null;
        }
    }

    function startRecording() as Void {
    try {
        shutdownSessionWithoutSave();

        var now = Time.now();
        var info = Gregorian.info(now, Time.FORMAT_SHORT);

        // Example result: "DR 2026-07-25 16:42"
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

        // Instinct ~16 developer-field limit. Create at most 14 record fields.
        // IDs 0–13 sequential. Extra metrics stay on-screen only.
        drEastField     = safeCreateField("DR_East",   FIELD_DR_EAST,    FitContributor.DATA_TYPE_FLOAT,  "m");
        drNorthField    = safeCreateField("DR_North",  FIELD_DR_NORTH,   FitContributor.DATA_TYPE_FLOAT,  "m");
        depthField      = safeCreateField("Depth",     FIELD_DEPTH,      FitContributor.DATA_TYPE_FLOAT,  "m");
        speedEstField   = safeCreateField("Speed",     FIELD_SPEED_EST,  FitContributor.DATA_TYPE_FLOAT,  "m/s");
        headingField    = safeCreateField("Heading",   FIELD_HEADING,    FitContributor.DATA_TYPE_FLOAT,  "deg");
        underwaterField = safeCreateField("Underwater",FIELD_UNDERWATER, FitContributor.DATA_TYPE_UINT32,  "");
        motionField     = safeCreateField("Motion",    FIELD_MOTION,     FitContributor.DATA_TYPE_FLOAT,  "mg");
        movingField     = safeCreateField("Moving",    FIELD_MOVING,     FitContributor.DATA_TYPE_UINT32,  "");
        gpsFixField     = safeCreateField("GpsFix",    FIELD_GPS_FIX,    FitContributor.DATA_TYPE_UINT32,  "");
        drLatField      = safeCreateField("DR_Lat",    FIELD_DR_LAT,     FitContributor.DATA_TYPE_FLOAT,  "deg");
        drLonField      = safeCreateField("DR_Lon",    FIELD_DR_LON,     FitContributor.DATA_TYPE_FLOAT,  "deg");
        poiIdField      = safeCreateField("POI_Id",    FIELD_POI_ID,     FitContributor.DATA_TYPE_UINT32,  "");
        poiLatField     = safeCreateField("POI_Lat",   FIELD_POI_LAT,    FitContributor.DATA_TYPE_FLOAT,  "deg");
        poiLonField     = safeCreateField("POI_Lon",   FIELD_POI_LON,    FitContributor.DATA_TYPE_FLOAT,  "deg");

        // Not created on-device (stay null) – UI only / avoids field-limit crash:
        // n2*, hr, ascent, spo2, temp, gps lat/lon, poi east/north, session summaries
        n2LoadField = null;
        n2MaxField = null;
        n2BandField = null;
        hrField = null;
        ascentField = null;
        spo2Field = null;
        tempField = null;
        gpsLatField = null;
        gpsLonField = null;
        poiEastField = null;
        poiNorthField = null;
        maxDepthField = null;
        diveTimeField = null;
        maxN2Field = null;

        var started = session.start();
        if (started) {
            isRecording = true;
            clearLastFitValues();
            poiCount = 0;
            poiFlashMs = 0;
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
        lastFitSpo2 = null;
        lastFitTemp = null;
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
        spo2Field = null;
        tempField = null;
        maxDepthField = null;
        diveTimeField = null;
        maxN2Field = null;
        poiIdField = null;
        poiLatField = null;
        poiLonField = null;
        poiEastField = null;
        poiNorthField = null;
        clearLastFitValues();
    }

    function resetDepthCalibration() as Void {
        try {
            surfaceAltitudeSum = 0.0f;
            surfaceAltitude = 0.0f;
            surfacePressureSum = 0.0f;
            surfacePressurePa = DEFAULT_SURFACE_PA;
            depthFilter = 0.0f;
            calibrationSamples = 0;
            currentDepth = 0.0f;
            lastDepthUpdateMs = 0;
            usePressureDepth = false;
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

            // Synthetic lat/lon
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

            // NEW health / dive metrics
            if (heartRate > 0) {
                lastFitHr = writeUIntField(hrField, heartRate, lastFitHr);
            }
            lastFitAscent = writeFloatField(ascentField, currentAscentRateMps, lastFitAscent, 0.05f);

            // SpO2 is optical/wrist-based and unreliable underwater - only log
            // when a real reading is present (0 means no reading this tick).
            if (spo2 > 0) {
                lastFitSpo2 = writeUIntField(spo2Field, spo2, lastFitSpo2);
            }
            lastFitTemp = writeFloatField(tempField, ambientTempC, lastFitTemp, 0.5f);

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
            var statusText = isRecording ? "RECORDING" : "Stopped";
            if (isRecording && poiFlashMs > 0) {
                var age = System.getTimer() - poiFlashMs;
                if (age >= 0 && age < POI_FLASH_MS) {
                    statusText = "POI #" + poiCount;
                    dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
                } else {
                    poiFlashMs = 0;
                }
            }
            dc.drawText(w / 2, y, font, statusText, Graphics.TEXT_JUSTIFY_CENTER);

            y += rowH;

            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            if (isRecording && poiCount > 0) {
                dc.drawText(leftX, y, font, "POIs:", Graphics.TEXT_JUSTIFY_LEFT);
                dc.drawText(rightX, y, font, "" + poiCount, Graphics.TEXT_JUSTIFY_LEFT);
                y += rowH;
            }

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

            // Nitrogen Model display
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