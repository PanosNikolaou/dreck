NitrogenModel Class Documentation
Connect IQ / Monkey C
Simple tissue-loading risk model for dive tracking applications.

Overview
NitrogenModel is a lightweight, real-time nitrogen loading estimator designed
for Garmin Connect IQ dive / surface trackers.
It is NOT a full decompression algorithm (no Bühlmann, no VPM, no formal
M-values). Instead it provides a continuous 0–100 % loading score and a
discrete risk band that can be logged to FIT files and displayed on the watch.
Typical use cases:

Live on-screen nitrogen risk indicator
FIT custom fields (N2_Load, N2_Load_Max, N2_Risk_Band)
Post-dive analysis of residual loading


Class Declaration
import Toybox.Math;
import Toybox.Lang;
class NitrogenModel {
// ...
}

Constants
SURFACE_HALF_LIFE_MIN   = 120.0f
Approximate half-life of the modelled compartment at the surface (minutes).
DEPTH_RESPONSE_M        = 10.0f
Depth (metres) at which on-gassing reaches its full rate.
MAX_LOADING             = 100.0f
Hard ceiling for the loading value (%).
DESCENT_BONUS           = 1.15f
Multiplier applied to on-gassing while the diver is descending.
FAST_ASCENT_FACTOR      = 0.70f
Multiplier applied to off-gassing when ascent rate exceeds 0.5 m/s
(reduces off-gassing → higher residual risk).

Member Variables
loading      (Float)   Current nitrogen loading (0.0 – 100.0 %).
maxLoading   (Float)   Highest loading reached during the current session.
lastDepth    (Float)   Depth recorded on the previous update call
(used for descent detection).
initialized  (Boolean) Internal flag – first call to update() initialises
the depth baseline.

Public Methods
initialize()
Constructor. Calls reset() so the object starts in a clean state.
reset() as Void
Resets all internal state:
loading     → 0.0
maxLoading  → 0.0
lastDepth   → 0.0
initialized → false
Call this at the beginning of a new dive session or after the diver has
fully surfaced and recovered.
update(depthM as Float, dtSec as Float, isUnderwater as Boolean,
ascentRateMps as Float) as Float
Core update function – must be called regularly
(recommended every 0.5–1.0 s).
Parameters:
depthM         Current depth in metres (positive = underwater).
dtSec          Time delta since last call, in seconds. Must be > 0.
isUnderwater   true when the diver is considered submerged.
ascentRateMps  Vertical speed in m/s. Positive = ascending.
Returns:
Current loading value after the update (0.0 – 100.0).
Behaviour summary:

On-gassing (only when isUnderwater && depthM > 0.5)
Rate proportional to depth (full rate at 10 m).
Extra 15 % bonus while descending.
Nominal rate ≈ 1 % per minute at 10 m.

Off-gassing
Surface / shallow (< 0.5 m): exponential decay with 120 min
half-life.
Underwater: longer half-life (up to 3×) proportional to depth.
Fast ascent (> 0.5 m/s) reduces off-gassing rate by 30 %
→ higher residual loading.

Loading is clamped to [0, 100].
maxLoading is updated if a new peak is reached.

getLoading() as Float
Returns the current loading percentage (0.0 – 100.0).
getMaxLoading() as Float
Returns the highest loading value observed since the last reset().
getRiskBand() as Number
Returns a discrete risk band based on current loading:
Band 0   0 – 24.9 %     Low / green
Band 1  25 – 49.9 %     Moderate / yellow
Band 2  50 – 74.9 %     Elevated / orange
Band 3  75 – 100 %      High / red

Typical Integration (from gsensrosView)
// In timer callback (every ~0.5 s)
var ascentRateMps = 0.0f;
if (dt > 0.0f) {
ascentRateMps = (lastDepthForAscent - currentDepth) / dt;
}
lastDepthForAscent = currentDepth;
if (n2Model != null) {
n2Model.update(currentDepth, dt, isUnderwater, ascentRateMps);
}
// Later when writing FIT fields
lastFitN2Load = writeFloatField(n2LoadField, n2Model.getLoading(),
lastFitN2Load, 0.1f);
lastFitN2Max  = writeFloatField(n2MaxField,  n2Model.getMaxLoading(),
lastFitN2Max, 0.1f);
lastFitN2Band = writeUIntField(n2BandField,  n2Model.getRiskBand(),
lastFitN2Band);

Design Notes & Limitations

This is a single-compartment toy model, not a medical-grade decompression
algorithm.
On-gassing and off-gassing rates are deliberately simplified for real-time
watch performance and easy interpretation.
No surface interval credit beyond the exponential decay is modelled.
No multi-tissue or bubble modelling is present.
The model intentionally increases residual loading on fast ascents to
reflect elevated risk.
Suitable for logging and UI indication only.
Do NOT use for actual dive planning or decompression decisions.


Version History
Version 1.0  –  2026-07-25
Initial documented version with corrected exponential off-gassing and
realistic on-gassing rates.
End of documentation