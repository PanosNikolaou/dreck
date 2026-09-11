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
import Toybox.Application;

class gsensrosView extends WatchUi.View {

    function isDebugLoggingEnabled() as Boolean {
        var enabled = Application.Storage.getValue("debug_logs_enabled");
        if (enabled == null) {
            return true;
        }
        return (enabled == true);
    }

    function setDebugLoggingEnabled(enabled as Boolean) as Void {
        Application.Storage.setValue("debug_logs_enabled", enabled);
    }

    function toggleDebugLogging() as Void {
        var nextEnabled = !isDebugLoggingEnabled();
        setDebugLoggingEnabled(nextEnabled);
        if (nextEnabled) {
            logDebug("Debug logging enabled");
        } else {
            logDebug("Debug logging disabled");
        }
    }

    function logDebug(message as String) as Void {
        if (message != null && isDebugLoggingEnabled()) {
            System.println(message);
        }
    }

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
    var gpsFixLostAtMs = 0;
    var gpsRecoveryUntilMs = 0;
    var lastGpsEventMs = 0;
    const GPS_LOSS_HOLD_MS = 1000;
    const GPS_FIX_MAX_AGE_MS = 15000;
    var lastDrGpsCorrectionMs = 0;
    const DR_GPS_CORRECTION_INTERVAL_MS = 1000;

    var entryLat = 0.0f;
    var entryLon = 0.0f;
    var exitLat = 0.0f;
    var exitLon = 0.0f;
    var hasEntryPosition = false;

    var session = null as ActivityRecording.Session or Null;
    var isRecording = false;
    var isDepthActive = false;

    var updateTimer = null as Timer.Timer or Null;
    var dr = null;
    var kalman = null;

    var lastUpdateMs = 0;
    var fitWriteTick = 0;

    var movingConfidence = 0;
    const MOVING_CONFIDENCE_ON = 3;
    const MOVING_CONFIDENCE_MAX = 10;

    const STATIONARY_GYRO_MAG_RAD_S = 0.05f;
    const MAG_FIELD_EXPECTED_UT = 50.0f;
    const MAG_FIELD_DISTORTION_TOL_UT = 20.0f;
    const MAG_HEADING_MIN_CONFIDENCE = 0.20f;

    var calibrationActive = false;
    var calibrationStartMs = 0;
    const CALIBRATION_DURATION_MS = 5000;

    var gyroBiasX = 0.0f;
    var gyroBiasY = 0.0f;
    var gyroBiasZ = 0.0f;
    var gyroCalSamples = 0;
    var gyroBiasStationarySamples = 0;

    var magBiasX = 0.0f;
    var magBiasY = 0.0f;
    var magBiasZ = 0.0f;
    var magCalSamples = 0;
    var lastMagX = 0.0f;
    var lastMagY = 0.0f;
    var lastMagZ = 0.0f;

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
    var solarLux = 0.0f;                      // UI-only solar intensity readout for Instinct 2X Solar

    const SURFACE_RECAL_ALPHA   = 0.02f;   // how fast surface reference adapts on land
    const DEPTH_NOISE_FLOOR_M   = 0.01f;   // keep shallow samples alive without letting pure noise through
    const DEPTH_START_THRESHOLD_M = 0.08f;   // require a meaningful shallow depth signal before starting tracking
    const SURFACE_STOP_DEPTH_M  = 0.10f;   // surface hysteresis should stay stable above noise while still allowing near-surface stops
    const LAND_RETURN_RADIUS_M  = 5.0f;    // stop only when back within 5m of the start GPS point
    const MIN_SURFACE_PRESSURE_PA = 98000.0f;  // reject obvious underwater samples as calibration baselines
    const MAX_SURFACE_PRESSURE_PA = 104500.0f;

    // Physical limits – stops the 100–2000 m spikes seen in FIT telemetry
    const MAX_DEPTH_M           = 80.0f;   // hard clamp (deep tracking upper bound)
    const MAX_DEPTH_RATE_MPS    = 4.0f;    // allow real depth motion without blocking normal shallow ascent/descent
    const MIN_VALID_ALT_M       = -120.0f; // reject GPS/baro altitude garbage
    const MAX_VALID_ALT_M       = 5000.0f;
    // Seawater approx: 1 m depth ≈ 10050 Pa over surface pressure
    const PA_PER_METER_SEAWATER = 10050.0f;
    const DEFAULT_SURFACE_PA    = 101325.0f;
    const MIN_PHYS_PRESSURE_PA  = 50000.0f;
    const MAX_PHYS_PRESSURE_PA  = 400000.0f;

    // Depth-state hysteresis (prevents instant start->stop at the surface)
    var depthStartMs = 0;
    var shallowSampleCount = 0;
    var depthStartConfidence = 0;
    var depthStopConfidence = 0;
    const MIN_TRACK_DURATION_MS = 3000;
    const SHALLOW_SAMPLES_TO_STOP = 5;
    const START_CONFIDENCE_THRESHOLD = 1;
    const STOP_CONFIDENCE_THRESHOLD = 2;

    // Additional health data
    var spo2 = 0;                          // NEW - pulse oximetry, %
    var ambientTempC = 0.0f;                // NEW - ambient/water temperature

    // Session-summary tracking (written once at stopSession())
    var maxDepthSeen = 0.0f;                // NEW
    var depthTrackingTimeMs = 0;            // time spent in active depth tracking
    var maxN2LoadSeen = 0.0f;               // NEW

    // FIT field IDs
    // FIT developer field IDs must be unique 0–255.
    // Instinct-class devices only allow ~16 developer fields total – keep ≤14.
    const FIELD_DR_EAST    = 0;
    const FIELD_DR_NORTH   = 1;
    const FIELD_DEPTH      = 2;
    const FIELD_SPEED_EST  = 3;
    const FIELD_HEADING    = 4;
    const FIELD_DEPTH_ACTIVE = 5;
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
    const FIELD_TRACK_TIME = 24;
    const FIELD_MAX_N2     = 25;
    const FIELD_POI_EAST   = 26;
    const FIELD_POI_NORTH  = 27;
    const FIELD_DR_DIAG    = 28;

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
    var depthActiveField = null as FitContributor.Field or Null;
    var gpsFixField = null as FitContributor.Field or Null;
    var headingField = null as FitContributor.Field or Null;
    var movingField = null as FitContributor.Field or Null;
    var hrField = null as FitContributor.Field or Null;          // NEW
    var ascentField = null as FitContributor.Field or Null;      // NEW
    var spo2Field = null as FitContributor.Field or Null;        // NEW
    var tempField = null as FitContributor.Field or Null;        // NEW

    // Session-level summary fields (written once, not per-record)
    var maxDepthField = null as FitContributor.Field or Null;    // NEW
    var trackTimeField = null as FitContributor.Field or Null;   // NEW
    var maxN2Field = null as FitContributor.Field or Null;       // NEW

    // POI marker fields (written once per mark into the record stream)
    var poiIdField = null as FitContributor.Field or Null;
    var poiLatField = null as FitContributor.Field or Null;
    var poiLonField = null as FitContributor.Field or Null;
    var poiEastField = null as FitContributor.Field or Null;
    var poiNorthField = null as FitContributor.Field or Null;
    var drDiagField = null as FitContributor.Field or Null;

    var poiCount = 0;
    var poiFlashMs = 0;           // UI: show "POI #n" briefly after mark
    var poiNoticeText = null as String or Null;
    var poiNoticeStartMs = 0;
    const POI_FLASH_MS = 2000;
    const POI_NOTICE_MS = 1600;
    var drDiagFitEnabled = true;

    var traceLogKey = null as String or Null;
    var traceLogText = null as String or Null;
    var traceLogLineCount = 0;
    const MAX_TRACE_LOG_LINES = 80;
    const MAX_TRACE_LOG_BYTES = 12000;

    var surfaceAltitudeSum = 0.0f;
    var surfaceAltitude = 0.0f;
    var surfacePressurePa = 101325.0f;
    var surfacePressureSum = 0.0f;
    var pressureCalibrationSamples = 0;
    var altitudeCalibrationSamples = 0;
    var depthFilter = 0.0f;
    var calibrationSamples = 0;
    const CALIBRATION_COUNT = 20;   // a bit longer for a stable surface reference
    var currentDepth = 0.0f;
    var depthSourceTag = "NONE";
    var uiPressureRaw = null as Float or Null;
    var uiPressurePa = null as Float or Null;
    var uiPressureUnitTag = "--";
    var lastDepthDiagLogMs = 0;
    var lastAltSample = null as Float or Null;
    var flatAltSampleCount = 0;
    var simulatedDepthM = 0.0f;
    var lastDepthUpdateMs = 0;
    var lastSurfacePressureRecalMs = 0;
    var usePressureDepth = false;   // true once we have a pressure-based surface cal
    const SURFACE_PRESSURE_RECAL_INTERVAL_MS = 180000;
    const PRESSURE_DEPTH_WEIGHT = 0.95f;
    const ALT_DEPTH_WEIGHT = 0.05f;
    const ALT_DEPTH_BLEND_FULL_DIFF_M = 2.0f;
    const ALT_DEPTH_BLEND_OFF_DIFF_M = 6.0f;
    const SIM_DEPTH_ENABLE = true;
    const SIM_DEPTH_MIN_FLAT_SAMPLES = 8;
    const SIM_DEPTH_ALT_EPSILON_M = 0.02f;
    const SIM_DEPTH_MAX_M = 2.5f;
    const SIM_DEPTH_RISE_GAIN = 0.20f;
    const SIM_DEPTH_FALL_GAIN = 0.28f;

    var motionScoreMg = 0.0f;
    var motionBaselineMg = 0.0f;
    var motionBaselineReady = false;
    var isMotionDetected = false;
    var sensorListenerActive = false;
    var biometricMotionBoost = 0.0f;
    var biometricHrBaseline = 0;
    var biometricSpo2Baseline = 0.0f;
    var biometricBaselineReady = false;

    const TIMER_PERIOD_MS = 500;
    const SENSOR_PERIOD_SEC = 1;
    const SENSOR_SAMPLE_RATE_HZ = 10;

    const GPS_ZERO_SPEED_MPS = 0.20f;
    const MIN_VALID_GPS_SPEED_MPS = 0.35f;
    const DR_MOVE_SPEED_THRESHOLD_MPS = 0.12f;
    const KF_MOTION_MIN_SPEED_MPS = 0.03f;
    const GPS_LOSS_DAMPING_FACTOR = 0.35f;
    const MIN_SENSOR_MOTION_MG = 20.0f;
    const MIN_SENSOR_CONFIDENCE = 6;
    const MIN_HEADING_CONFIDENCE_FOR_DR = 0.60f;

    // Continuous motion→speed mapping (replaces coarse step buckets)
    const MIN_MOTION_SWIM_MG = 24.0f;
    const MAX_MOTION_SWIM_MG = 90.0f;
    const MIN_SWIM_SPEED_MPS = 0.12f;
    const MAX_SWIM_SPEED_MPS = 0.50f;

    const MIN_MOTION_LAND_MG = 28.0f;
    const MAX_MOTION_LAND_MG = 120.0f;
    const MIN_LAND_SPEED_MPS = 0.15f;
    const MAX_LAND_SPEED_MPS = 0.90f;

    const SPEED_SMOOTH_RISE = 0.25f;   // respond faster when accelerating
    const SPEED_SMOOTH_FALL = 0.12f;   // decay slower when stopping

    const MOTION_FILTER_ALPHA = 0.55f; // slightly more responsive motion score

    var filteredSpeedEst = 0.0f;       // smoothed output of getEstimatedSpeedMps
    var kfDerivedSpeedMps = 0.0f;
    var prevKfEast = null as Float or Null;
    var prevKfNorth = null as Float or Null;

