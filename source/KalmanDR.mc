import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Position;

// Compact Unscented Kalman Filter for planar dead-reckoning.
// State: [east_m, north_m, vel_east_mps, vel_north_mps]
// Predict: nonlinear kinematics from speed + heading control input.
// Update: GPS position in local EN frame.
//
// Same public API as the previous linear Kalman so the view needs no renames.
class KalmanDR {

    const N = 4;                 // state dimension
    const N_SIGMA = 9;           // 2N+1 sigma points

    // UKF parameters tuned for a constrained marine motion model: smaller sigma spread,
    // Gaussian prior, and a stable on-watch implementation.
    // alpha = 0.3 keeps sigma points tighter around the mean; beta = 2 is optimal for
    // Gaussian priors; kappa = 0 keeps the transform conservative under watch constraints.
    const ALPHA = 0.30f;
    const BETA  = 2.0f;
    const KAPPA = 0.0f;
    const LAMBDA = 0.30f * 0.30f * (N.toFloat() + KAPPA) - N.toFloat();
    const C_SCALE = 1.939f;      // sqrt(N + lambda) with alpha=0.3, kappa=0 → sqrt(3.84) ≈ 1.96

    // Process / measurement noise tuned for smoother marine motion and multipath-heavy water GPS.
    // Keep Q low enough that the filter trusts the motion model, but not so low that it drifts.
    const Q_POS   = 0.018f;      // m^2 / s  position process
    const Q_VEL   = 0.026f;      // (m/s)^2 / s  velocity process
    const R_GPS_GOOD   = 1.2f;   // m^2
    const R_GPS_USABLE = 4.0f;   // m^2
    const R_GPS_POOR   = 14.0f;  // m^2
    const Q_POS_LOSS   = 0.030f;
    const Q_VEL_LOSS   = 0.045f;
    const R_GPS_LOSS_SCALE = 2.2f;
    const MIN_PREDICT_SPEED_MPS = 0.08f;
    const MAX_PREDICT_SPEED_MPS = 2.2f;

    var x as Array<Float>;       // state mean [E, N, vE, vN]
    var P as Array<Float>;       // covariance, row-major N*N

    var Wm as Array<Float>;      // mean weights
    var Wc as Array<Float>;      // covariance weights

    var referenceLat = 0.0f;
    var referenceLon = 0.0f;
    var hasReference = false;
    var gpsLossTimeSec = 0.0f;

    // Scratch buffers – always Float-literal seeded (Monkey C rejects new[n] → Null[])
    var sigma as Array<Float>;
    var cholL as Array<Float>;   // 4x4 Cholesky scratch
    var sigmaY as Array<Float>;  // propagated sigma points

    function initialize() {
        x = [0.0f, 0.0f, 0.0f, 0.0f];
        P = [
            0.0f, 0.0f, 0.0f, 0.0f,
            0.0f, 0.0f, 0.0f, 0.0f,
            0.0f, 0.0f, 0.0f, 0.0f,
            0.0f, 0.0f, 0.0f, 0.0f
        ];
        // 9 sigma points × 4 state = 36
        sigma = [
            0.0f, 0.0f, 0.0f, 0.0f,
            0.0f, 0.0f, 0.0f, 0.0f,
            0.0f, 0.0f, 0.0f, 0.0f,
            0.0f, 0.0f, 0.0f, 0.0f,
            0.0f, 0.0f, 0.0f, 0.0f,
            0.0f, 0.0f, 0.0f, 0.0f,
            0.0f, 0.0f, 0.0f, 0.0f,
            0.0f, 0.0f, 0.0f, 0.0f,
            0.0f, 0.0f, 0.0f, 0.0f
        ];
        sigmaY = [
            0.0f, 0.0f, 0.0f, 0.0f,
            0.0f, 0.0f, 0.0f, 0.0f,
            0.0f, 0.0f, 0.0f, 0.0f,
            0.0f, 0.0f, 0.0f, 0.0f,
            0.0f, 0.0f, 0.0f, 0.0f,
            0.0f, 0.0f, 0.0f, 0.0f,
            0.0f, 0.0f, 0.0f, 0.0f,
            0.0f, 0.0f, 0.0f, 0.0f,
            0.0f, 0.0f, 0.0f, 0.0f
        ];
        cholL = [
            0.0f, 0.0f, 0.0f, 0.0f,
            0.0f, 0.0f, 0.0f, 0.0f,
            0.0f, 0.0f, 0.0f, 0.0f,
            0.0f, 0.0f, 0.0f, 0.0f
        ];
        Wm = [0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f];
        Wc = [0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f];
        initWeights();
        reset();
    }

