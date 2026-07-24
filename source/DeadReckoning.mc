import Toybox.Lang;
import Toybox.Math;
import Toybox.System;

class DeadReckoning {

    var eastMeters = 0.0f;
    var northMeters = 0.0f;

    var headingRad = 0.0f;
    var speedMps = 0.0f;

    var totalDistanceMeters = 0.0f;
    var lastStepDistanceMeters = 0.0f;
    var lastAcceptedDx = 0.0f;
    var lastAcceptedDy = 0.0f;

    var prevMs = 0;

    var hasHeadingLock = false;
    var lastMeasuredHeadingRad = null;
    var lastPredictedHeadingRad = 0.0f;
    var lastHeadingErrorRad = 0.0f;
    var movementAccepted = false;

    const MAX_DT_SEC = 2.0f;
    const MIN_DT_SEC = 0.01f;

    const HEADING_ALPHA_SLOW = 0.10f;
    const HEADING_ALPHA_FAST = 0.22f;
    const MAX_HEADING_CORRECTION_RAD = 0.35f;

    const SPEED_ALPHA_RISE = 0.30f;
    const SPEED_ALPHA_FALL = 0.18f;
    const SPEED_DECAY_WHEN_STOPPED = 0.75f;

    const MIN_SPEED_MPS = 0.0f;
    const MAX_SPEED_MPS = 3.0f;
    const SPEED_DEADBAND_MPS = 0.08f;

    const MIN_STEP_DISTANCE_M = 0.015f;
    const MAX_STEP_DISTANCE_M = 10.0f;

    const MAX_REASONABLE_YAW_RATE_RAD_S = 4.5f;

    function initialize() {
        reset();
    }

    function reset() as Void {
        eastMeters = 0.0f;
        northMeters = 0.0f;
        headingRad = 0.0f;
        speedMps = 0.0f;
        totalDistanceMeters = 0.0f;
        lastStepDistanceMeters = 0.0f;
        lastAcceptedDx = 0.0f;
        lastAcceptedDy = 0.0f;
        prevMs = System.getTimer();
        hasHeadingLock = false;
        lastMeasuredHeadingRad = null;
        lastPredictedHeadingRad = 0.0f;
        lastHeadingErrorRad = 0.0f;
        movementAccepted = false;
    }

    function resetWithHeading(initialHeading as Float) as Void {
        reset();
        headingRad = normalizeAngle(initialHeading);
        hasHeadingLock = true;
        lastMeasuredHeadingRad = headingRad;
    }

    function setHeading(newHeading as Float) as Void {
        headingRad = normalizeAngle(newHeading);
        hasHeadingLock = true;
        lastMeasuredHeadingRad = headingRad;
    }

    function setSpeedEstimate(newSpeedMps as Float) as Void {
        speedMps = sanitizeSpeed(newSpeedMps);
    }

    function update(accelX as Float, accelY as Float, accelZ as Float, gyroZ as Float, measuredHeadingRad as Float or Null, dt as Float) as Void {
        updateWithSpeedAndConfidence(accelX, accelY, accelZ, gyroZ, measuredHeadingRad, dt, speedMps, true, 1.0f);
    }

    function updateWithSpeed(accelX as Float, accelY as Float, accelZ as Float, gyroZ as Float, measuredHeadingRad as Float or Null, dt as Float, newSpeedMps as Float) as Void {
        updateWithSpeedAndConfidence(accelX, accelY, accelZ, gyroZ, measuredHeadingRad, dt, newSpeedMps, true, 1.0f);
    }

    function updateWithSpeedAndConfidence(
        accelX as Float,
        accelY as Float,
        accelZ as Float,
        gyroZ as Float,
        measuredHeadingRad as Float or Null,
        dt as Float,
        newSpeedMps as Float,
        movementAllowed as Boolean,
        headingConfidence as Float
    ) as Void {

        movementAccepted = false;
        lastStepDistanceMeters = 0.0f;
        lastAcceptedDx = 0.0f;
        lastAcceptedDy = 0.0f;

        if (dt < MIN_DT_SEC || dt > MAX_DT_SEC) {
            return;
        }

        var safeGyroZ = gyroZ;
        if (safeGyroZ > MAX_REASONABLE_YAW_RATE_RAD_S) {
            safeGyroZ = MAX_REASONABLE_YAW_RATE_RAD_S;
        } else if (safeGyroZ < -MAX_REASONABLE_YAW_RATE_RAD_S) {
            safeGyroZ = -MAX_REASONABLE_YAW_RATE_RAD_S;
        }

        var predictedHeading = normalizeAngle(headingRad + (safeGyroZ * dt));
        lastPredictedHeadingRad = predictedHeading;

        var correctedHeading = predictedHeading;

        if (measuredHeadingRad != null) {
            var targetHeading = normalizeAngle(measuredHeadingRad);
            lastMeasuredHeadingRad = targetHeading;

            if (!hasHeadingLock) {
                correctedHeading = targetHeading;
                hasHeadingLock = true;
            } else {
                var alpha = chooseHeadingAlpha(speedMps, headingConfidence);
                var error = normalizeAngle(targetHeading - predictedHeading);
                error = clampFloat(error, -MAX_HEADING_CORRECTION_RAD, MAX_HEADING_CORRECTION_RAD);
                lastHeadingErrorRad = error;
                correctedHeading = normalizeAngle(predictedHeading + (error * alpha));
            }
        } else {
            lastHeadingErrorRad = 0.0f;
        }

        headingRad = correctedHeading;

        var clampedInputSpeed = sanitizeSpeed(newSpeedMps);

        if (!movementAllowed || clampedInputSpeed <= SPEED_DEADBAND_MPS) {
            speedMps = speedMps * SPEED_DECAY_WHEN_STOPPED;
            if (speedMps < SPEED_DEADBAND_MPS) {
                speedMps = 0.0f;
            }
            return;
        }

        if (clampedInputSpeed > speedMps) {
            speedMps = lowPass(speedMps, clampedInputSpeed, SPEED_ALPHA_RISE);
        } else {
            speedMps = lowPass(speedMps, clampedInputSpeed, SPEED_ALPHA_FALL);
        }

        if (speedMps <= SPEED_DEADBAND_MPS) {
            speedMps = 0.0f;
            return;
        }

        var stepEast = speedMps * Math.sin(headingRad) * dt;
        var stepNorth = speedMps * Math.cos(headingRad) * dt;
        var stepDistance = Math.sqrt((stepEast * stepEast) + (stepNorth * stepNorth));

        if (stepDistance < MIN_STEP_DISTANCE_M || stepDistance > MAX_STEP_DISTANCE_M) {
            return;
        }

        eastMeters += stepEast;
        northMeters += stepNorth;
        totalDistanceMeters += stepDistance;

        lastAcceptedDx = stepEast;
        lastAcceptedDy = stepNorth;
        lastStepDistanceMeters = stepDistance;
        movementAccepted = true;
    }

