import Toybox.Lang;
import Toybox.Math;
import Toybox.System;

class KalmanDR {

    var x as Array<Float> = [0.0f, 0.0f, 0.0f, 0.0f];

    var P as Array<Float> = [
        1000.0f, 0.0f, 0.0f, 0.0f,
        0.0f, 1000.0f, 0.0f, 0.0f,
        0.0f, 0.0f, 100.0f, 0.0f,
        0.0f, 0.0f, 0.0f, 100.0f
    ];

    const STATE_SIZE = 4;

    const Q_PROCESS = 0.08f;
    const R_GPS_POS = 8.0f;

    var referenceLat = 0.0f;
    var referenceLon = 0.0f;
    var hasReference = false;


    // KalmanDR.mc
    const R_GPS_GOOD    = 5.0f;   // trust more
    const R_GPS_USABLE   = 25.0f; // trust less
    
    function initialize() {
        reset();
    }

    function reset() as Void {
        x = [0.0f, 0.0f, 0.0f, 0.0f];
        P = [
            1000.0f, 0.0f, 0.0f, 0.0f,
            0.0f, 1000.0f, 0.0f, 0.0f,
            0.0f, 0.0f, 100.0f, 0.0f,
            0.0f, 0.0f, 0.0f, 100.0f
        ];
        hasReference = false;
    }

    function setReference(lat as Float, lon as Float) as Void {
        referenceLat = lat;
        referenceLon = lon;
        hasReference = true;
        x[0] = 0.0f;
        x[1] = 0.0f;
    }

    private function getP(i as Number, j as Number) as Float {
        return P[i * STATE_SIZE + j];
    }

    private function setP(i as Number, j as Number, value as Float) as Void {
        P[i * STATE_SIZE + j] = value;
    }

    function predict(speedMps as Float, headingRad as Float, dt as Float) as Void {
        if (dt <= 0.0f || dt > 2.0f || speedMps <= 0.0f) {
            return;
        }

        var velEast = speedMps * Math.sin(headingRad);
        var velNorth = speedMps * Math.cos(headingRad);

        x[0] += velEast * dt;
        x[1] += velNorth * dt;
        x[2] = velEast;
        x[3] = velNorth;

        for (var i = 0; i < STATE_SIZE; i++) {
            setP(i, i, getP(i, i) + Q_PROCESS * dt);
        }
    }

    function updateGps(lat as Float, lon as Float, quality as Number) as Void {
        if (!hasReference) {
            setReference(lat, lon);
            return;
        }

        var r = (quality == Position.QUALITY_GOOD) ? R_GPS_GOOD : R_GPS_USABLE;

        var eastGps = (lon - referenceLon) * 111000.0f * Math.cos(referenceLat * Math.PI / 180.0f);
        var northGps = (lat - referenceLat) * 111000.0f;

        var innovation = eastGps - x[0];
        var gain = getP(0, 0) / (getP(0, 0) + r);
        x[0] += gain * innovation;
        setP(0, 0, getP(0, 0) * (1.0f - gain));

        innovation = northGps - x[1];
        gain = getP(1, 1) / (getP(1, 1) + r);
        x[1] += gain * innovation;
        setP(1, 1, getP(1, 1) * (1.0f - gain));
    }

    function getEast() as Float { return x[0]; }
    function getNorth() as Float { return x[1]; }

    function getDRData() as Dictionary {
        return {
            :east => x[0],
            :north => x[1],
            :distance => Math.sqrt(x[0]*x[0] + x[1]*x[1]),
            :speed => Math.sqrt(x[2]*x[2] + x[3]*x[3])
        };
    }
}