    private function initWeights() as Void {
        // Wm0 = lambda/(N+lambda), Wc0 = Wm0 + (1-alpha^2+beta)
        var nL = N.toFloat() + LAMBDA; // = 6
        Wm[0] = LAMBDA / nL;           // 2/6 ≈ 0.333
        Wc[0] = Wm[0] + (1.0f - ALPHA * ALPHA + BETA); // 0.333 + (1-1+2) = 2.333
        var w = 1.0f / (2.0f * nL);    // 1/12 ≈ 0.0833
        for (var i = 1; i < N_SIGMA; i++) {
            Wm[i] = w;
            Wc[i] = w;
        }
    }

    function reset() as Void {
        x = [0.0f, 0.0f, 0.0f, 0.0f];
        for (var i = 0; i < N * N; i++) {
            P[i] = 0.0f;
        }
        // Large initial position uncertainty, moderate velocity
        setP(0, 0, 250.0f);
        setP(1, 1, 250.0f);
        setP(2, 2, 4.0f);
        setP(3, 3, 4.0f);
        hasReference = false;
        gpsLossTimeSec = 0.0f;
    }

    function setReference(lat as Float, lon as Float) as Void {
        referenceLat = lat;
        referenceLon = lon;
        hasReference = true;
        x[0] = 0.0f;
        x[1] = 0.0f;
        // Keep velocity; re-anchor position covariance
        setP(0, 0, 25.0f);
        setP(1, 1, 25.0f);
    }

    private function getP(i as Number, j as Number) as Float {
        return P[i * N + j];
    }

    private function setP(i as Number, j as Number, value as Float) as Void {
        P[i * N + j] = value;
    }

    // Symmetric 4x4 Cholesky: P = L L^T, returns lower-triangular L in row-major
    private function cholesky4(outL as Array<Float>) as Boolean {
        for (var i = 0; i < N; i++) {
            for (var j = 0; j <= i; j++) {
                var sum = getP(i, j);
                for (var k = 0; k < j; k++) {
                    sum -= outL[i * N + k] * outL[j * N + k];
                }
                if (i == j) {
                    if (sum <= 0.00000001f) {
                        // Numerical floor – keep filter alive
                        outL[i * N + j] = 1.0e-4f;
                    } else {
                        outL[i * N + j] = Math.sqrt(sum);
                    }
                } else {
                    var diag = outL[j * N + j];
                    if (diag < 0.00000001f && diag > -0.00000001f) {
                        outL[i * N + j] = 0.0f;
                    } else {
                        outL[i * N + j] = sum / diag;
                    }
                }
            }
            for (var j = i + 1; j < N; j++) {
                outL[i * N + j] = 0.0f;
            }
        }
        return true;
    }

    private function generateSigmaPoints() as Void {
        cholesky4(cholL);

        // sigma_0 = x
        for (var i = 0; i < N; i++) {
            sigma[i] = x[i];
        }

        // sigma_{i+1}   = x + c * L_col_i
        // sigma_{i+1+N} = x - c * L_col_i
        for (var i = 0; i < N; i++) {
            for (var j = 0; j < N; j++) {
                var col = cholL[j * N + i] * C_SCALE;
                sigma[(i + 1) * N + j]         = x[j] + col;
                sigma[(i + 1 + N) * N + j]     = x[j] - col;
            }
        }
    }