    var lastFitEast = null as Float or Null;
    var lastFitNorth = null as Float or Null;
    var lastFitDepth = null as Float or Null;
    var lastFitMotion = null as Float or Null;
    var lastFitSpeedEst = null as Float or Null;
    var lastFitDepthActive = null as Number or Null;
    var lastFitGpsFix = null as Number or Null;
    var lastFitHeading = null as Float or Null;
    var lastFitMoving = null as Number or Null;
    var lastFitDrDiag = null as Number or Null;
    var lastFitHr = null as Number or Null;          // NEW
    var lastFitAscent = null as Float or Null;       // NEW
    var lastFitSpo2 = null as Number or Null;        // NEW
    var lastFitTemp = null as Float or Null;         // NEW

    const MAX_DR_DIAG_LOGS = 120;
    var drDiagCount = 0;

    var scrollY = 0;
    const SCROLL_STEP = 20;
    const SCROLL_MIN = -180;
    const SCROLL_MAX = 0;

    // Match the Instinct 2X layout1 SVG: top-left alert area, top-right GPS block,
    // and a lower content region for system readings.
    const LAYOUT_TOP_LEFT_X = 6;
    const LAYOUT_TOP_LEFT_Y = 8;
    const LAYOUT_TOP_LEFT_W = 108;
    const LAYOUT_TOP_LEFT_H = 71;
    const LAYOUT_TOP_RIGHT_X = 118;
    const LAYOUT_TOP_RIGHT_Y = 10;
    const LAYOUT_TOP_RIGHT_W = 52;
    const LAYOUT_TOP_RIGHT_H = 52;
    const LAYOUT_CONTENT_TOP = 76;
    const LAYOUT_CONTENT_LEFT = 8;
    const LAYOUT_CUTOUT_CENTER_X = 144;
    const LAYOUT_CUTOUT_CENTER_Y = 31;
    const LAYOUT_CUTOUT_RADIUS = 31;

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

    const MOTION_ON_MG         = 24.0f;
    const MOTION_OFF_MG        = 12.0f;
    const CONF_RISE            = 12;      // require sustained motion before declaring moving
    const CONF_FALL            = 20;      // require sustained low motion before declaring stationary

    function initialize() {
        View.initialize();
        try {
            dr = new DeadReckoning();
            kalman = new KalmanDR();
            if (dr != null) {
                dr.setContext(isDepthActive);
            }
            n2Model = new NitrogenModel();
        } catch (e) {
            logDebug("Init failed: " + errorToString(e));
        }
    }

    function onLayout(dc as Dc) as Void {
        try {
            setLayout(Rez.Layouts.MainLayout(dc));
        } catch (e) {
            logDebug("Layout error: " + errorToString(e));
        }
    }

    function onShow() as Void {
        try {
            logDebug("=== DR Tracker Started ===");
            resetDepthCalibration();
            resetMotionState();
            resetHeadingEstimate();
            movingConfidence = 0;
            fitWriteTick = 0;
            drDiagCount = 0;
            lastDrGpsCorrectionMs = 0;
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
            logDebug("onShow error: " + errorToString(e));
        }
    }