    function updateAutoDt(measuredHeadingRad as Float or Null, gyroZ as Float, newSpeedMps as Float) as Void {
        var nowMs = System.getTimer();
        var dt = (nowMs - prevMs).toFloat() / 1000.0f;
        prevMs = nowMs;

        if (dt < MIN_DT_SEC || dt > MAX_DT_SEC) {
            return;
        }

        updateWithSpeed(0.0f, 0.0f, 0.0f, gyroZ, measuredHeadingRad, dt, newSpeedMps);
    }

    function addDistanceStep(distanceMeters as Float, courseHeadingRad as Float) as Void {
        if (distanceMeters <= 0.0f) {
            return;
        }

        var d = clampFloat(distanceMeters, 0.0f, MAX_STEP_DISTANCE_M);
        if (d < MIN_STEP_DISTANCE_M) {
            return;
        }

        var h = normalizeAngle(courseHeadingRad);

        var stepEast = d * Math.sin(h);
        var stepNorth = d * Math.cos(h);

        eastMeters += stepEast;
        northMeters += stepNorth;
        totalDistanceMeters += d;
        headingRad = h;
        hasHeadingLock = true;
        lastMeasuredHeadingRad = h;
        lastPredictedHeadingRad = h;
        lastHeadingErrorRad = 0.0f;
        lastAcceptedDx = stepEast;
        lastAcceptedDy = stepNorth;
        lastStepDistanceMeters = d;
        movementAccepted = true;
    }

    function getDRData() as Dictionary {
        return {
            :east => eastMeters,
            :north => northMeters,
            :headingRad => headingRad,
            :headingDeg => normalizeDegrees(Math.toDegrees(headingRad)),
            :distance => totalDistanceMeters,
            :speed => speedMps,
            :stepDistance => lastStepDistanceMeters,
            :stepEast => lastAcceptedDx,
            :stepNorth => lastAcceptedDy,
            :movementAccepted => movementAccepted,
            :hasHeadingLock => hasHeadingLock,
            :headingErrorDeg => Math.toDegrees(lastHeadingErrorRad)
        };
    }

    function getEastMeters() as Float {
        return eastMeters;
    }

    function getNorthMeters() as Float {
        return northMeters;
    }

    function getHeadingRad() as Float {
        return headingRad;
    }

    function getHeadingDeg() as Float {
        return normalizeDegrees(Math.toDegrees(headingRad));
    }

    function getSpeedMps() as Float {
        return speedMps;
    }

    function getTotalDistanceMeters() as Float {
        return totalDistanceMeters;
    }

    function hasValidHeading() as Boolean {
        return hasHeadingLock;
    }

    function chooseHeadingAlpha(currentSpeedMps as Float, headingConfidence as Float) as Float {
        var conf = clampFloat(headingConfidence, 0.0f, 1.0f);

        if (currentSpeedMps >= 0.7f) {
            return HEADING_ALPHA_FAST * conf;
        }

        return HEADING_ALPHA_SLOW * conf;
    }

    function sanitizeSpeed(value as Float) as Float {
        var v = clampFloat(value, MIN_SPEED_MPS, MAX_SPEED_MPS);
        if (v < SPEED_DEADBAND_MPS) {
            return 0.0f;
        }
        return v;
    }

    function lowPass(current as Float, incoming as Float, alpha as Float) as Float {
        return current + ((incoming - current) * alpha);
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

    function normalizeAngle(a as Float) as Float {
        var angle = a;

        while (angle > Math.PI) {
            angle -= (2.0f * Math.PI);
        }

        while (angle < -Math.PI) {
            angle += (2.0f * Math.PI);
        }

        return angle;
    }

    function normalizeDegrees(deg as Float) as Float {
        var d = deg;

        while (d >= 360.0f) {
            d -= 360.0f;
        }

        while (d < 0.0f) {
            d += 360.0f;
        }

        return d;
    }

    function blendAngle(current as Float, target as Float, alpha as Float) as Float {
        var delta = normalizeAngle(target - current);
        return normalizeAngle(current + (delta * alpha));
    }
}