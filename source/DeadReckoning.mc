import Toybox.Lang;
import Toybox.Math;
import Toybox.Time;

class DeadReckoning {
    var posX = 0.0f;   // East (meters)
    var posY = 0.0f;   // North (meters)
    var depth = 0.0f;
    var heading = 0.0f; // radians

    var velocityX = 0.0f;
    var velocityY = 0.0f;

    var prevTime = 0;
    var gravity = 9.81f;
    var accelScale = 0.0012f; // tuned a bit

    var totalDistance = 0.0f; // cumulative distance

    function initialize() {
        reset();
    }

    function reset() as Void {
        posX = 0.0f;
        posY = 0.0f;
        depth = 0.0f;
        velocityX = 0.0f;
        velocityY = 0.0f;
        totalDistance = 0.0f;
        prevTime = Time.now().value();
    }

    function update(accelX as Number, accelY as Number, accelZ as Number, gyroZ as Float, magHeading as Float, dt as Float) as Void {
        if (dt <= 0 || dt > 2) { return; }

        var ax = accelX.toFloat() * accelScale;
        var ay = accelY.toFloat() * accelScale;
        var az = accelZ.toFloat() * accelScale - gravity;

        velocityX += ax * dt;
        velocityY += ay * dt;

        // Apply heading
        var vx = velocityX * Math.cos(heading) - velocityY * Math.sin(heading);
        var vy = velocityX * Math.sin(heading) + velocityY * Math.cos(heading);

        var dx = vx * dt;
        var dy = vy * dt;

        posX += dx;
        posY += dy;

        // Update total distance
        totalDistance += Math.sqrt(dx*dx + dy*dy);

        depth += az * dt * dt * 0.5f;

        heading = magHeading; // Use magnetometer
    }

    function getDRData() as Dictionary {
        return {
            :east => posX,
            :north => posY,
            :depth => depth,
            :headingDeg => heading * 180 / Math.PI,
            :distance => totalDistance
        };
    }
}