    function onHide() as Void {
        try {
            logDebug("=== HIDING VIEW ===");
            if (drDiagCount > 0) {
                logDebug("DRDIAG summary: logged=" + drDiagCount);
            }
            stopTimerOnly();
            stopMotionListener();
            stopGps();
        } catch (e) {
            logDebug("onHide error: " + errorToString(e));
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
        gyroBiasStationarySamples = 0;
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
        logDebug("Calibration complete");
    }

    function openTraceLogFile() as Void {
        try {
            closeTraceLogFile();

            var now = Time.now();
            var info = Gregorian.info(now, Time.FORMAT_SHORT);
            var stamp = Lang.format("$1$-$2$-$3$-$4$-$5$-$6$", [
                info.year.format("%04d"),
                info.month.format("%02d"),
                info.day.format("%02d"),
                info.hour.format("%02d"),
                info.min.format("%02d"),
                info.sec.format("%02d")
            ]);

            traceLogKey = "trace_log_" + stamp;
            traceLogText = "time_ms,gpsUsable,headingConf,motionScore,estSpeed,stepEast,stepNorth,depthM,heartRate,spo2\n";
            traceLogLineCount = 1;
            Application.Storage.setValue(traceLogKey, traceLogText);
            logDebug("Trace log started: " + traceLogKey);
        } catch (e) {
            logDebug("openTraceLogFile error: " + errorToString(e));
            traceLogKey = null;
            traceLogText = null;
            traceLogLineCount = 0;
        }
    }

    function closeTraceLogFile() as Void {
        if (traceLogKey != null) {
            if (traceLogText != null) {
                Application.Storage.setValue(traceLogKey, traceLogText);
            }
            traceLogKey = null;
            traceLogText = null;
            traceLogLineCount = 0;
        }
    }

    function writeTraceLogLine(line as String) as Void {
        if (traceLogKey == null || traceLogText == null || line == null || line.length() == 0) {
            return;
        }

        if (traceLogLineCount >= MAX_TRACE_LOG_LINES) {
            return;
        }

        try {
            var lineText = line + "\n";
            if (lineText.length() >= MAX_TRACE_LOG_BYTES) {
                lineText = "[truncated]\n";
            }

            traceLogText = lineText;
            traceLogLineCount += 1;
            Application.Storage.setValue(traceLogKey, traceLogText);
        } catch (e) {
            traceLogText = null;
        }
    }

    function logDrDiagnostics(
        nowMs as Number,
        gpsUsable as Boolean,
        headingConf as Float,
        motionScore as Float,
        estSpeed as Float,
        stepEast as Float,
        stepNorth as Float,
        depthM as Float
    ) as Void {
        if (drDiagCount >= MAX_DR_DIAG_LOGS) {
            return;
        }

        drDiagCount += 1;

        var line = Lang.format("$1$,$2$,$3$,$4$,$5$,$6$,$7$,$8$,$9$,$10$", [
            nowMs,
            (gpsUsable ? 1 : 0),
            headingConf.format("%.2f"),
            motionScore.format("%.1f"),
            estSpeed.format("%.3f"),
            stepEast.format("%.3f"),
            stepNorth.format("%.3f"),
            depthM.format("%.2f"),
            heartRate,
            spo2
        ]);

        logDebug(
            "DRDIAG #" + drDiagCount +
            " t=" + nowMs +
            " gps=" + (gpsUsable ? 1 : 0) +
            " hConf=" + headingConf.format("%.2f") +
            " motion=" + motionScore.format("%.1f") +
            " gyr=" + gyroZ.format("%.3f") +
            " speed=" + estSpeed.format("%.3f") +
            " step=" + stepEast.format("%.3f") + "," + stepNorth.format("%.3f") +
            " depth=" + depthM.format("%.2f") +
            " hr=" + heartRate +
            " spo2=" + spo2
        );
        writeTraceLogLine(line);
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
            updateDepth(sensorInfo, posInfo);
            updateGPS(sensorInfo, posInfo);
            processDepthState();
            updateMotionConfidence();

            // Ascent rate (positive = ascending)
            currentAscentRateMps = 0.0f;
            if (dt > 0.0f) {
                currentAscentRateMps = (lastDepthForAscent - currentDepth) / dt;
            }
            lastDepthForAscent = currentDepth;

            if (n2Model != null) {
                n2Model.update(currentDepth, dt, isDepthActive, currentAscentRateMps);
            }

            // Track session-summary values while recording
            if (isRecording) {
                if (currentDepth > maxDepthSeen) {
                    maxDepthSeen = currentDepth;
                }
                if (isDepthActive) {
                    depthTrackingTimeMs += (dt * 1000.0f).toNumber();
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
                var headingConfidence = 0.0f;
                var effectiveHeading = null as Float or Null;

                if (isStationary()) {
                    estSpeed = 0.0f;
                }

                var headingQuality = getHeadingConfidenceForDr();
                if (headingQuality >= MIN_HEADING_CONFIDENCE_FOR_DR) {
                    effectiveHeading = bestHeading;
                    headingConfidence = headingQuality;
                }

                var hasUsableGps = hasGpsFix && isGpsQualityUsable(gpsQuality) && !isGpsRecoveryHoldActive();
                var gpsSignalLost = !hasUsableGps && (gpsFixLostAtMs > 0 || !hasGpsFix);
                var drFallbackActive = !hasUsableGps && (!hasGpsFix || gpsSignalLost);

                var drFusion = updateDrAndKalmanFusion(
                    nowMs,
                    dt,
                    effectiveHeading,
                    estSpeed,
                    headingConfidence,
                    motionScoreMg,
                    hasUsableGps,
                    gpsSignalLost,
                    drFallbackActive
                );
                var drSpeed = drFusion.get(:drSpeed) as Float;
                var drHeadingConfidence = drFusion.get(:drHeadingConfidence) as Float;

                if (kalman != null && dt > 0.0f) {
                    var kfEastNow = kalman.getEast();
                    var kfNorthNow = kalman.getNorth();
                    if (isFiniteValue(kfEastNow) && isFiniteValue(kfNorthNow)
                        && prevKfEast != null && prevKfNorth != null) {
                        var dE = kfEastNow - prevKfEast;
                        var dN = kfNorthNow - prevKfNorth;
                        var dM = Math.sqrt((dE * dE) + (dN * dN));
                        kfDerivedSpeedMps = dM / dt;
                    } else {
                        kfDerivedSpeedMps = 0.0f;
                    }
                    prevKfEast = kfEastNow;
                    prevKfNorth = kfNorthNow;
                } else {
                    kfDerivedSpeedMps = 0.0f;
                    prevKfEast = null;
                    prevKfNorth = null;
                }

                if (gpsSignalLost) {
                    var diagStepEast = 0.0f;
                    var diagStepNorth = 0.0f;
                    if (dr != null) {
                        diagStepEast = dr.lastAcceptedDx;
                        diagStepNorth = dr.lastAcceptedDy;
                    }
                    logDrDiagnostics(nowMs, false, drHeadingConfidence, motionScoreMg, drSpeed, diagStepEast, diagStepNorth, currentDepth);
                }

                fitWriteTick += 1;
                if (fitWriteTick >= 2) {
                    fitWriteTick = 0;
                    writeFitFieldsIfNeeded(estSpeed, bestHeading);
                }
            }
        } catch (e) {
            logDebug("CRITICAL Timer Error: " + errorToString(e));
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
            logDebug("GPS continuous enabled");
        } catch (e) {
            gpsActive = false;
            logDebug("startGps error: " + errorToString(e));
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
        logDebug("GPS disabled");
    }

    function getPositionQuality(info as Position.Info or Null) as Number or Null {
        try {
            return info != null ? info.accuracy : null;
        } catch (e) {
            return null;
        }
    }

    function isGpsFreshEnough() as Boolean {
        if (lastGpsEventMs <= 0) {
            return false;
        }
        return (System.getTimer() - lastGpsEventMs) <= GPS_FIX_MAX_AGE_MS;
    }

    function onPosition(info as Position.Info) as Void {
        try {
            lastGpsEventMs = System.getTimer();
            updateGpsState(info, true);
        } catch (e) {
            logDebug("onPosition error: " + errorToString(e));
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
                },
                :gyroscope => {
                    :enabled => true,
                    :sampleRate => sampleRate
                },
                :magnetometer => {
                    :enabled => true,
                    :sampleRate => sampleRate
                }
            };

            Sensor.registerSensorDataListener(method(:sensorDataCallback), options);
            sensorListenerActive = true;
        } catch (e) {
            sensorListenerActive = false;
            logDebug("startMotionListener error: " + errorToString(e));
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

        if (mag > 50.0f) {
            mag *= 0.001f;
        }

        // High-pass filter (removes gravity)
        var hp = mag - lastAccelMag;
        lastAccelMag = (1.0f - MOTION_HP_ALPHA) * lastAccelMag + MOTION_HP_ALPHA * mag;

        // Exponential variance of the high-pass signal
        motionVar = (1.0f - MOTION_VAR_ALPHA) * motionVar
                + MOTION_VAR_ALPHA * (hp * hp);
    }

    function updateMotionState() as Void {
        var onTh  = isDepthActive ? 18.0f : MOTION_ON_MG;
        var offTh = isDepthActive ?  8.0f : MOTION_OFF_MG;

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
            if (sensorData has :accelerometerData && sensorData.accelerometerData != null) {
                var accData = sensorData.accelerometerData;

                try {
                    // Prefer the raw samples if available (better than power). Some devices
                    // can return a scalar / stripped payload in this callback, so guard every
                    // .size() and index access before we touch it.
                    if (accData has :x && accData.x != null) {
                        var xSamples = accData.x;
                        var ySamples = (accData has :y && accData.y != null) ? accData.y : null;
                        var zSamples = (accData has :z && accData.z != null) ? accData.z : null;
                        var count = xSamples.size();
                        var yCount = (ySamples != null) ? ySamples.size() : 0;
                        var zCount = (zSamples != null) ? zSamples.size() : 0;
                        if (count > 0) {
                            var i = 0;
                            while (i < count) {
                                var xVal = xSamples[i];
                                var ax = (xVal != null) ? xVal.toFloat() : 0.0f;

                                var ay = 0.0f;
                                if (ySamples != null && i < yCount && ySamples[i] != null) {
                                    ay = ySamples[i].toFloat();
                                }

                                var az = 0.0f;
                                if (zSamples != null && i < zCount && zSamples[i] != null) {
                                    az = zSamples[i].toFloat();
                                }

                                updateMotionFromAccel(ax, ay, az);
                                i += 1;
                            }
                        }
                    }
                    // Fallback to power if raw axes are not present.
                    else if (accData has :power && accData.power != null) {
                        var p = accData.power;
                        var count = p.size();
                        if (count > 0) {
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
                            if (validCount > 0) {
                                var avgPower = sumPower / validCount.toFloat();
                                updateMotionFromAccel(avgPower, 0.0f, 0.0f);
                            }
                        }
                    }
                } catch (e) {
                    logDebug("accelerometer payload parse error: " + errorToString(e));
                }
            }

            if (sensorData has :gyroscopeData && sensorData.gyroscopeData != null) {
                try {
                    var gyroData = sensorData.gyroscopeData;
                    if (gyroData has :x && gyroData.x != null) {
                        var xSamples = gyroData.x;
                        var ySamples = (gyroData has :y && gyroData.y != null) ? gyroData.y : null;
                        var zSamples = (gyroData has :z && gyroData.z != null) ? gyroData.z : null;
                        var count = xSamples.size();
                        var yCount = (ySamples != null) ? ySamples.size() : 0;
                        var zCount = (zSamples != null) ? zSamples.size() : 0;
                        if (count > 0) {
                            var i = 0;
                            while (i < count) {
                                var gx = xSamples[i];
                                gyroX = (gx != null) ? gx.toFloat() : 0.0f;

                                gyroY = 0.0f;
                                if (ySamples != null && i < yCount && ySamples[i] != null) {
                                    gyroY = ySamples[i].toFloat();
                                }

                                gyroZ = 0.0f;
                                if (zSamples != null && i < zCount && zSamples[i] != null) {
                                    gyroZ = zSamples[i].toFloat();
                                }
                                i += 1;
                            }
                        }
                    }
                } catch (e) {
                    logDebug("gyroscope payload parse error: " + errorToString(e));
                }
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
            logDebug("sensorDataCallback error: " + errorToString(e));
        }
    }

    function isStationary() as Boolean {
        if (speed >= MIN_VALID_GPS_SPEED_MPS) {
            return false;
        }
        if (kfDerivedSpeedMps >= KF_MOTION_MIN_SPEED_MPS) {
            return false;
        }
        var gyroMag = Math.sqrt(gyroX * gyroX + gyroY * gyroY + gyroZ * gyroZ);
        if (gyroMag > STATIONARY_GYRO_MAG_RAD_S) {
            return false;
        }
        return !isMotionDetected;
    }

    function clampFloat(value as Float, minValue as Float, maxValue as Float) as Float {
        if (value < minValue) {
            return minValue;
        }
        if (value > maxValue) {
            return maxValue;
        }
        return value;
    }

    function absFloat(value as Float) as Float {
        if (value < 0.0f) {
            return -value;
        }
        return value;
    }

    function isProbablyMoving() as Boolean {
        if (speed >= MIN_VALID_GPS_SPEED_MPS) {
            return true;
        }
        if (kfDerivedSpeedMps >= KF_MOTION_MIN_SPEED_MPS) {
            return true;
        }
        return isMotionDetected;
    }

    function updateBiometricMovementEvidence() as Void {
        var boost = 0.0f;

        if (heartRate > 0) {
            if (!biometricBaselineReady) {
                biometricHrBaseline = heartRate;
                biometricSpo2Baseline = (spo2 > 0) ? spo2.toFloat() : 100.0f;
                biometricBaselineReady = true;
                return;
            }

            var hrDelta = heartRate - biometricHrBaseline;
            if (hrDelta >= 12) {
                boost += 1.0f;
            }
            if (hrDelta >= 20) {
                boost += 1.0f;
            }
            if (heartRate >= 100) {
                boost += 0.5f;
            }
        }

        if (spo2 > 0 && biometricBaselineReady && biometricSpo2Baseline > 0.0f) {
            var spo2Drop = biometricSpo2Baseline - spo2.toFloat();
            if (spo2Drop >= 4.0f) {
                boost += 0.5f;
            }
            if (spo2Drop >= 8.0f) {
                boost += 0.5f;
            }
        }

        if (boost > 0.0f) {
            biometricMotionBoost = (biometricMotionBoost * 0.65f) + (boost * 0.35f);
        } else {
            biometricMotionBoost = biometricMotionBoost * 0.80f;
            if (biometricMotionBoost < 0.05f) {
                biometricMotionBoost = 0.0f;
            }
        }
    }

    function updateMotionConfidence() as Void {
        updateBiometricMovementEvidence();

        var evidence = 0;
        if (isProbablyMoving()) {
            evidence += 1;
        }
        if (kfDerivedSpeedMps >= KF_MOTION_MIN_SPEED_MPS) {
            evidence += 1;
        }
        if (biometricMotionBoost >= 1.0f) {
            evidence += 1;
        }

        if (evidence > 0) {
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
        kfDerivedSpeedMps   = 0.0f;
        prevKfEast          = null;
        prevKfNorth         = null;
        biometricMotionBoost = 0.0f;
        biometricHrBaseline = 0;
        biometricSpo2Baseline = 0.0f;
        biometricBaselineReady = false;
        depthStartConfidence = 0;
        depthStopConfidence = 0;
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
        if (q == Position.QUALITY_NOT_AVAILABLE) {
            return false;
        }

        if (q == Position.QUALITY_GOOD
            || q == Position.QUALITY_USABLE
            || q == Position.QUALITY_POOR) {
            return true;
        }

        // Some Garmin APIs report a meter-based accuracy value instead of the enum.
        // Only accept a realistic fix quality range; reject stale/invalid positions.
        if (q > 0.0 && q <= 50.0) {
            return true;
        }

        return false;
    }

    function readSensors(info as Sensor.Info or Null) as Void {
        try {
            if (info == null) {
                return;
            }

            var stats = System.getSystemStats();

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

            // Solar intensity (UI-only, not a FIT field; keeps active field count at 15)
            if (stats != null && stats.solarIntensity != null) {
                solarLux = stats.solarIntensity.toFloat();
            } else if (info has :light && info.light != null) {
                solarLux = info.light.toFloat();
            } else {
                solarLux = 0.0f;
            }

            if (info has :accel) {
                var accelArray = info.accel as Array<Number>;
                if (accelArray != null && accelArray.size() >= 3) {
                    accelX = accelArray[0].toFloat();
                    accelY = accelArray[1].toFloat();
                    accelZ = accelArray[2].toFloat();
                } else {
                    accelX = 0.0f;
                    accelY = 0.0f;
                    accelZ = 0.0f;
                }
            } else {
                accelX = 0.0f;
                accelY = 0.0f;
                accelZ = 0.0f;
            }

            if (info has :gyro) {
                var gyroArray = info.gyro as Array<Number>;
                if (gyroArray != null && gyroArray.size() >= 3) {
                    gyroX = gyroArray[0].toFloat();
                    gyroY = gyroArray[1].toFloat();
                    gyroZ = gyroArray[2].toFloat();

                    if (calibrationActive) {
                        gyroBiasX += gyroX;
                        gyroBiasY += gyroY;
                        gyroBiasZ += gyroZ;
                        gyroCalSamples += 1;
                    } else {
                        if (isStationary() && gyroBiasStationarySamples < 20) {
                            gyroBiasX = (gyroBiasX * 0.90f) + (gyroX * 0.10f);
                            gyroBiasY = (gyroBiasY * 0.90f) + (gyroY * 0.10f);
                            gyroBiasZ = (gyroBiasZ * 0.90f) + (gyroZ * 0.10f);
                            gyroBiasStationarySamples += 1;
                        }
                        gyroX -= gyroBiasX;
                        gyroY -= gyroBiasY;
                        gyroZ -= gyroBiasZ;
                    }
                } else {
                    gyroX = 0.0f;
                    gyroY = 0.0f;
                    gyroZ = 0.0f;
                }
            } else {
                gyroX = 0.0f;
                gyroY = 0.0f;
                gyroZ = 0.0f;
            }

            trueHeading = null;
            magHeading = null;

            if (info has :heading && info.heading != null) {
                trueHeading = normalizeHeadingInput(info.heading.toFloat());
                headingEstimate = trueHeading;
                hasHeadingEstimate = true;
            }

            if (info has :mag && info.mag != null && info.mag.size() >= 3) {
                var mx = info.mag[0].toFloat();
                var my = info.mag[1].toFloat();
                var mz = info.mag[2].toFloat();
                lastMagX = mx;
                lastMagY = my;
                lastMagZ = mz;

                if (calibrationActive) {
                    magBiasX += mx;
                    magBiasY += my;
                    magBiasZ += mz;
                    magCalSamples += 1;
                } else if (trueHeading == null) {
                    mx -= magBiasX;
                    my -= magBiasY;
                    mz -= magBiasZ;
                    var magFieldMag = Math.sqrt((mx * mx) + (my * my) + (mz * mz));
                    var magDistortion = absFloat(magFieldMag - MAG_FIELD_EXPECTED_UT);
                    var magConfidence = 1.0f;
                    if (magDistortion > MAG_FIELD_DISTORTION_TOL_UT) {
                        magConfidence = clampFloat(1.0f - ((magDistortion - MAG_FIELD_DISTORTION_TOL_UT) / 30.0f), MAG_HEADING_MIN_CONFIDENCE, 1.0f);
                    }
                    magHeading = normalizeAngleRad(Math.atan2(my, mx));
                    if (magConfidence < 0.95f) {
                        headingEstimate = normalizeAngleRad((headingEstimate * 0.5f) + (magHeading * 0.5f));
                    }
                }
            }
        } catch (e) {
            logDebug("readSensors error: " + errorToString(e));
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

        if (!hasGpsFix) {
            if (dr != null && dr.hasValidHeading()) {
                return dr.getHeadingRad();
            }
            return null;
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

    function normalizeHeadingInput(value as Float) as Float {
        var normalized = value;
        if (normalized > (2.0f * Math.PI) && normalized <= 360.0f) {
            normalized = normalized * (Math.PI / 180.0f);
        }
        return normalizeAngleRad(normalized);
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

    function normalizePressureToPa(rawPressure as Float) as Float {
        var p = rawPressure;

        // Common watch/profile pressure units observed across devices:
        // Pa (~101325), hPa/mbar (~1013), kPa (~101), deci-hPa (~10132),
        // and occasionally normalized atmosphere/bar (~1.0).
        if (p > 0.7f && p < 1.4f) {
            p *= DEFAULT_SURFACE_PA;       // atm or bar-like normalized value
        } else if (p >= 80.0f && p < 120.0f) {
            p *= 1000.0f;                  // kPa -> Pa
        } else if (p >= 800.0f && p < 1200.0f) {
            p *= 100.0f;                   // hPa/mbar -> Pa
        } else if (p >= 8000.0f && p < 12000.0f) {
            p *= 10.0f;                    // deci-hPa -> Pa
        }

        return p;
    }

    function detectPressureUnitTag(rawPressure as Float) as String {
        if (rawPressure > 0.7f && rawPressure < 1.4f) {
            return "ATM";
        } else if (rawPressure >= 80.0f && rawPressure < 120.0f) {
            return "KPA";
        } else if (rawPressure >= 800.0f && rawPressure < 1200.0f) {
            return "HPA";
        } else if (rawPressure >= 8000.0f && rawPressure < 12000.0f) {
            return "DHPA";
        }
        return "PA";
    }

    function updateDepth(info as Sensor.Info or Null, posInfo as Position.Info or Null) as Void {
        try {
            depthSourceTag = "NONE";
            uiPressureRaw = null;
            uiPressurePa = null;
            uiPressureUnitTag = "--";

            if (info == null && posInfo == null) {
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
            // Some devices report pressure as ambientPressure and/or in hPa or kPa,
            // so normalize to Pa before applying the depth model.
            var pressureReading = null as Float or Null;
            if (info != null && (info has :pressure) && (info.pressure != null)) {
                pressureReading = info.pressure.toFloat();
            } else if (info != null && (info has :ambientPressure) && (info.ambientPressure != null)) {
                pressureReading = info.ambientPressure.toFloat();
            }

            var hasPressure = pressureReading != null;
            var pressurePa = 0.0f;
            var pressureRaw = 0.0f;
            if (hasPressure) {
                pressureRaw = pressureReading;
                pressurePa = normalizePressureToPa(pressureRaw);
                uiPressureRaw = pressureRaw;
                uiPressurePa = pressurePa;
                uiPressureUnitTag = detectPressureUnitTag(pressureRaw);

                if (pressurePa >= MIN_PHYS_PRESSURE_PA && pressurePa <= MAX_PHYS_PRESSURE_PA) {
                    depthSourceTag = "P";
                } else {
                    uiPressureUnitTag = uiPressureUnitTag + "!";
                    // Ignore pressure samples that cannot represent absolute ambient pressure.
                    hasPressure = false;
                    pressurePa = 0.0f;
                }
            }

            // Some device profiles expose direct depth instead of pressure.
            var directDepth = null as Float or Null;
            if (info != null && (info has :depth) && (info.depth != null)) {
                directDepth = info.depth.toFloat();
            } else if (info != null && (info has :enhancedDepth) && (info.enhancedDepth != null)) {
                directDepth = info.enhancedDepth.toFloat();
            }
            if (directDepth != null) {
                depthSourceTag = "D";
                if (directDepth < 0.0f) {
                    directDepth = 0.0f;
                } else if (directDepth > MAX_DEPTH_M) {
                    directDepth = MAX_DEPTH_M;
                }
            }

            var hasAlt = false;
            var rawAlt = 0.0f;
            if (info != null && (info has :altitude) && (info.altitude != null)) {
                rawAlt = info.altitude.toFloat();
                hasAlt = true;
                if (depthSourceTag.equals("NONE")) {
                    depthSourceTag = "ALT";
                }
            } else if (info != null && (info has :enhancedAltitude) && (info.enhancedAltitude != null)) {
                rawAlt = info.enhancedAltitude.toFloat();
                hasAlt = true;
                if (depthSourceTag.equals("NONE")) {
                    depthSourceTag = "ALT";
                }
            } else if (posInfo != null && (posInfo has :altitude) && (posInfo.altitude != null)) {
                // Simulator profiles often expose altitude on position samples rather than Sensor.Info.
                rawAlt = posInfo.altitude.toFloat();
                hasAlt = true;
                if (depthSourceTag.equals("NONE")) {
                    depthSourceTag = "GPS_ALT";
                }
            }
            var altValid = hasAlt && rawAlt >= MIN_VALID_ALT_M && rawAlt <= MAX_VALID_ALT_M;
            if (altValid) {
                if (lastAltSample != null && absFloat(rawAlt - lastAltSample) <= SIM_DEPTH_ALT_EPSILON_M) {
                    flatAltSampleCount += 1;
                } else {
                    flatAltSampleCount = 0;
                }
                lastAltSample = rawAlt;
            } else {
                lastAltSample = null;
                flatAltSampleCount = 0;
            }

            // ---------- Initial surface calibration ----------
            if (calibrationSamples < CALIBRATION_COUNT) {
                var plausibleSurfacePressure = hasPressure
                    && pressurePa >= MIN_SURFACE_PRESSURE_PA
                    && pressurePa <= MAX_SURFACE_PRESSURE_PA;

                if (plausibleSurfacePressure) {
                    // Only use a genuine surface sample as the baseline. If the watch is
                    // already underwater, or the sensor is noisy, a single pressure sample
                    // should not flatten the whole depth estimate toward 0.1–0.2 m.
                    if (pressureCalibrationSamples == 0 || !usePressureDepth) {
                        surfacePressurePa = pressurePa;
                        usePressureDepth = true;
                    }
                    surfacePressureSum += pressurePa;
                    pressureCalibrationSamples += 1;
                }
                if (altValid) {
                    surfaceAltitudeSum += rawAlt;
                    altitudeCalibrationSamples += 1;
                }
                calibrationSamples += 1;

                if (calibrationSamples == CALIBRATION_COUNT) {
                    var minCalSamples = (CALIBRATION_COUNT / 2).toNumber();

                    if (usePressureDepth && pressureCalibrationSamples >= minCalSamples && surfacePressureSum > 0.0f) {
                        surfacePressurePa = surfacePressureSum / pressureCalibrationSamples.toFloat();
                    } else if (pressureCalibrationSamples > 0 && surfacePressureSum > 0.0f) {
                        surfacePressurePa = surfacePressureSum / pressureCalibrationSamples.toFloat();
                    } else {
                        usePressureDepth = false;
                        surfacePressurePa = DEFAULT_SURFACE_PA;
                    }
                    if (altitudeCalibrationSamples > 0) {
                        surfaceAltitude = surfaceAltitudeSum / altitudeCalibrationSamples.toFloat();
                    }
                    depthFilter = 0.0f;
                    logDebug("Depth cal done: P0=" + surfacePressurePa.format("%.0f")
                        + " Pa  alt0=" + surfaceAltitude.format("%.1f")
                        + " useP=" + usePressureDepth
                        + " pCal=" + pressureCalibrationSamples
                        + " aCal=" + altitudeCalibrationSamples);
                }
                if (directDepth != null) {
                    currentDepth = directDepth;
                    depthFilter = directDepth;
                    return;
                }
                // If we already have a valid initial pressure baseline, keep the live depth
                // estimate running instead of returning zero during the warm-up window.
                if (hasPressure && pressurePa > 50000.0f) {
                    if (usePressureDepth) {
                        currentDepth = (pressurePa - surfacePressurePa) / PA_PER_METER_SEAWATER;
                        if (currentDepth < 0.0f) {
                            currentDepth = 0.0f;
                        }
                        return;
                    }
                    // Use the nominal surface pressure if no true-surface calibration exists yet.
                    currentDepth = (pressurePa - DEFAULT_SURFACE_PA) / PA_PER_METER_SEAWATER;
                    if (currentDepth < 0.0f) {
                        currentDepth = 0.0f;
                    }
                    return;
                }
                currentDepth = 0.0f;
                return;
            }

            // ---------- Continuous surface recalibration (only on surface) ----------
            if (!isDepthActive && currentDepth <= DEPTH_NOISE_FLOOR_M) {
                var stationaryForRecal = (movingConfidence < MOVING_CONFIDENCE_ON) || isStationary();
                var shouldAutoRecalSurface = stationaryForRecal
                    && hasGpsFix
                    && isGpsQualityUsable(gpsQuality)
                    && (nowMs - lastSurfacePressureRecalMs) >= SURFACE_PRESSURE_RECAL_INTERVAL_MS;
                var altitudeOnlyMode = (!hasPressure) && (directDepth == null);

                if (usePressureDepth && hasPressure
                    && pressurePa > 80000.0f && pressurePa < 110000.0f) {
                    surfacePressurePa = (1.0f - SURFACE_RECAL_ALPHA) * surfacePressurePa
                                      + SURFACE_RECAL_ALPHA * pressurePa;
                    if (shouldAutoRecalSurface) {
                        lastSurfacePressureRecalMs = nowMs;
                        surfacePressurePa = (0.90f * surfacePressurePa) + (0.10f * pressurePa);
                    }
                }
                // In altitude-only mode while recording, keep a stable baseline.
                // Otherwise the baseline follows raw altitude and collapses depth to ~0.
                if (altValid && (!altitudeOnlyMode || !isRecording)) {
                    surfaceAltitude = (1.0f - SURFACE_RECAL_ALPHA) * surfaceAltitude
                                    + SURFACE_RECAL_ALPHA * rawAlt;
                }
            }

            // ---------- Raw depth ----------
            var pressureDepth = null as Float or Null;
            var altitudeDepth = null as Float or Null;

            if (directDepth != null) {
                pressureDepth = directDepth;
            }

            if (usePressureDepth && hasPressure && pressurePa > 50000.0f) {
                pressureDepth = (pressurePa - surfacePressurePa) / PA_PER_METER_SEAWATER;
                if (pressureDepth < 0.0f) {
                    pressureDepth = 0.0f;
                }
            }

            if (altValid) {
                // Some profiles report altitude with opposite sign versus depth.
                // Evaluate both directions and keep the physically plausible positive one.
                var altitudeDepthA = surfaceAltitude - rawAlt;
                if (altitudeDepthA < 0.0f) {
                    altitudeDepthA = 0.0f;
                }

                var altitudeDepthB = rawAlt - surfaceAltitude;
                if (altitudeDepthB < 0.0f) {
                    altitudeDepthB = 0.0f;
                }

                altitudeDepth = altitudeDepthA;
                if (pressureDepth == null && altitudeDepthB > altitudeDepthA) {
                    altitudeDepth = altitudeDepthB;
                }
            }

            var rawDepth = 0.0f;
            if (pressureDepth != null && altitudeDepth != null) {
                var diff = absFloat(pressureDepth - altitudeDepth);
                var altitudeBlendWeight = 0.0f;

                if (diff <= ALT_DEPTH_BLEND_FULL_DIFF_M) {
                    altitudeBlendWeight = ALT_DEPTH_WEIGHT;
                } else if (diff < ALT_DEPTH_BLEND_OFF_DIFF_M) {
                    var t = (diff - ALT_DEPTH_BLEND_FULL_DIFF_M) / (ALT_DEPTH_BLEND_OFF_DIFF_M - ALT_DEPTH_BLEND_FULL_DIFF_M);
                    altitudeBlendWeight = ALT_DEPTH_WEIGHT * (1.0f - t);
                }

                rawDepth = (pressureDepth * PRESSURE_DEPTH_WEIGHT) + (altitudeDepth * altitudeBlendWeight);
            } else if (pressureDepth != null) {
                rawDepth = pressureDepth;
            } else if (altitudeDepth != null) {
                rawDepth = altitudeDepth;
            } else {
                // No usable sensor this tick – hold previous filtered value
                return;
            }

            var altitudeOnlyMode = (!hasPressure) && (directDepth == null);
            if (SIM_DEPTH_ENABLE && altitudeOnlyMode && altValid
                && flatAltSampleCount >= SIM_DEPTH_MIN_FLAT_SAMPLES && isRecording) {
                var movingForSimDepth = (kfDerivedSpeedMps >= KF_MOTION_MIN_SPEED_MPS)
                    || (movingConfidence >= MOVING_CONFIDENCE_ON);
                if (movingForSimDepth) {
                    simulatedDepthM += (kfDerivedSpeedMps + 0.05f) * SIM_DEPTH_RISE_GAIN * dt;
                    if (simulatedDepthM > SIM_DEPTH_MAX_M) {
                        simulatedDepthM = SIM_DEPTH_MAX_M;
                    }
                } else {
                    simulatedDepthM -= SIM_DEPTH_FALL_GAIN * dt;
                    if (simulatedDepthM < 0.0f) {
                        simulatedDepthM = 0.0f;
                    }
                }

                var wobble = 0.06f * Math.sin(nowMs.toFloat() / 1200.0f);
                rawDepth = simulatedDepthM + wobble;
                if (rawDepth < 0.0f) {
                    rawDepth = 0.0f;
                }
                depthSourceTag = "SIM";
            } else if (!altitudeOnlyMode) {
                simulatedDepthM = 0.0f;
            }

            // Reject non-physical jumps (GPS altitude jumps, baro glitches)
            var maxDelta = MAX_DEPTH_RATE_MPS * dt;
            var prev = depthFilter;
            if (rawDepth - prev > maxDelta) {
                rawDepth = prev + maxDelta;
            } else if (prev - rawDepth > maxDelta) {
                rawDepth = prev - maxDelta;
            }

            // Match the Suunto-style depth bursts more closely: keep shallow samples alive,
            // react quickly to real transitions, and avoid a laggy, rounded trace near the
            // surface while still rejecting actual noise spikes.
            var depthAlpha = 0.58f;
            var depthDelta = absFloat(rawDepth - depthFilter);
            if (rawDepth <= 0.75f) {
                depthAlpha = 0.52f;
            } else if (rawDepth <= 2.0f) {
                depthAlpha = 0.42f;
            } else {
                depthAlpha = 0.28f;
            }
            if (depthDelta > 1.5f) {
                depthAlpha = 0.22f;
            }
            if (depthDelta < 0.12f) {
                depthAlpha = 0.78f;
            }
            depthFilter = (depthFilter * (1.0f - depthAlpha)) + (rawDepth * depthAlpha);

            // Noise floor: keep tiny real shallow values visible, but still reject pure noise.
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

            if (isDebugLoggingEnabled() && (nowMs - lastDepthDiagLogMs) >= 1000) {
                lastDepthDiagLogMs = nowMs;
                var rawAltText = hasAlt ? rawAlt.format("%.2f") : "NA";
                var pText = hasPressure ? pressurePa.format("%.0f") : "NA";
                var pRawText = (pressureReading != null) ? pressureRaw.format("%.2f") : "NA";
                var pDepthText = (pressureDepth != null) ? pressureDepth.format("%.2f") : "NA";
                var aDepthText = (altitudeDepth != null) ? altitudeDepth.format("%.2f") : "NA";
                logDebug("DEPTHDBG src=" + depthSourceTag
                    + " rec=" + isRecording
                    + " rawAlt=" + rawAltText
                    + " alt0=" + surfaceAltitude.format("%.2f")
                    + " pRaw=" + pRawText
                    + " pPa=" + pText
                    + " pDepth=" + pDepthText
                    + " aDepth=" + aDepthText
                    + " depth=" + currentDepth.format("%.2f"));
            }
        } catch (e) {
            logDebug("updateDepth error: " + errorToString(e));
        }
    }

    function updateGpsState(posInfo as Position.Info or Null, updateRecovery as Boolean) as Void {
        var previousFix = hasGpsFix;
        hasGpsFix = false;
        gpsQuality = -1;
        latitude = 0.0f;
        longitude = 0.0f;

        if (posInfo != null) {
            gpsQuality = getPositionQuality(posInfo);
        }

        var hasUsableSample = posInfo != null
            && posInfo.position != null
            && isGpsQualityUsable(gpsQuality);

        if (hasUsableSample) {
            var coords = posInfo.position.toDegrees();
            var lat = coords[0].toFloat();
            var lon = coords[1].toFloat();

            if (lat >= -90.0f && lat <= 90.0f && lon >= -180.0f && lon <= 180.0f
                && (lat != 0.0f || lon != 0.0f)) {
                latitude = lat;
                longitude = lon;
            }
        }

        var freshEnough = isGpsFreshEnough();
        if (freshEnough && latitude != 0.0f && longitude != 0.0f) {
            hasGpsFix = true;
        }

        if (hasGpsFix) {
            gpsFixLostAtMs = 0;
            gpsRecoveryUntilMs = System.getTimer() + GPS_LOSS_HOLD_MS;
        } else {
            if (updateRecovery && previousFix) {
                gpsFixLostAtMs = System.getTimer();
            }
            if (updateRecovery) {
                gpsRecoveryUntilMs = 0;
            }
        }
    }

    function updateGPS(sensorInfo as Sensor.Info or Null, posInfo as Position.Info or Null) as Void {
        try {
            speed = 0.0f;

            if (sensorInfo != null && sensorInfo has :speed && sensorInfo.speed != null) {
                var rawSpeed = sensorInfo.speed.toFloat();
                speed = rawSpeed < GPS_ZERO_SPEED_MPS ? 0.0f : rawSpeed;
            }

            updateGpsState(posInfo, false);
        } catch (e) {
            logDebug("updateGPS error: " + errorToString(e));
            speed = 0.0f;
            latitude = 0.0f;
            longitude = 0.0f;
            hasGpsFix = false;
            gpsQuality = -1;
        }
    }

    function isNearEntryPosition() as Boolean {
        if (!hasEntryPosition || !hasGpsFix || !isGpsQualityUsable(gpsQuality)) {
            return false;
        }

        var latRefRad = entryLat * 0.017453292519943295f;
        var metersPerDegLat = 111000.0f;
        var metersPerDegLon = 111000.0f * Math.cos(latRefRad);
        if (metersPerDegLon < 1000.0f) {
            metersPerDegLon = 1000.0f;
        }

        var eastDelta = (longitude - entryLon) * metersPerDegLon;
        var northDelta = (latitude - entryLat) * metersPerDegLat;
        var distanceM = Math.sqrt((eastDelta * eastDelta) + (northDelta * northDelta));
        return distanceM <= LAND_RETURN_RADIUS_M;
    }

    function processDepthState() as Void {
        try {
            if (!isRecording) {
                isDepthActive = false;
                shallowSampleCount = 0;
                depthStartConfidence = 0;
                depthStopConfidence = 0;
                return;
            }

            if (!isDepthActive) {
                if (currentDepth > DEPTH_START_THRESHOLD_M && currentDepth <= MAX_DEPTH_M) {
                    depthStartConfidence += 1;
                    depthStopConfidence = 0;
                    if (depthStartConfidence >= START_CONFIDENCE_THRESHOLD) {
                        isDepthActive = true;
                        depthStartMs = System.getTimer();
                        shallowSampleCount = 0;
                        depthStartConfidence = 0;
                        depthStopConfidence = 0;
                    }
                } else {
                    depthStartConfidence = 0;
                    depthStopConfidence = 0;
                }
                return;
            }

            var elapsed = System.getTimer() - depthStartMs;

            // Don't allow auto-stop until a minimum duration has passed;
            // avoids the instant start->stop loop caused by depth noise.
            if (elapsed < MIN_TRACK_DURATION_MS) {
                return;
            }

            var backOnStartingLand = isNearEntryPosition();
            var nearSurface = currentDepth <= SURFACE_STOP_DEPTH_M;

            // Only end tracking once we are shallow and back at the land position
            // where recording started and the GPS signal was captured.
            if (nearSurface && backOnStartingLand) {
                depthStopConfidence += 1;
                if (depthStopConfidence >= STOP_CONFIDENCE_THRESHOLD) {
                    isDepthActive = false;
                    shallowSampleCount = 0;
                    depthStopConfidence = 0;
                    depthStartConfidence = 0;
                }
            } else {
                depthStopConfidence = 0;
                shallowSampleCount = 0;
            }
        } catch (e) {
            logDebug("processDepthState error: " + errorToString(e));
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
                if (isStationary()) {
                    filteredSpeedEst = 0.0f;
                } else {
                    filteredSpeedEst *= 0.70f;
                    if (filteredSpeedEst < 0.05f) {
                        filteredSpeedEst = 0.0f;
                    }
                }
                return filteredSpeedEst;
            }

            if (!hasGpsFix || isGpsRecoveryHoldActive()) {
                var sensorTarget = 0.0f;
                if (isDepthActive) {
                    if (motionScoreMg <= MIN_MOTION_SWIM_MG) {
                        sensorTarget = MIN_SWIM_SPEED_MPS * 0.45f;
                    } else if (motionScoreMg >= MAX_MOTION_SWIM_MG) {
                        sensorTarget = MAX_SWIM_SPEED_MPS * 0.85f;
                    } else {
                        var n = (motionScoreMg - MIN_MOTION_SWIM_MG)
                              / (MAX_MOTION_SWIM_MG - MIN_MOTION_SWIM_MG);
                        sensorTarget = (MIN_SWIM_SPEED_MPS * 0.45f) + n * ((MAX_SWIM_SPEED_MPS * 0.85f) - (MIN_SWIM_SPEED_MPS * 0.45f));
                    }
                } else {
                    if (motionScoreMg <= MIN_MOTION_LAND_MG) {
                        sensorTarget = MIN_LAND_SPEED_MPS * 0.45f;
                    } else if (motionScoreMg >= MAX_MOTION_LAND_MG) {
                        sensorTarget = MAX_LAND_SPEED_MPS * 0.70f;
                    } else {
                        var n2 = (motionScoreMg - MIN_MOTION_LAND_MG)
                              / (MAX_MOTION_LAND_MG - MIN_MOTION_LAND_MG);
                        sensorTarget = (MIN_LAND_SPEED_MPS * 0.45f) + n2 * ((MAX_LAND_SPEED_MPS * 0.70f) - (MIN_LAND_SPEED_MPS * 0.45f));
                    }
                }

                if (movingConfidence < MOVING_CONFIDENCE_ON) {
                    sensorTarget *= 0.55f;
                } else if (movingConfidence < (MOVING_CONFIDENCE_ON + 2)) {
                    sensorTarget *= 0.80f;
                }

                if (sensorTarget > 0.0f) {
                    var a = (sensorTarget > filteredSpeedEst) ? (SPEED_SMOOTH_RISE * 0.55f) : (SPEED_SMOOTH_FALL * 0.60f);
                    filteredSpeedEst = filteredSpeedEst + a * (sensorTarget - filteredSpeedEst);
                } else {
                    filteredSpeedEst *= GPS_LOSS_DAMPING_FACTOR;
                }

                if (filteredSpeedEst < 0.03f) {
                    filteredSpeedEst = 0.0f;
                }
                return filteredSpeedEst;
            }

            // Priority 3: continuous intensity → speed map
            var target = 0.0f;
            if (isDepthActive) {
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

    function isGpsRecoveryHoldActive() as Boolean {
        if (gpsRecoveryUntilMs <= 0) {
            return false;
        }
        return System.getTimer() < gpsRecoveryUntilMs;
    }

    function getHeadingConfidenceForDr() as Float {
        if (trueHeading != null) {
            return 1.0f;
        }
        if (magHeading != null) {
            var magFieldMag = Math.sqrt((lastMagX * lastMagX) + (lastMagY * lastMagY) + (lastMagZ * lastMagZ));
            var distortion = absFloat(magFieldMag - MAG_FIELD_EXPECTED_UT);
            var confidence = 0.60f;
            if (distortion > MAG_FIELD_DISTORTION_TOL_UT) {
                confidence = clampFloat(0.60f - ((distortion - MAG_FIELD_DISTORTION_TOL_UT) / 40.0f), MAG_HEADING_MIN_CONFIDENCE, 0.60f);
            }
            return confidence;
        }
        return 0.0f;
    }

    function shouldAdvanceDR(bestHeading as Float or Null, estSpeed as Float) as Boolean {
        if (bestHeading == null) {
            return false;
        }
        if (getHeadingConfidenceForDr() < MIN_HEADING_CONFIDENCE_FOR_DR) {
            return false;
        }
        if (!hasGpsFix) {
            return false;
        }
        if (isGpsRecoveryHoldActive()) {
            return false;
        }
        if (estSpeed < (DR_MOVE_SPEED_THRESHOLD_MPS * 1.2f)) {
            return false;
        }
        if (movingConfidence < (MIN_SENSOR_CONFIDENCE + 1)) {
            return false;
        }
        if (motionScoreMg < (MIN_SENSOR_MOTION_MG + 5.0f)) {
            return false;
        }
        if (isStationary()) {
            return false;
        }
        return true;
    }

    function shouldAdvanceDRWithoutGps(bestHeading as Float or Null, estSpeed as Float) as Boolean {
        if (bestHeading == null) {
            return false;
        }
        if (getHeadingConfidenceForDr() < MIN_HEADING_CONFIDENCE_FOR_DR) {
            return false;
        }
        if (estSpeed < (DR_MOVE_SPEED_THRESHOLD_MPS * 0.85f)) {
            return false;
        }
        if (movingConfidence < MIN_SENSOR_CONFIDENCE) {
            return false;
        }
        if (motionScoreMg < (MIN_SENSOR_MOTION_MG + 2.0f)) {
            return false;
        }
        if (isStationary()) {
            return false;
        }
        return true;
    }

    function getGpsLossDrSpeed(estSpeed as Float) as Float {
        if (estSpeed <= 0.0f) {
            if (filteredSpeedEst > 0.0f) {
                estSpeed = filteredSpeedEst;
            } else {
                return 0.0f;
            }
        }
        if (movingConfidence < MOVING_CONFIDENCE_ON && motionScoreMg < (MIN_SENSOR_MOTION_MG * 0.85f) && !isMotionDetected) {
            return 0.0f;
        }

        var adjusted = estSpeed;
        if (motionScoreMg < MIN_SENSOR_MOTION_MG) {
            adjusted *= 0.65f;
        } else if (motionScoreMg < (MIN_SENSOR_MOTION_MG + 15.0f)) {
            adjusted *= 0.80f;
        }

        if (movingConfidence < (MOVING_CONFIDENCE_ON + 2)) {
            adjusted *= 0.85f;
        }

        if (adjusted < (DR_MOVE_SPEED_THRESHOLD_MPS * 0.70f)) {
            adjusted = 0.0f;
        }

        return adjusted;
    }

    function updateDrAndKalmanFusion(
        nowMs as Number,
        dt as Float,
        effectiveHeading as Float or Null,
        estSpeed as Float,
        headingConfidence as Float,
        motionScoreMg as Float,
        hasUsableGps as Boolean,
        gpsSignalLost as Boolean,
        drFallbackActive as Boolean
    ) as Dictionary {
        var drSpeed = estSpeed;
        var drHeadingConfidence = headingConfidence;
        var gpsTrustWeight = 1.0f;
        var drGpsBlend = 0.0f;
        var shouldAdvanceSensorDr = false;

        if (dr != null) {
            dr.updateMotionStateFilter(hasUsableGps, headingConfidence, motionScoreMg, dt);
            gpsTrustWeight = dr.getMotionBlendWeight();
        }

        if (!hasUsableGps) {
            gpsTrustWeight = clampFloat(gpsTrustWeight * 0.55f, 0.15f, 1.0f);
        }

        drHeadingConfidence = headingConfidence * gpsTrustWeight;

        if (gpsSignalLost) {
            drSpeed = getGpsLossDrSpeed(estSpeed);
            drHeadingConfidence = drHeadingConfidence * 0.70f;
        }

        if (kalman != null) {
            if (hasUsableGps || drFallbackActive) {
                var h = (effectiveHeading != null) ? effectiveHeading : 0.0f;
                kalman.predictWithTuning(drSpeed, h, dt, headingConfidence, movingConfidence, hasUsableGps);
                if (hasUsableGps) {
                    kalman.updateGps(latitude, longitude, gpsQuality);
                }
            }
        }

        if (dr != null && (hasUsableGps || gpsSignalLost || drFallbackActive) && (nowMs - lastDrGpsCorrectionMs) >= DR_GPS_CORRECTION_INTERVAL_MS) {
            lastDrGpsCorrectionMs = nowMs;
            if (hasUsableGps) {
                drGpsBlend = 0.12f + (gpsTrustWeight * 0.12f);
                if (drGpsBlend > 0.24f) {
                    drGpsBlend = 0.24f;
                }
            } else {
                drGpsBlend = 0.06f + (gpsTrustWeight * 0.06f);
                if (drGpsBlend > 0.12f) {
                    drGpsBlend = 0.12f;
                }
            }
        }

        if (dr != null) {
            dr.updateVerticalState(currentAscentRateMps, dt);
            dr.setContext(isDepthActive);
        }

        if (hasUsableGps) {
            shouldAdvanceSensorDr = shouldAdvanceDR(effectiveHeading, estSpeed);
        } else if (drFallbackActive) {
            shouldAdvanceSensorDr = shouldAdvanceDRWithoutGps(effectiveHeading, drSpeed);
        }

        if (dr != null && shouldAdvanceSensorDr) {
            dr.updateWithSpeedAndConfidence(accelX, accelY, accelZ, gyroZ, effectiveHeading, dt, drSpeed, true, drHeadingConfidence);
        }

        var shouldApplyDrCorrection = (hasUsableGps || gpsSignalLost || drFallbackActive);
        if (dr != null && drGpsBlend > 0.0f && shouldApplyDrCorrection) {
            if (kalman != null) {
                dr.applyPositionCorrection(kalman.getEast(), kalman.getNorth(), drGpsBlend);
            } else if (hasUsableGps && isFiniteValue(latitude) && isFiniteValue(longitude) && hasEntryPosition) {
                var latRefRad = entryLat * 0.017453292519943295f;
                var metersPerDegLat = 111000.0f;
                var metersPerDegLon = 111000.0f * Math.cos(latRefRad);
                if (metersPerDegLon < 1000.0f) {
                    metersPerDegLon = 1000.0f;
                }
                var refEast = (longitude - entryLon) * metersPerDegLon;
                var refNorth = (latitude - entryLat) * metersPerDegLat;
                dr.applyPositionCorrection(refEast, refNorth, drGpsBlend);
            }
        }

        return {
            :drSpeed => drSpeed,
            :drHeadingConfidence => drHeadingConfidence,
            :drGpsBlend => drGpsBlend,
            :shouldAdvanceSensorDr => shouldAdvanceSensorDr
        };
    }

    function onSelect() as Boolean {
        try {
            logDebug("=== SELECT BUTTON PRESSED ===");
            if (isRecording) {
                stopSession();
            } else {
                startSession();
            }
        } catch (e) {
            logDebug("Select button error: " + errorToString(e));
        }
        return true;
    }

    function showPoiNotice(text as String) as Void {
        poiNoticeText = text;
        poiNoticeStartMs = System.getTimer();
        WatchUi.requestUpdate();
    }

    function handlePoiAction() as Boolean {
        try {
            if (!isRecording) {
                toggleDebugLogging();
                showPoiNotice("DBG " + (isDebugLoggingEnabled() ? "ON" : "OFF"));
                return true;
            }
            toggleDrDiagnosticsFit();
            markPoi();
        } catch (e) {
            logDebug("onMenu/POI error: " + errorToString(e));
        }
        return true;
    }

    // CTRL / Menu button → drop a POI on the current DR route while recording
    function onMenu() as Boolean {
        return handlePoiAction();
    }

    function markPoi() as Void {
        if (!isRecording || session == null) {
            return;
        }
        if (poiCount >= MAX_POIS) {
            logDebug("POI limit reached (" + MAX_POIS + ")");
            poiFlashMs = System.getTimer(); // still flash so user knows press was seen
            showPoiNotice("POI limit");
            return;
        }

        var eastVal = 0.0f;
        var northVal = 0.0f;
        var useGpsForPoi = false;

        if (hasGpsFix && isFiniteValue(latitude) && isFiniteValue(longitude)) {
            eastVal = 0.0f;
            northVal = 0.0f;
            useGpsForPoi = true;
        } else if (kalman != null) {
            eastVal = kalman.getEast();
            northVal = kalman.getNorth();
        } else if (dr != null) {
            eastVal = dr.getEastMeters();
            northVal = dr.getNorthMeters();
        }

        // Prefer live GPS; else use the current DR/Kalman estimate.
        var poiLat = 0.0f;
        var poiLon = 0.0f;
        var haveLatLon = false;

        if (useGpsForPoi) {
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

        // POIs are stored as custom FIT record values only; do not create a lap split.
        poiFlashMs = System.getTimer();
        showPoiNotice("POI saved");
        logDebug("POI #" + poiCount + " E=" + eastVal.format("%.1f")
            + " N=" + northVal.format("%.1f")
            + (haveLatLon ? (" lat=" + poiLat.format("%.5f") + " lon=" + poiLon.format("%.5f")) : ""));
    }

    function onBack() as Boolean {
        try {
            logDebug("=== BACK BUTTON ===");

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
            logDebug("Back button error: " + errorToString(e));
            return false;
        }
    }

    function startSession() as Void {
        try {
            if (isRecording) {
                return;
            }

            logDebug("MANUAL START");
            startGps();
            captureEntryPosition();
            startRecording();
            openTraceLogFile();

            if (!isRecording) {
                return;
            }

            isDepthActive = (currentDepth > DEPTH_START_THRESHOLD_M);
            resetHeadingEstimate();
            resetMotionState();
            movingConfidence = 0;
            fitWriteTick = 0;
            heartRate = 0;
            currentAscentRateMps = 0.0f;
            maxDepthSeen = 0.0f;
            depthTrackingTimeMs = 0;
            maxN2LoadSeen = 0.0f;
            poiCount = 0;
            poiFlashMs = 0;

            // stopSession() stops the accelerometer listener to save power
            // while not recording; bring it back with a clean baseline now.
            startMotionListener();

            if (kalman != null) {
                kalman.reset();
                if (hasEntryPosition) {
                    kalman.setReference(entryLat, entryLon);
                } else if (hasGpsFix) {
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
            logDebug("startSession error: " + errorToString(e));
        }
    }

    function stopSession() as Void {
        try {
            stopTimerOnly();
            if (!isRecording) {
                isDepthActive = false;
                stopGps();
                stopMotionListener();
                return;
            }
            if (n2Model != null) {
                n2Model.reset();
            }
            lastDepthForAscent = 0.0f;
            currentAscentRateMps = 0.0f;
            logDebug("MANUAL STOP - Saving FIT");
            captureExitPosition();
            isDepthActive = false;

            // Write session-level summary fields while the session is still open
            if (maxDepthField != null) {
                maxDepthField.setData(maxDepthSeen);
            }
            if (trackTimeField != null) {
                trackTimeField.setData(depthTrackingTimeMs.toFloat() / 1000.0f);
            }
            if (maxN2Field != null) {
                maxN2Field.setData(maxN2LoadSeen);
            }

            shutdownSessionSafe();
            closeTraceLogFile();
            maxDepthSeen = 0.0f;
            depthTrackingTimeMs = 0;
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
            logDebug("stopSession error: " + errorToString(e));
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
            logDebug("captureEntryPosition error: " + errorToString(e));
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
            logDebug("captureExitPosition error: " + errorToString(e));
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
            logDebug("createField OK: " + name + " id=" + id);
            return f;
        } catch (e) {
            logDebug("createField failed: " + name + " id=" + id + " -> " + errorToString(e));
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
            logDebug("createSessionField failed: " + name + " -> " + errorToString(e));
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

        // Instinct ~16 developer-field limit. Create at most 14 record fields.
        // IDs 0–13 sequential. Extra metrics stay on-screen only.
        drEastField     = safeCreateField("DR_East",   FIELD_DR_EAST,    FitContributor.DATA_TYPE_FLOAT,  "m");
        drNorthField    = safeCreateField("DR_North",  FIELD_DR_NORTH,   FitContributor.DATA_TYPE_FLOAT,  "m");
        depthField      = safeCreateField("Depth",     FIELD_DEPTH,      FitContributor.DATA_TYPE_FLOAT,  "m");
        speedEstField   = safeCreateField("Speed",     FIELD_SPEED_EST,  FitContributor.DATA_TYPE_FLOAT,  "m/s");
        headingField    = safeCreateField("Heading",   FIELD_HEADING,    FitContributor.DATA_TYPE_FLOAT,  "deg");
        depthActiveField = safeCreateField("DepthActive", FIELD_DEPTH_ACTIVE, FitContributor.DATA_TYPE_UINT32,  "");
        motionField     = safeCreateField("Motion",    FIELD_MOTION,     FitContributor.DATA_TYPE_FLOAT,  "mg");
        movingField     = safeCreateField("Moving",    FIELD_MOVING,     FitContributor.DATA_TYPE_UINT32,  "");
        gpsFixField     = safeCreateField("GpsFix",    FIELD_GPS_FIX,    FitContributor.DATA_TYPE_UINT32,  "");
        drLatField      = safeCreateField("DR_Lat",    FIELD_DR_LAT,     FitContributor.DATA_TYPE_FLOAT,  "deg");
        drLonField      = safeCreateField("DR_Lon",    FIELD_DR_LON,     FitContributor.DATA_TYPE_FLOAT,  "deg");
        poiIdField      = safeCreateField("POI_Id",    FIELD_POI_ID,     FitContributor.DATA_TYPE_UINT32,  "");
        poiLatField     = safeCreateField("POI_Lat",   FIELD_POI_LAT,    FitContributor.DATA_TYPE_FLOAT,  "deg");
        poiLonField     = safeCreateField("POI_Lon",   FIELD_POI_LON,    FitContributor.DATA_TYPE_FLOAT,  "deg");
        drDiagField     = drDiagFitEnabled ? safeCreateField("DR_Diag", FIELD_DR_DIAG, FitContributor.DATA_TYPE_UINT32, "") : null;

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
        trackTimeField = null;
        maxN2Field = null;

        var started = session.start();
        if (started) {
            isRecording = true;
            clearLastFitValues();
            poiCount = 0;
            poiFlashMs = 0;
            logDebug("Recording STARTED");
            openTraceLogFile();
        } else {
            logDebug("session.start() returned false");
            clearFitFields();
            session = null;
            isRecording = false;
        }
    } catch (e) {
        logDebug("Start recording error: " + errorToString(e));
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
                logDebug("session.stop() done");
            }

            var saved = session.save();
            logDebug("session.save() returned: " + saved);
        } catch (e) {
            logDebug("session save error: " + errorToString(e));
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
        isDepthActive = false;
        hasGpsFix = false;
    }

    function clearLastFitValues() as Void {
        lastFitEast = null;
        lastFitNorth = null;
        lastFitDepth = null;
        lastFitMotion = null;
        lastFitSpeedEst = null;
        lastFitDepthActive = null;
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
        depthActiveField = null;
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
        trackTimeField = null;
        maxN2Field = null;
        poiIdField = null;
        poiLatField = null;
        poiLonField = null;
        poiEastField = null;
        poiNorthField = null;
        drDiagField = null;
        clearLastFitValues();
    }

    function resetDepthCalibration() as Void {
        try {
            surfaceAltitudeSum = 0.0f;
            surfaceAltitude = 0.0f;
            surfacePressureSum = 0.0f;
            pressureCalibrationSamples = 0;
            altitudeCalibrationSamples = 0;
            surfacePressurePa = DEFAULT_SURFACE_PA;
            depthFilter = 0.0f;
            calibrationSamples = 0;
            currentDepth = 0.0f;
            simulatedDepthM = 0.0f;
            lastAltSample = null;
            flatAltSampleCount = 0;
            lastDepthUpdateMs = 0;
            usePressureDepth = false;
        } catch (e) {
            logDebug("resetDepthCalibration error: " + errorToString(e));
        }
    }

    function toggleDrDiagnosticsFit() as Void {
        drDiagFitEnabled = !drDiagFitEnabled;
        if (!drDiagFitEnabled) {
            logDebug("DR diagnostics FIT disabled");
        } else {
            logDebug("DR diagnostics FIT enabled");
        }
    }

    function packDrDiagnosticsValue(gpsUsable as Boolean, headingConf as Float, motionScore as Float, estSpeed as Float, gyroZValue as Float) as Number {
        var gpsBit = gpsUsable ? 1 : 0;
        var headingByte = clampFloat(headingConf * 255.0f, 0.0f, 255.0f).toNumber();
        var motionByte = clampFloat(motionScore, 0.0f, 255.0f).toNumber();
        var gyroByte = clampFloat(gyroZValue * 100.0f, 0.0f, 255.0f).toNumber();
        return ((gpsBit << 24) + (headingByte << 16) + (motionByte << 8) + gyroByte).toNumber();
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

    function safeFormatFloat(value as Float or Null, pattern as String, fallback as String) as String {
        if (value == null || !isFiniteValue(value)) {
            return fallback;
        }
        return value.format(pattern);
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

            var eastVal = (kalman != null) ? kalman.getEast() : (dr != null ? dr.getEastMeters() : 0.0f);
            var northVal = (kalman != null) ? kalman.getNorth() : (dr != null ? dr.getNorthMeters() : 0.0f);

            var depthVal = currentDepth;
            var motionVal = motionScoreMg;
            var speedVal = estSpeed;
            var depthActiveVal = isDepthActive ? 1 : 0;
            var gpsFixVal = hasGpsFix ? 1 : 0;
            var movingVal = (movingConfidence >= MOVING_CONFIDENCE_ON && !isStationary()) ? 1 : 0;
            var headingDegVal = bestHeading != null ? radToDeg(bestHeading) : -1.0f;

            lastFitEast = writeFloatField(drEastField, eastVal, lastFitEast, 0.01f);
            lastFitNorth = writeFloatField(drNorthField, northVal, lastFitNorth, 0.01f);
            lastFitDepth = writeFloatField(depthField, depthVal, lastFitDepth, 0.01f);
            lastFitMotion = writeFloatField(motionField, motionVal, lastFitMotion, 0.1f);
            lastFitSpeedEst = writeFloatField(speedEstField, speedVal, lastFitSpeedEst, 0.01f);
            lastFitDepthActive = writeUIntField(depthActiveField, depthActiveVal, lastFitDepthActive);
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

            if (drDiagField != null && drDiagFitEnabled) {
                var diagHeadingConf = getHeadingConfidenceForDr();
                var diagPayload = packDrDiagnosticsValue(hasGpsFix, diagHeadingConf, motionScoreMg, estSpeed, gyroZ);
                lastFitDrDiag = writeUIntField(drDiagField, diagPayload, lastFitDrDiag);
            }

            if (n2Model != null) {
                lastFitN2Load = writeFloatField(n2LoadField, n2Model.getLoading(), lastFitN2Load, 0.1f);
                lastFitN2Max = writeFloatField(n2MaxField, n2Model.getMaxLoading(), lastFitN2Max, 0.1f);
                lastFitN2Band = writeUIntField(n2BandField, n2Model.getRiskBand(), lastFitN2Band);
            }

            // NEW health / depth-tracking metrics
            if (heartRate > 0) {
                lastFitHr = writeUIntField(hrField, heartRate, lastFitHr);
            }
            lastFitAscent = writeFloatField(ascentField, currentAscentRateMps, lastFitAscent, 0.05f);

            // SpO2 is optical/wrist-based and unreliable in deeper tracking conditions - only log
            // when a real reading is present (0 means no reading this tick).
            if (spo2 > 0) {
                lastFitSpo2 = writeUIntField(spo2Field, spo2, lastFitSpo2);
            }
            lastFitTemp = writeFloatField(tempField, ambientTempC, lastFitTemp, 0.5f);

        } catch (e) {
            logDebug("FIT write error: " + errorToString(e));
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

    function isInsideTopRightCutout(x as Number, y as Number) as Boolean {
        var dx = x - LAYOUT_CUTOUT_CENTER_X;
        var dy = y - LAYOUT_CUTOUT_CENTER_Y;
        return (dx * dx + dy * dy) <= (LAYOUT_CUTOUT_RADIUS * LAYOUT_CUTOUT_RADIUS);
    }

    function canDrawFieldRow(labelX as Number, valueX as Number, y as Number) as Boolean {
        var rowY = y + 8;
        var rowBottom = y + 16;
        return y >= LAYOUT_CONTENT_TOP && rowBottom <= 176 &&
            !isInsideTopRightCutout(labelX + 12, rowY) &&
            !isInsideTopRightCutout(valueX + 14, rowY);
    }

    function drawMiniStatusIcon(dc as Dc, x as Number, y as Number, color as Number, iconType as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        if (iconType == 0) {
            dc.fillCircle(x + 4, y + 4, 3);
        } else if (iconType == 1) {
            dc.fillRectangle(x + 2, y + 2, 5, 5);
            dc.fillRectangle(x + 6, y + 2, 5, 5);
            dc.fillRectangle(x + 2, y + 7, 5, 5);
            dc.fillRectangle(x + 6, y + 7, 5, 5);
        } else if (iconType == 2) {
            dc.fillRectangle(x + 2, y + 5, 11, 2);
            dc.fillRectangle(x + 6, y + 2, 3, 8);
            dc.drawLine(x + 2, y + 9, x + 13, y + 9);
        } else if (iconType == 3) {
            dc.fillRectangle(x + 2, y + 2, 2, 10);
            dc.fillRectangle(x + 7, y + 2, 2, 10);
            dc.fillRectangle(x + 12, y + 2, 2, 10);
        } else if (iconType == 4) {
            dc.fillCircle(x + 6, y + 6, 4);
            dc.drawLine(x + 6, y + 10, x + 6, y + 14);
            dc.drawLine(x + 4, y + 8, x + 1, y + 5);
            dc.drawLine(x + 8, y + 8, x + 11, y + 5);
        }
    }

    function onUpdate(dc as Dc) as Void {
        try {
            View.onUpdate(dc);

            var font = Graphics.FONT_XTINY;
            var w = dc.getWidth();
            var leftX = LAYOUT_CONTENT_LEFT;
            var rowH = 18;
            var headerTextLeft = LAYOUT_TOP_LEFT_X + 4;
            var noticeText = null as String or Null;

            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(0, 0, w, 176);

            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(LAYOUT_TOP_LEFT_X, LAYOUT_TOP_LEFT_Y, LAYOUT_TOP_LEFT_W, LAYOUT_TOP_LEFT_H);

            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            if (isRecording && poiFlashMs > 0) {
                var age = System.getTimer() - poiFlashMs;
                if (age >= 0 && age < POI_FLASH_MS) {
                    dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
                } else {
                    poiFlashMs = 0;
                }
            }

            if (poiNoticeText != null) {
                var noticeAge = System.getTimer() - poiNoticeStartMs;
                if (noticeAge >= POI_NOTICE_MS) {
                    poiNoticeText = null;
                } else {
                    noticeText = poiNoticeText;
                }
            } else if (!hasGpsFix && dr != null) {
                noticeText = "GPS LOST - DR";
            }

            var recStatusText = isRecording ? "ON" : "OFF";
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.drawText(headerTextLeft, LAYOUT_TOP_LEFT_Y + 6, Graphics.FONT_XTINY, "REC: " + recStatusText, Graphics.TEXT_JUSTIFY_LEFT);

            var modeText = isDepthActive ? "DEPTH" : "SURFACE";
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.drawText(headerTextLeft, LAYOUT_TOP_LEFT_Y + 20, Graphics.FONT_XTINY, "MODE: " + modeText, Graphics.TEXT_JUSTIFY_LEFT);

            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.drawText(headerTextLeft, LAYOUT_TOP_LEFT_Y + 34, Graphics.FONT_XTINY, "GPS: " + (hasGpsFix ? "FIX" : "NO FIX"), Graphics.TEXT_JUSTIFY_LEFT);

            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.drawText(headerTextLeft, LAYOUT_TOP_LEFT_Y + 48, Graphics.FONT_XTINY, "DBG: " + (isDebugLoggingEnabled() ? "ON" : "OFF"), Graphics.TEXT_JUSTIFY_LEFT);

            if (noticeText != null) {
                dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
                dc.drawText(headerTextLeft, LAYOUT_TOP_LEFT_Y + 62, Graphics.FONT_XTINY, noticeText, Graphics.TEXT_JUSTIFY_LEFT);
            }

            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            var topRightLabel = hasGpsFix ? "GPS" : ((dr != null) ? "DR" : "NO");
            var topRightMeta = hasGpsFix ? "Q" + gpsQuality : ((dr != null) ? "FALLB" : "FIX");
            dc.drawText(LAYOUT_TOP_RIGHT_X + 26, LAYOUT_TOP_RIGHT_Y + 8, font, topRightLabel, Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(LAYOUT_TOP_RIGHT_X + 26, LAYOUT_TOP_RIGHT_Y + 24, font, topRightMeta, Graphics.TEXT_JUSTIFY_CENTER);

            var contentY = LAYOUT_CONTENT_TOP + scrollY;
            var rightX = LAYOUT_CONTENT_LEFT + 66;

            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            if (isRecording && poiCount > 0) {
                if (canDrawFieldRow(leftX, rightX, contentY)) {
                    dc.drawText(leftX, contentY, font, "POIs:", Graphics.TEXT_JUSTIFY_LEFT);
                    dc.drawText(rightX, contentY, font, "" + poiCount, Graphics.TEXT_JUSTIFY_LEFT);
                }
                contentY += rowH;
            }

            if (canDrawFieldRow(leftX, rightX, contentY)) {
                dc.drawText(leftX, contentY, font, "GPS:", Graphics.TEXT_JUSTIFY_LEFT);
                dc.drawText(rightX, contentY, font, hasGpsFix ? "Yes" : "No", Graphics.TEXT_JUSTIFY_LEFT);
            }
            contentY += rowH;

            if (canDrawFieldRow(leftX, rightX, contentY)) {
                dc.drawText(leftX, contentY, font, "Q:", Graphics.TEXT_JUSTIFY_LEFT);
                dc.drawText(rightX, contentY, font, "" + gpsQuality, Graphics.TEXT_JUSTIFY_LEFT);
            }
            contentY += rowH;

            if (canDrawFieldRow(leftX, rightX, contentY)) {
                dc.drawText(leftX, contentY, font, "Moving:", Graphics.TEXT_JUSTIFY_LEFT);
                dc.drawText(rightX, contentY, font, ((movingConfidence >= MOVING_CONFIDENCE_ON && !isStationary()) ? "Yes" : "No"), Graphics.TEXT_JUSTIFY_LEFT);
            }
            contentY += rowH;

            if (canDrawFieldRow(leftX, rightX, contentY)) {
                dc.drawText(leftX, contentY, font, "Depth:", Graphics.TEXT_JUSTIFY_LEFT);
                dc.drawText(rightX, contentY, font, currentDepth.format("%.1f") + "m", Graphics.TEXT_JUSTIFY_LEFT);
            }
            contentY += rowH;

            if (canDrawFieldRow(leftX, rightX, contentY)) {
                dc.drawText(leftX, contentY, font, "Dsrc:", Graphics.TEXT_JUSTIFY_LEFT);
                dc.drawText(rightX, contentY, font, depthSourceTag, Graphics.TEXT_JUSTIFY_LEFT);
            }
            contentY += rowH;

            if (isRecording && isDebugLoggingEnabled()) {
                if (canDrawFieldRow(leftX, rightX, contentY)) {
                    dc.drawText(leftX, contentY, font, "Praw:", Graphics.TEXT_JUSTIFY_LEFT);
                    dc.drawText(rightX, contentY, font,
                        (uiPressureRaw != null ? uiPressureRaw.format("%.1f") : "--"),
                        Graphics.TEXT_JUSTIFY_LEFT);
                }
                contentY += rowH;

                if (canDrawFieldRow(leftX, rightX, contentY)) {
                    dc.drawText(leftX, contentY, font, "Ppa:", Graphics.TEXT_JUSTIFY_LEFT);
                    dc.drawText(rightX, contentY, font,
                        (uiPressurePa != null ? uiPressurePa.format("%.0f") : "--"),
                        Graphics.TEXT_JUSTIFY_LEFT);
                }
                contentY += rowH;

                if (canDrawFieldRow(leftX, rightX, contentY)) {
                    dc.drawText(leftX, contentY, font, "Punit:", Graphics.TEXT_JUSTIFY_LEFT);
                    dc.drawText(rightX, contentY, font, uiPressureUnitTag, Graphics.TEXT_JUSTIFY_LEFT);
                }
                contentY += rowH;
            }

            if (canDrawFieldRow(leftX, rightX, contentY)) {
                dc.drawText(leftX, contentY, font, "Asc:", Graphics.TEXT_JUSTIFY_LEFT);
                dc.drawText(rightX, contentY, font, currentAscentRateMps.format("%.2f") + "m/s", Graphics.TEXT_JUSTIFY_LEFT);
            }
            contentY += rowH;

            if (canDrawFieldRow(leftX, rightX, contentY)) {
                dc.drawText(leftX, contentY, font, "HR:", Graphics.TEXT_JUSTIFY_LEFT);
                if (heartRate > 0) {
                    dc.drawText(rightX, contentY, font, heartRate.format("%d") + " bpm", Graphics.TEXT_JUSTIFY_LEFT);
                } else {
                    dc.drawText(rightX, contentY, font, "--", Graphics.TEXT_JUSTIFY_LEFT);
                }
            }
            contentY += rowH;

            if (canDrawFieldRow(leftX, rightX, contentY)) {
                dc.drawText(leftX, contentY, font, "Solar:", Graphics.TEXT_JUSTIFY_LEFT);
                if (solarLux > 0.0f) {
                    dc.drawText(rightX, contentY, font, solarLux.format("%.0f") + " lux", Graphics.TEXT_JUSTIFY_LEFT);
                } else {
                    dc.drawText(rightX, contentY, font, "--", Graphics.TEXT_JUSTIFY_LEFT);
                }
            }
            contentY += rowH;

            if (canDrawFieldRow(leftX, rightX, contentY)) {
                dc.drawText(leftX, contentY, font, "Motion:", Graphics.TEXT_JUSTIFY_LEFT);
                dc.drawText(rightX, contentY, font, motionScoreMg.format("%.0f") + "mg", Graphics.TEXT_JUSTIFY_LEFT);
            }
            contentY += rowH - 2;

            if (calibrationActive) {
                var elapsed = System.getTimer() - calibrationStartMs;
                var remain = CALIBRATION_DURATION_MS - elapsed;
                if (remain < 0) {
                    remain = 0;
                }
                if (canDrawFieldRow(leftX, rightX, contentY)) {
                    dc.drawText(leftX, contentY, font, "Cal:", Graphics.TEXT_JUSTIFY_LEFT);
                    dc.drawText(rightX, contentY, font, remain + "ms", Graphics.TEXT_JUSTIFY_LEFT);
                }
                contentY += rowH;
            }

            if (kalman != null) {
                if (canDrawFieldRow(leftX, rightX, contentY)) {
                    dc.drawText(leftX, contentY, font, "KF E:", Graphics.TEXT_JUSTIFY_LEFT);
                    dc.drawText(rightX, contentY, font, safeFormatFloat(kalman.getEast(), "%.1f", "0.0") + "m", Graphics.TEXT_JUSTIFY_LEFT);
                }
                contentY += rowH;
                if (canDrawFieldRow(leftX, rightX, contentY)) {
                    dc.drawText(leftX, contentY, font, "KF N:", Graphics.TEXT_JUSTIFY_LEFT);
                    dc.drawText(rightX, contentY, font, safeFormatFloat(kalman.getNorth(), "%.1f", "0.0") + "m", Graphics.TEXT_JUSTIFY_LEFT);
                }
                contentY += rowH;
            } else if (dr != null) {
                if (canDrawFieldRow(leftX, rightX, contentY)) {
                    dc.drawText(leftX, contentY, font, "DR E:", Graphics.TEXT_JUSTIFY_LEFT);
                    dc.drawText(rightX, contentY, font, safeFormatFloat(dr.getEastMeters(), "%.1f", "0.0") + "m", Graphics.TEXT_JUSTIFY_LEFT);
                }
                contentY += rowH;
                if (canDrawFieldRow(leftX, rightX, contentY)) {
                    dc.drawText(leftX, contentY, font, "DR N:", Graphics.TEXT_JUSTIFY_LEFT);
                    dc.drawText(rightX, contentY, font, safeFormatFloat(dr.getNorthMeters(), "%.1f", "0.0") + "m", Graphics.TEXT_JUSTIFY_LEFT);
                }
                contentY += rowH;
                if (canDrawFieldRow(leftX, rightX, contentY)) {
                    dc.drawText(leftX, contentY, font, "Dist:", Graphics.TEXT_JUSTIFY_LEFT);
                    dc.drawText(rightX, contentY, font, safeFormatFloat(dr.getTotalDistanceMeters(), "%.0f", "0") + "m", Graphics.TEXT_JUSTIFY_LEFT);
                }
                contentY += rowH;
            }

            if (canDrawFieldRow(leftX, rightX, contentY)) {
                dc.drawText(leftX, contentY, font, "Spd:", Graphics.TEXT_JUSTIFY_LEFT);
                dc.drawText(rightX, contentY, font, speed.format("%.2f") + "m/s", Graphics.TEXT_JUSTIFY_LEFT);
            }
            contentY += rowH;

            if (n2Model != null) {
                if (canDrawFieldRow(leftX, rightX, contentY)) {
                    dc.drawText(leftX, contentY, font, "N2:", Graphics.TEXT_JUSTIFY_LEFT);
                    dc.drawText(rightX, contentY, font, n2Model.getLoading().format("%.0f") + "%", Graphics.TEXT_JUSTIFY_LEFT);
                }
                contentY += rowH;

                if (canDrawFieldRow(leftX, rightX, contentY)) {
                    dc.drawText(leftX, contentY, font, "Max:", Graphics.TEXT_JUSTIFY_LEFT);
                    dc.drawText(rightX, contentY, font, n2Model.getMaxLoading().format("%.0f") + "%", Graphics.TEXT_JUSTIFY_LEFT);
                }
                contentY += rowH;

                var band = n2Model.getRiskBand();
                var bandText = "LOW";
                var bandColor = Graphics.COLOR_WHITE;

                if (band == 1) {
                    bandText = "MOD";
                    bandColor = Graphics.COLOR_LT_GRAY;
                } else if (band == 2) {
                    bandText = "ELEV";
                    bandColor = Graphics.COLOR_DK_GRAY;
                } else if (band == 3) {
                    bandText = "HIGH";
                    bandColor = Graphics.COLOR_WHITE;
                }

                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                if (canDrawFieldRow(leftX, rightX, contentY)) {
                    dc.drawText(leftX, contentY, font, "Risk:", Graphics.TEXT_JUSTIFY_LEFT);
                    dc.setColor(bandColor, Graphics.COLOR_TRANSPARENT);
                    dc.drawText(rightX, contentY, font, bandText, Graphics.TEXT_JUSTIFY_LEFT);
                    dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                }
            }
        } catch (e) {
            logDebug("Draw error: " + errorToString(e));
        }
    }

    function prepareToExit() as Void {
        stopTimerOnly();
        if (isRecording) {
            stopSession();
        }
        stopMotionListener();
        stopGps();
    }
}