# Unscented Kalman Filter (UKF) for Dead Reckoning  
## gsensros – Garmin Connect IQ (Instinct 2 / 2X)

**Document version:** 1.0  
**Code modules:** `KalmanDR.mc`, `gsensrosView.mc`, `DeadReckoning.mc`  
**Purpose:** Document how the UKF is formulated, driven by sensors, and written into FIT / UI fields.

---

## 1. Why a UKF?

Underwater (and in GPS-denied surface segments) the watch has no reliable absolute position. The app therefore **propagates** position from estimated speed and heading, and **corrects** when a GPS fix is available.

A classical linear Kalman filter assumes linear dynamics. Here the kinematics are nonlinear:

\[
v_E = v \sin(\psi),\quad v_N = v \cos(\psi)
\]

\[
E_{k+1} = E_k + v_E\,\Delta t,\quad N_{k+1} = N_k + v_N\,\Delta t
\]

The **Unscented Kalman Filter** propagates a small set of carefully chosen sample points (*sigma points*) through this nonlinear model, then reconstructs mean and covariance. That avoids Jacobian linearisation and is more accurate for heading/speed-driven motion on a wrist-worn device.

The class is still named `KalmanDR` so the rest of the app keeps the same API (`predict`, `updateGps`, `getEast`, `getNorth`, `getDRData`).

---

## 2. State vector

Four-dimensional state in a **local East–North** frame anchored at dive/session entry:

| Index | Symbol | Unit | Meaning |
|------:|--------|------|---------|
| 0 | \(E\) | m | East displacement from reference |
| 1 | \(N\) | m | North displacement from reference |
| 2 | \(v_E\) | m/s | East velocity |
| 3 | \(v_N\) | m/s | North velocity |

Internal representation:

```text
x = [east_m, north_m, vel_east_mps, vel_north_mps]
P = 4×4 covariance (row-major float array)
```

**Reference origin** (`referenceLat`, `referenceLon`) is set at session start from the entry GPS fix (`setReference`), or on the first usable GPS update if entry had no fix.

Geographic conversion (approx.):

\[
E = (\lambda - \lambda_0)\,111000\cos\varphi_0
\]
\[
N = (\varphi - \varphi_0)\,111000
\]

with \(\varphi,\lambda\) in degrees.

---

## 3. UKF parameters (as implemented)

| Parameter | Value | Role |
|-----------|------:|------|
| \(n\) (state dim) | 4 | |
| Sigma points | \(2n+1 = 9\) | |
| \(\alpha\) | 1.0 | Spread of sigma points |
| \(\kappa\) | 2.0 | Secondary scaling |
| \(\beta\) | 2.0 | Prior knowledge of distribution (Gaussian → 2) |
| \(\lambda\) | \(\alpha^2(n+\kappa)-n = 2\) | Composite scaling |
| \(c = \sqrt{n+\lambda}\) | \(\sqrt{6} \approx 2.449\) | Cholesky column scale |

**Mean / covariance weights**

\[
W_m^{(0)} = \frac{\lambda}{n+\lambda} \approx 0.333,\quad
W_c^{(0)} = W_m^{(0)} + (1-\alpha^2+\beta) \approx 2.333
\]

\[
W_m^{(i)} = W_c^{(i)} = \frac{1}{2(n+\lambda)} \approx 0.0833,\quad i=1\ldots 8
\]

These values keep weights **positive** and numerically stable on Monkey C (no large negative \(W_m^{(0)}\)).

---

## 4. Process model (prediction)

### 4.1 Control inputs

Every timer tick (~0.5 s) while recording:

| Input | Source in `gsensrosView` |
|-------|---------------------------|
| \(v\) (commanded speed, m/s) | `getEstimatedSpeedMps()` → motion intensity or GPS speed; forced to 0 if `isStationary()` |
| \(\psi\) (heading, rad) | `getBestHeading(dt)` → true heading, else magnetometer, else integrated estimate |
| \(\Delta t\) | Timer delta, clamped to (0, 2] s |

### 4.2 Nonlinear process \(f(x,u)\)

For each sigma point \(s = [E, N, v_E, v_N]\):

1. Commanded velocity from controls:
   \[
   v_E^{\mathrm{cmd}} = v\sin\psi,\quad v_N^{\mathrm{cmd}} = v\cos\psi
   \]
2. First-order lag toward command (\(\tau \approx 0.6\,\mathrm{s}\)):
   \[
   \alpha = \frac{\Delta t}{0.6+\Delta t}
   \]
   \[
   v_E \leftarrow v_E + \alpha(v_E^{\mathrm{cmd}} - v_E)
   \]
   (same for \(v_N\))
3. Speed clamp: \(\sqrt{v_E^2+v_N^2} \le 2.5\,\mathrm{m/s}\)
4. Position integrate:
   \[
   E \leftarrow E + v_E\Delta t,\quad N \leftarrow N + v_N\Delta t
   \]

