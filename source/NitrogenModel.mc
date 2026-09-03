import Toybox.Math;
import Toybox.Lang;

class NitrogenModel {
    // Half-life at surface (minutes)
    const SURFACE_HALF_LIFE_MIN = 120.0f;
    // Depth at which on-gassing reaches full rate
    const DEPTH_RESPONSE_M = 10.0f;
    const MAX_LOADING = 100.0f;

    // Multipliers for a simple risk model
    const DESCENT_BONUS = 1.15f;      // slightly faster uptake while descending
    const FAST_ASCENT_FACTOR = 0.70f; // slower off-gassing (higher residual risk) on fast ascent

    var loading = 0.0f;
    var maxLoading = 0.0f;
    var lastDepth = 0.0f;
    var initialized = false;

    function initialize() {
        reset();
    }

    function reset() as Void {
        loading = 0.0f;
        maxLoading = 0.0f;
        lastDepth = 0.0f;
        initialized = false;
    }

    function update(depthM as Float, dtSec as Float, isDepthActive as Boolean, ascentRateMps as Float) as Float {
        if (dtSec <= 0.0f) {
            return loading;
        }

        if (!initialized) {
            lastDepth = depthM;
            initialized = true;
        }

        // 0…1 depth factor
        var depthFactor = depthM / DEPTH_RESPONSE_M;
        if (depthFactor < 0.0f) { depthFactor = 0.0f; }
        if (depthFactor > 1.0f) { depthFactor = 1.0f; }

        // ----- On-gassing -----
        var onGas = 0.0f;
        if (isDepthActive && depthM > 0.5f) {
            // Very simple linear model: full rate at DEPTH_RESPONSE_M
            // Scale so that at 10 m you add ~1 % per minute (much more realistic)
            onGas = depthFactor * (dtSec / 60.0f) * 1.0f;   // ← was *100

            if (depthM > lastDepth) {
                onGas *= DESCENT_BONUS;
            }
        }

        // ----- Off-gassing (exponential) -----
        var halfLifeSec = SURFACE_HALF_LIFE_MIN * 60.0f;
        var offGas = 0.0f;

        if (!isDepthActive || depthM <= 0.5f) {
            // Surface: normal half-life
            offGas = loading * (1.0f - Math.pow(0.5f, dtSec / halfLifeSec));
        } else {
            // Depth mode: slower off-gassing (deeper = slower)
            var deepHalfLife = halfLifeSec * (1.0f + 2.0f * depthFactor); // up to 3× longer
            offGas = loading * (1.0f - Math.pow(0.5f, dtSec / deepHalfLife));
        }

        // Fast ascent reduces off-gassing rate → higher residual loading (risk)
        if (ascentRateMps > 0.5f) {
            offGas *= FAST_ASCENT_FACTOR;
        }

        loading = loading + onGas - offGas;

        if (loading < 0.0f) { loading = 0.0f; }
        if (loading > MAX_LOADING) { loading = MAX_LOADING; }
        if (loading > maxLoading) { maxLoading = loading; }

        lastDepth = depthM;
        return loading;
    }

    function getLoading() as Float {
        return loading;
    }

    function getMaxLoading() as Float {
        return maxLoading;
    }

    function getRiskBand() as Number {
        if (loading < 25.0f) { return 0; }
        if (loading < 50.0f) { return 1; }
        if (loading < 75.0f) { return 2; }
        return 3;
    }
}