    // Nonlinear process: integrate constant-velocity driven by commanded speed/heading.
    // Control pulls velocity toward (speed*sin(h), speed*cos(h)); position integrates velocity.
    private function processModel(posE as Float, posN as Float, velE as Float, velN as Float, speedMps as Float, headingRad as Float, dt as Float, out as Array<Float>) as Void {
        var cmdVe = speedMps * Math.sin(headingRad);
        var cmdVn = speedMps * Math.cos(headingRad);

        // First-order lag on velocity (tau ≈ 0.6 s) so motion intensity changes smoothly
        var alpha = dt / (0.6f + dt);
        var ve = velE + alpha * (cmdVe - velE);
        var vn = velN + alpha * (cmdVn - velN);

        if (speedMps < MIN_PREDICT_SPEED_MPS) {
            ve *= 0.60f;
            vn *= 0.60f;
        }

        // Clamp to human-plausible speeds
        var spd = Math.sqrt(ve * ve + vn * vn);
        if (spd > MAX_PREDICT_SPEED_MPS) {
            var scale = MAX_PREDICT_SPEED_MPS / spd;
            ve *= scale;
            vn *= scale;
        }

        out[0] = posE + ve * dt;
        out[1] = posN + vn * dt;
        out[2] = ve;
        out[3] = vn;
    }

    function predict(speedMps as Float, headingRad as Float, dt as Float) as Void {
        if (dt <= 0.0f || dt > 2.0f) {
            return;
        }

        // Allow zero-speed predict (coast / stop) – still integrate velocity & inflate P
        if (speedMps < 0.0f) {
            speedMps = 0.0f;
        }
        if (speedMps > MAX_PREDICT_SPEED_MPS) {
            speedMps = MAX_PREDICT_SPEED_MPS;
        }

        generateSigmaPoints();

        // Propagate each sigma point into sigmaY
        for (var i = 0; i < N_SIGMA; i++) {
            var s0 = sigma[i * N + 0];
            var s1 = sigma[i * N + 1];
            var s2 = sigma[i * N + 2];
            var s3 = sigma[i * N + 3];
            var p = [0.0f, 0.0f, 0.0f, 0.0f];
            processModel(s0, s1, s2, s3, speedMps, headingRad, dt, p);
            sigmaY[i * N + 0] = p[0];
            sigmaY[i * N + 1] = p[1];
            sigmaY[i * N + 2] = p[2];
            sigmaY[i * N + 3] = p[3];
        }

        // Recover mean
        for (var j = 0; j < N; j++) {
            var m = 0.0f;
            for (var i = 0; i < N_SIGMA; i++) {
                m += Wm[i] * sigmaY[i * N + j];
            }
            x[j] = m;
        }

        // Recover covariance + process noise
        for (var i = 0; i < N * N; i++) {
            P[i] = 0.0f;
        }
        for (var i = 0; i < N_SIGMA; i++) {
            var de = sigmaY[i * N + 0] - x[0];
            var dn = sigmaY[i * N + 1] - x[1];
            var dve = sigmaY[i * N + 2] - x[2];
            var dvn = sigmaY[i * N + 3] - x[3];
            var w = Wc[i];
            // Outer product (symmetric)
            setP(0, 0, getP(0, 0) + w * de * de);
            setP(0, 1, getP(0, 1) + w * de * dn);
            setP(0, 2, getP(0, 2) + w * de * dve);
            setP(0, 3, getP(0, 3) + w * de * dvn);
            setP(1, 1, getP(1, 1) + w * dn * dn);
            setP(1, 2, getP(1, 2) + w * dn * dve);
            setP(1, 3, getP(1, 3) + w * dn * dvn);
            setP(2, 2, getP(2, 2) + w * dve * dve);
            setP(2, 3, getP(2, 3) + w * dve * dvn);
            setP(3, 3, getP(3, 3) + w * dvn * dvn);
        }
        // Symmetrize
        setP(1, 0, getP(0, 1));
        setP(2, 0, getP(0, 2));
        setP(3, 0, getP(0, 3));
        setP(2, 1, getP(1, 2));
        setP(3, 1, getP(1, 3));
        setP(3, 2, getP(2, 3));

        // Additive process noise (scaled by dt)
        setP(0, 0, getP(0, 0) + Q_POS * dt);
        setP(1, 1, getP(1, 1) + Q_POS * dt);
        setP(2, 2, getP(2, 2) + Q_VEL * dt);
        setP(3, 3, getP(3, 3) + Q_VEL * dt);
    }