### 4.3 Sigma-point pipeline

1. **Cholesky** of \(P = LL^\top\) (4×4, with a small floor on diagonal for numerical safety).
2. Form sigma points:
   \[
   \mathcal{X}^{(0)} = \hat{x},\quad
   \mathcal{X}^{(i)} = \hat{x} + c\,L_{:i},\quad
   \mathcal{X}^{(i+n)} = \hat{x} - c\,L_{:i}
   \]
3. Propagate each through \(f(\cdot)\).
4. Recover predicted mean \(\hat{x}^-\) with \(W_m\).
5. Recover predicted covariance \(P^-\) with \(W_c\), then add process noise:
   - \(Q_{\mathrm{pos}} = 0.15\,\mathrm{m}^2/\mathrm{s}\) on \(E,N\) (× \(\Delta t\))
   - \(Q_{\mathrm{vel}} = 0.25\,(\mathrm{m/s})^2/\mathrm{s}\) on \(v_E,v_N\) (× \(\Delta t\))

### 4.4 Call site

```text
timerCallback (recording, not calibrating):
  estSpeed   = getEstimatedSpeedMps()
  bestHeading = getBestHeading(dt)
  if stationary → estSpeed = 0
  kalman.predict(estSpeed, heading, dt)
  if usable GPS → kalman.updateGps(lat, lon, quality)
```

So the filter **always predicts**; GPS is an optional measurement update on the same tick.

---

## 5. Measurement model (GPS update)

### 5.1 Measurement

When `hasGpsFix` and quality is usable/good:

\[
z = \begin{bmatrix} E_{\mathrm{GPS}} \\ N_{\mathrm{GPS}} \end{bmatrix}
\]

from the same local EN conversion as the reference.

### 5.2 Noise \(R\) by quality

| GPS quality | \(R\) (m², per axis) |
|-------------|----------------------:|
| GOOD | 4 |
| USABLE (default) | 20 |
| POOR | 60 |

### 5.3 Update form

Position measurement is linear in state (\(H\) picks \(E,N\)). Implementation uses a compact gain on the position block and cross-covariance terms with velocity:

- Innovation: \(z - [E,N]\)
- \(S = P_{pos} + R\)
- Kalman gain from \(P\) columns for states 0…3 vs position
- State corrected; position variances deflated; cross-terms softened for stability on-device

No full Joseph form is used (cost/memory on Instinct); floors prevent \(P\) from collapsing to zero.

---

## 6. Parallel dead-reckoning path

`DeadReckoning.mc` still runs when `shouldAdvanceDR(heading, speed)` is true. It is a **separate**, heading-smoothed integrator used as fallback and for comparison.

**Primary track for FIT and UI “KF E / KF N”** is the **UKF** (`kalman.getEast()` / `getNorth()`).

| Component | Role |
|-----------|------|
| `KalmanDR` (UKF) | Fused EN track + velocity; GPS-corrected |
| `DeadReckoning` | Classic DR with gyro/heading blend; advanced only when moving with valid heading |

---

## 7. Inputs that drive the UKF (sensor → filter)

These are **not** UKF state components, but they feed the control vector \((v,\psi)\):

| Quantity | Origin | Notes |
|----------|--------|--------|
| Speed estimate | GPS if ≥ 0.35 m/s; else continuous map from `motionScoreMg` (swim/land ranges) | Smoothed (`filteredSpeedEst`); decay when stationary |
| Motion score | Accel high-pass variance + gyro magnitude, adaptive baseline | Underwater vs land thresholds |
| Heading | `Sensor.Info.heading` preferred; else magnetometer | Gyro bias calibration at startup |
| Stationary flag | Low GPS speed, low gyro magnitude, no motion detect | Forces \(v=0\) into `predict` |
| GPS lat/lon/quality | `Position` API | Measurement update only |

Depth, N₂, HR, etc. are **orthogonal** to the UKF (dive/health metrics).

---

## 8. Outputs and FIT developer fields

### 8.1 Direct UKF outputs

| App / UI label | Source | FIT field name | FIT field ID | Type | Units |
|----------------|--------|----------------|-------------:|------|-------|
| KF E | `kalman.getEast()` | `DR_East` | 0 | FLOAT | m |
| KF N | `kalman.getNorth()` | `DR_North` | 1 | FLOAT | m |
| (derived) distance | \(\sqrt{E^2+N^2}\) via `getDRData()` | — | — | — | m (UI only) |
| (derived) filter speed | \(\sqrt{v_E^2+v_N^2}\) | — | — | — | m/s (not logged as separate FIT field) |

Synthetic geographic track from UKF EN + entry reference:

| FIT field | ID | How computed |
|-----------|---:|--------------|
| `DR_Lat` | 9 | \(\varphi_0 + N / 111000\) |
| `DR_Lon` | 10 | \(\lambda_0 + E / (111000\cos\varphi_0)\) |

Written in `writeFitFieldsIfNeeded` when `hasEntryPosition` is true.

### 8.2 Related FIT fields (feed or accompany UKF, not state)

| FIT field | ID | Relationship to UKF |
|-----------|---:|---------------------|
| `Speed` | 3 | Control input \(v\) (estimated or GPS), not UKF \(v_E,v_N\) magnitude |
| `Heading` | 4 | Control input \(\psi\) (degrees) |
| `Motion` | 6 | Drives speed estimate when GPS is weak |
| `Moving` | 7 | Gating / stationary logic |
| `GpsFix` | 8 | Whether GPS update ran this epoch |
| `Underwater` | 5 | Mode switch for motion→speed map |
| `Depth` | 2 | Independent baro/pressure pipeline |

### 8.3 POI fields (use UKF position at mark time)

When CTRL / Light marks a POI:

| FIT field | ID | Content |
|-----------|---:|---------|
| `POI_Id` | 11 | 1-based index |
| `POI_Lat` | 12 | GPS if available, else synth from entry + UKF \(N,E\) |
| `POI_Lon` | 13 | Same for longitude |

East/north at POI time are taken from `kalman.getEast()` / `getNorth()` for synthesis; they are not separate FIT fields (device field-count limit).

### 8.4 Fields intentionally **not** created as FIT (UI only)

N₂ load/max/band, HR, ascent rate, SpO₂, temperature, raw GPS lat/lon developer fields, session max-depth / dive-time summaries — removed from FIT creation to stay under Instinct’s ~16 developer-field limit. Values may still appear on the watch face.

---

## 9. Lifecycle

```text
onShow / startSession
  → kalman.reset()
  → if entry GPS: kalman.setReference(entryLat, entryLon)
       (zeros E,N; tightens position covariance)

each TIMER_PERIOD_MS (500 ms) while recording
  → sensors, depth, GPS, motion confidence
  → estSpeed, bestHeading
  → kalman.predict(...)
  → optional kalman.updateGps(...)
  → every 2 ticks: writeFitFieldsIfNeeded → DR_East, DR_North, DR_Lat, DR_Lon, ...

stopSession
  → session saved; fields cleared
```

---

## 10. Design constraints (Monkey C / Instinct)

1. **No matrix library** — 4×4 Cholesky and outer products are hand-written.
2. **No `new [n]` for `Array<Float>`** — all buffers seeded with float literals (Null arrays are illegal assignments).
3. **~16 FIT developer fields** — UKF-related set kept minimal (East, North, Lat, Lon + controls/POI).
4. **CPU** — 9 sigma points × light kinematics at 2 Hz is acceptable on Instinct 2X.
5. **GPS quality** scales \(R\) so good fixes pull the track hard; poor fixes barely move it.

---

## 11. Tuning cheat sheet

| Symptom | Lever |
|---------|--------|
| Track lag vs GPS | Lower \(R_{\mathrm{GOOD}}\) or raise process \(Q\) slightly |
| Jitter when GPS flickers | Raise \(R_{\mathrm{USABLE}}\) / \(R_{\mathrm{POOR}}\) |
| Drift underwater too fast | Lower max swim speed map; raise stationary strictness |
| Overshoot on turns | Velocity lag \(\tau\) (currently 0.6 s); heading source quality |
| Covariance collapse | Position variance floor after GPS update |

Constants live at the top of `KalmanDR.mc` (`Q_POS`, `Q_VEL`, `R_GPS_*`, UKF \(\alpha,\kappa,\beta\)).

---

## 12. Summary diagram

```text
  Accel/Gyro ──► motion score ──► speed estimate ──┐
  Mag / Heading ──────────────────► heading ψ ────┼──► UKF predict
  GPS lat/lon/quality ──────────────► EN measurement ──► UKF update
                                                      │
                                                      ▼
                                              state [E,N,vE,vN]
                                                      │
                          ┌───────────────────────────┼───────────────────┐
                          ▼                           ▼                   ▼
                     FIT DR_East/North          FIT DR_Lat/Lon         UI KF E/N
                     POI synth lat/lon          (from entry+EN)
```

---

## 13. File map

| File | Responsibility |
|------|----------------|
| `KalmanDR.mc` | Full UKF: sigma points, predict, GPS update, getters |
| `gsensrosView.mc` | Timer loop, speed/heading/motion, FIT write, POI mark, UI |
| `DeadReckoning.mc` | Secondary classical DR integrator |
| `gsensrosDelegate.mc` | Buttons (Select, Light/CTRL → POI, scroll) |

---

*End of document.*
