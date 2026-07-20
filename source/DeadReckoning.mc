import Toybox.Lang;
import Toybox.Math;
import Toybox.System;

class DeadReckoning {

    // East / North position in meters
    var posX = 0.0f;
    var posY = 0.0f;

    // Radians, normalized to [-PI, PI]
    var heading = 0.0f;

    // Optional last known speed estimate in m/s
    var speedMps = 0.0f;

    // Cumulative horizontal distance
    var totalDistance = 0.0f;

    // Millisecond timer source
    var prevMs = 0;

    // Tuning
    const MAX_DT_SEC = 2.0f;
    const HEADING_ALPHA = 0.15f;
    const SPEED_ALPHA = 0.20f;
    const MIN_SPEED_MPS = 0.0f;
    const MAX_SPEED_MPS = 3.0f;

    function initialize() {
        reset();
    }

    function reset() as Void {
        posX = 0.0f;
        posY = 0.0f;
        heading = 0.0f;
        speedMps = 0.0f;
        totalDistance = 0.0f;
        prevMs = System.getTimer();
    }

    function resetWithHeading(initialHeading as Float) as Void {
        reset();
        heading = normalizeAngle(initialHeading);
    }

    // Main update when caller already knows dt in seconds
    // accel params kept only for signature compatibility with your existing code path
    function update(accelX as Number, accelY as Number, accelZ as Number, gyroZ as Float, magHeading as Float, dt as Float) as Void {
        updateWithSpeed(accelX, accelY, accelZ, gyroZ, magHeading, dt, speedMps);
    }

    // Preferred update path: caller supplies dt in seconds and a speed estimate in m/s
    function updateWithSpeed(accelX as Number, accelY as Number, accelZ as Number, gyroZ as Float, magHeading as Float, dt as Float, newSpeedMps as Float) as Void {
        if (dt <= 0.0f || dt > MAX_DT_SEC) {
            return;
        }

        // 1) Fuse heading:
        // - integrate gyroZ as yaw-rate if caller provides rad/s
        // - nudge toward magnetic heading with low-pass angle blend
        var predictedHeading = normalizeAngle(heading + (gyroZ * dt));
        heading = blendAngle(predictedHeading, normalizeAngle(magHeading), HEADING_ALPHA);

        // 2) Smooth speed input and clamp
        var clampedSpeed = clampFloat(newSpeedMps, MIN_SPEED_MPS, MAX_SPEED_MPS);
        speedMps = lowPass(speedMps, clampedSpeed, SPEED_ALPHA);

        // 3) Advance in world frame using heading + speed
        var dx = speedMps * Math.cos(heading) * dt;
        var dy = speedMps * Math.sin(heading) * dt;

        posX += dx;
        posY += dy;
        totalDistance += Math.sqrt((dx * dx) + (dy * dy));
    }

    // Convenience overload when you do not want to compute dt outside
    function updateAutoDt(magHeading as Float, gyroZ as Float, newSpeedMps as Float) as Void {
        var nowMs = System.getTimer();
        var dt = (nowMs - prevMs).toFloat() / 1000.0f;
        prevMs = nowMs;

        if (dt <= 0.0f || dt > MAX_DT_SEC) {
            return;
        }

        updateWithSpeed(0, 0, 0, gyroZ, magHeading, dt, newSpeedMps);
    }

    function setSpeedEstimate(newSpeedMps as Float) as Void {
        speedMps = clampFloat(newSpeedMps, MIN_SPEED_MPS, MAX_SPEED_MPS);
    }

    function setHeading(newHeading as Float) as Void {
        heading = normalizeAngle(newHeading);
    }

    function addDistanceStep(distanceMeters as Float, courseHeading as Float) as Void {
        if (distanceMeters <= 0.0f) {
            return;
        }

        var h = normalizeAngle(courseHeading);
        var dx = distanceMeters * Math.cos(h);
        var dy = distanceMeters * Math.sin(h);

        posX += dx;
        posY += dy;
        totalDistance += distanceMeters;
        heading = h;
    }

    function getDRData() as Dictionary {
        return {
            :east => posX,
            :north => posY,
            :depth => 0.0f, // keep compatibility; use pressure/altitude depth elsewhere
            :headingRad => heading,
            :headingDeg => radiansToDegrees(heading),
            :distance => totalDistance,
            :speed => speedMps
        };
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

    function blendAngle(current as Float, target as Float, alpha as Float) as Float {
        var delta = normalizeAngle(target - current);
        return normalizeAngle(current + (delta * alpha));
    }

    function radiansToDegrees(rad as Float) as Float {
        return rad * 180.0f / Math.PI;
    }
}