    function predictWithTuning(speedMps as Float, headingRad as Float, dt as Float, headingConfidence as Float, motionConfidence as Number, gpsAvailable as Boolean) as Void {
        if (dt <= 0.0f || dt > 2.0f) {
            return;
        }

        var qPos = Q_POS;
        var qVel = Q_VEL;
        if (!gpsAvailable) {
            qPos = Q_POS_LOSS;
            qVel = Q_VEL_LOSS;
            gpsLossTimeSec += dt;
        } else if (headingConfidence < 0.8f) {
            qPos = Q_POS + 0.010f;
            qVel = Q_VEL + 0.012f;
        } else if (gpsLossTimeSec > 0.0f) {
            gpsLossTimeSec -= dt * 0.6f;
            if (gpsLossTimeSec < 0.0f) {
                gpsLossTimeSec = 0.0f;
            }
        }

        if (motionConfidence != null && motionConfidence < 6) {
            qPos *= 1.08f;
            qVel *= 1.08f;
        }

        var uncertaintyScale = 1.0f + (gpsLossTimeSec * 0.14f);
        if (uncertaintyScale > 1.8f) {
            uncertaintyScale = 1.8f;
        }

        // Reuse the existing predict path with a conservative covariance inflation.
        predict(speedMps, headingRad, dt);
        setP(0, 0, getP(0, 0) + qPos * dt * 0.28f * uncertaintyScale);
        setP(1, 1, getP(1, 1) + qPos * dt * 0.28f * uncertaintyScale);
        setP(2, 2, getP(2, 2) + qVel * dt * 0.28f * uncertaintyScale);
        setP(3, 3, getP(3, 3) + qVel * dt * 0.28f * uncertaintyScale);
    }

