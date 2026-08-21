# UKF dead reckoning documentation

## Purpose

This document describes the final UKF implementation used by the Garmin Connect IQ dive app. The class is `KalmanDR` and it is used to estimate local East/North motion when GPS is weak, stale, or unavailable.

## State vector

The filter state is a local tangent-plane model:

$$
\mathbf{x} = \begin{bmatrix}
E \\
N \\
v_E \\
v_N
\end{bmatrix}
$$

where:

- $E$ = East displacement from a reference point
- $N$ = North displacement from a reference point
- $v_E$ = East velocity
- $v_N$ = North velocity

The reference origin is set from a session entry GPS fix or first usable GPS update.

## UKF tuning used in the final code

The final implementation uses the following conservative settings:

- $\alpha = 0.30$
- $\beta = 2.0$
- $\kappa = 0.0$
- $Q_{pos} = 0.018$
- $Q_{vel} = 0.026$
- $R_{gps,good} = 1.2$
- $R_{gps,usable} = 4.0$
- $R_{gps,poor} = 14.0$

These values are intentionally smooth and conservative. Water GPS is noisy and can suffer from multipath, so the filter is designed not to over-trust weak updates.

## Prediction model

The process model uses the best available motion command from the app:

- estimated speed from GPS or motion heuristics
- heading from the best valid source
- timer delta $\Delta t$

The kinematic update is:

$$
v_E^{cmd} = v \sin(\psi), \quad v_N^{cmd} = v \cos(\psi)
$$

and the predicted state uses a local constant-velocity integration step:

$$
E_{k+1} = E_k + v_E \Delta t
$$

$$
N_{k+1} = N_k + v_N \Delta t
$$

with a first-order lag toward the commanded velocity to avoid abrupt changes from noisy motion estimates.

## GPS update model

When a GPS fix is usable, the filter updates the position state in local EN coordinates. This is a low-cost measurement update and it helps anchor the track without letting noisy water GPS dominate the solution.

The noise terms increase with fix quality degradation:

- good fix: small noise
- usable fix: moderate noise
- poor fix: much larger noise

This pattern keeps the filter stable while still allowing valid GPS data to correct drift.

## How the app drives the UKF

The app calls the filter every timer tick while recording. The relevant inputs are:

- estimated speed from the current motion model
- heading from true/mag/gyro sources
- GPS fix if available and quality is acceptable
- stationary detection to force speed toward zero when movement is absent

The UKF is therefore a local motion tracker, not a stand-alone navigation engine.

## Relationship to the fallback DR path

A separate `DeadReckoning` module is still maintained, but the main position used for the app is the UKF state. The fallback DR path remains useful when the UKF is unavailable or when the app needs a simpler sanity check.

## FIT output connection

The UKF outputs are written as:

- `DR_East`
- `DR_North`
- `DR_Lat`
- `DR_Lon`

These are derived from the local EN position and the session reference point. This allows the app to store a synthetic track even when GPS is intermittent.

## Limitations

The UKF is intentionally conservative because the app is built for a watch and a real-world dive environment. Limitations include:

- 2-D horizontal motion only
- local reference frame, not a global geodetic solution
- heuristic speed estimation when GPS is absent
- sensitivity to invalid heading or poor GPS quality

## Final note

The current implementation is the authoritative version of the UKF for this project. It reflects the actual code in `KalmanDR.mc` and the verified build status for the app.


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