    function updateGps(lat as Float, lon as Float, quality as Number) as Void {
        if (!hasReference) {
            setReference(lat, lon);
            return;
        }

        // Water multipath and intermittent satellite visibility make GPS noisy.
        // Lower R when the fix is clean, increase heavily when it is weak or unavailable.
        var r = R_GPS_USABLE;
        if (quality == Position.QUALITY_GOOD) {
            r = R_GPS_GOOD;
        } else if (quality == Position.QUALITY_POOR) {
            r = R_GPS_POOR;
        }

        if (quality == Position.QUALITY_NOT_AVAILABLE) {
            r = R_GPS_POOR * R_GPS_LOSS_SCALE * 1.15f;
        }

        // Extra conservative scaling when the fix is marginal or the platform is at the surface.
        if (quality == Position.QUALITY_USABLE) {
            r *= 1.25f;
        }

        var cosLat = Math.cos(referenceLat * Math.PI / 180.0f);
        if (cosLat < 0.2f) {
            cosLat = 0.2f;
        }
        var eastGps  = (lon - referenceLon) * 111000.0f * cosLat;
        var northGps = (lat - referenceLat) * 111000.0f;

        // Measurement model is linear (H picks position), so we can do a
        // simplified UKF measurement update on the two position components.
        // Innovation
        var innE = eastGps - x[0];
        var innN = northGps - x[1];

        // S = P_pos + R  (2x2 diagonal R)
        var p00 = getP(0, 0) + r;
        var p11 = getP(1, 1) + r;
        var p01 = getP(0, 1);

        // det(S)
        var det = p00 * p11 - p01 * p01;
        if (det < 0.000001f && det > -0.000001f) {
            return;
        }
        var inv00 =  p11 / det;
        var inv11 =  p00 / det;
        var inv01 = -p01 / det;

        // Kalman gain K (4x2): P(:,0:1) * S^{-1}
        // Update state
        var ke0 = getP(0, 0) * inv00 + getP(0, 1) * inv01;
        var ke1 = getP(0, 0) * inv01 + getP(0, 1) * inv11;
        var kn0 = getP(1, 0) * inv00 + getP(1, 1) * inv01;
        var kn1 = getP(1, 0) * inv01 + getP(1, 1) * inv11;
        var kve0 = getP(2, 0) * inv00 + getP(2, 1) * inv01;
        var kve1 = getP(2, 0) * inv01 + getP(2, 1) * inv11;
        var kvn0 = getP(3, 0) * inv00 + getP(3, 1) * inv01;
        var kvn1 = getP(3, 0) * inv01 + getP(3, 1) * inv11;

        var gpsGainBoost = 1.0f;
        if (quality == Position.QUALITY_GOOD) {
            gpsGainBoost = 1.18f;
        } else if (quality == Position.QUALITY_USABLE) {
            gpsGainBoost = 1.10f;
        }

        x[0] += (ke0 * innE + ke1 * innN) * gpsGainBoost;
        x[1] += (kn0 * innE + kn1 * innN) * gpsGainBoost;
        x[2] += (kve0 * innE + kve1 * innN) * gpsGainBoost;
        x[3] += (kvn0 * innE + kvn1 * innN) * gpsGainBoost;

        // Joseph-form-ish covariance update for position block + cross terms
        // P = (I - K H) P   with H = [I_2  0]
        // For numerical stability on-device we deflate the measured axes and
        // gently pull cross-covariances.
        setP(0, 0, getP(0, 0) * (1.0f - ke0));
        setP(1, 1, getP(1, 1) * (1.0f - kn1));
        if (getP(0, 0) < r * 0.25f) {
            setP(0, 0, r * 0.25f);
        }
        if (getP(1, 1) < r * 0.25f) {
            setP(1, 1, r * 0.25f);
        }
        if (gpsLossTimeSec > 0.0f) {
            var recoveryBias = 1.0f + (gpsLossTimeSec * 0.08f);
            setP(0, 0, getP(0, 0) + (r * 0.12f * recoveryBias));
            setP(1, 1, getP(1, 1) + (r * 0.12f * recoveryBias));
        }
        // Soften cross terms
        setP(0, 1, getP(0, 1) * 0.85f);
        setP(1, 0, getP(0, 1));
        setP(0, 2, getP(0, 2) * 0.9f);
        setP(2, 0, getP(0, 2));
        setP(0, 3, getP(0, 3) * 0.9f);
        setP(3, 0, getP(0, 3));
        setP(1, 2, getP(1, 2) * 0.9f);
        setP(2, 1, getP(1, 2));
        setP(1, 3, getP(1, 3) * 0.9f);
        setP(3, 1, getP(1, 3));
    }

    function getEast() as Float {
        if (x == null || x[0] != x[0]) {
            return 0.0f;
        }
        return x[0];
    }

    function getNorth() as Float {
        if (x == null || x[1] != x[1]) {
            return 0.0f;
        }
        return x[1];
    }

    function getSpeed() as Float {
        var v = x[2] * x[2] + x[3] * x[3];
        if (v != v) {
            return 0.0f;
        }
        return Math.sqrt(v);
    }

    function getDRData() as Dictionary {
        var east = getEast();
        var north = getNorth();
        var dist = (east * east) + (north * north);
        if (dist != dist) {
            dist = 0.0f;
        }
        return {
            :east => east,
            :north => north,
            :distance => Math.sqrt(dist),
            :speed => getSpeed()
        };
    }
}