import math
from typing import Dict, List, Optional


class DepthStateMachine:
    """Small state machine that mirrors the app's real shallow-water dive logic."""

    def __init__(self,
                 depth_noise_floor_m: float = 0.01,
                 dive_start_depth_m: float = 0.03,
                 surface_stop_depth_m: float = 0.05,
                 min_dive_duration_ms: int = 0):
        self.depth_noise_floor_m = depth_noise_floor_m
        self.dive_start_depth_m = dive_start_depth_m
        self.surface_stop_depth_m = surface_stop_depth_m
        self.min_dive_duration_ms = min_dive_duration_ms
        self.is_underwater = False
        self.dive_start_confidence = 0
        self.dive_stop_confidence = 0

    def process(self, depth_m: float, is_recording: bool = True,
                at_entry_position: bool = False) -> bool:
        if not is_recording:
            self.is_underwater = False
            self.dive_start_confidence = 0
            self.dive_stop_confidence = 0
            return False

        if not self.is_underwater:
            if depth_m > self.dive_start_depth_m and depth_m <= 200.0:
                self.dive_start_confidence += 1
                self.dive_stop_confidence = 0
                if self.dive_start_confidence >= 1:
                    self.is_underwater = True
                    self.dive_start_confidence = 0
                    self.dive_stop_confidence = 0
                    return True
            else:
                self.dive_start_confidence = 0
                self.dive_stop_confidence = 0
            return False

        near_surface = depth_m <= self.surface_stop_depth_m
        if near_surface and at_entry_position:
            self.dive_stop_confidence += 1
            if self.dive_stop_confidence >= 1:
                self.is_underwater = False
                self.dive_stop_confidence = 0
                self.dive_start_confidence = 0
                return False
        else:
            self.dive_stop_confidence = 0
        return True


def safe_numeric(value: float, default: float = 0.0) -> float:
    if value is None:
        return default
    try:
        if not math.isfinite(float(value)):
            return default
    except (TypeError, ValueError):
        return default
    return float(value)


class DeadReckoningSimulator:
    """Pure-Python model of the motion step used by the app."""

    def __init__(self):
        self.east_m = 0.0
        self.north_m = 0.0
        self.heading_rad = 0.0
        self.speed_mps = 0.0

    def step(self, east_m: float, north_m: float, speed_mps: float,
             heading_rad: float, dt_sec: float) -> Dict[str, float]:
        speed = safe_numeric(speed_mps)
        if speed <= 0.0 or dt_sec <= 0.0:
            return {'east_m': safe_numeric(east_m), 'north_m': safe_numeric(north_m), 'distance_m': 0.0}

        step_e = speed * math.sin(heading_rad) * dt_sec
        step_n = speed * math.cos(heading_rad) * dt_sec
        self.east_m = safe_numeric(east_m + step_e)
        self.north_m = safe_numeric(north_m + step_n)
        distance = math.hypot(step_e, step_n)
        return {
            'east_m': self.east_m,
            'north_m': self.north_m,
            'distance_m': safe_numeric(distance),
        }


class DiveTrajectoryGenerator:
    """Generate a realistic shallow-water dive trajectory with surface, descent, swim, and ascent phases."""

    def __init__(self, dt_sec: float = 1.0, sample_rate_hz: float = 1.0):
        self.dt_sec = dt_sec
        self.sample_rate_hz = sample_rate_hz

    def generate(self, duration_sec: int = 120, start_east: float = 0.0, start_north: float = 0.0,
                 heading_deg: float = 12.0, travel_speed_mps: float = 0.45,
                 start_depth_m: float = 0.0, max_depth_m: float = 0.8) -> List[Dict[str, float]]:
        if duration_sec <= 0:
            return []

        samples: List[Dict[str, float]] = []
        heading_rad = math.radians(heading_deg)
        sim = DeadReckoningSimulator()
        east = start_east
        north = start_north

        for t in range(0, duration_sec, int(self.dt_sec * self.sample_rate_hz)):
            phase = t / max(1, duration_sec)
            if phase < 0.18:
                depth = start_depth_m + (phase / 0.18) * 0.08
                speed = 0.10
            elif phase < 0.5:
                depth = 0.08 + (phase - 0.18) / 0.32 * max_depth_m
                speed = travel_speed_mps
            elif phase < 0.72:
                depth = max_depth_m - (phase - 0.5) / 0.22 * max_depth_m * 0.7
                speed = travel_speed_mps * 0.9
            elif phase < 0.9:
                depth = 0.12 + (0.9 - phase) / 0.18 * 0.08
                speed = 0.18
            else:
                depth = 0.0
                speed = 0.0

            step = sim.step(east, north, speed, heading_rad, self.dt_sec)
            east = step['east_m']
            north = step['north_m']
            samples.append({
                't_sec': float(t),
                'depth_m': safe_numeric(depth),
                'speed_mps': safe_numeric(speed),
                'heading_deg': safe_numeric(math.degrees(heading_rad)),
                'east_m': safe_numeric(east),
                'north_m': safe_numeric(north),
                'is_underwater': depth > 0.03,
            })

        return samples


def simulate_underwater_run(depth_samples: List[float],
                           at_entry_position_sequence: Optional[List[bool]] = None) -> List[bool]:
    machine = DepthStateMachine()
    out: List[bool] = []
    if at_entry_position_sequence is None:
        at_entry_position_sequence = [False] * len(depth_samples)
    for idx, d in enumerate(depth_samples):
        at_entry = at_entry_position_sequence[idx] if idx < len(at_entry_position_sequence) else False
        out.append(machine.process(safe_numeric(d), is_recording=True, at_entry_position=at_entry))
    return out


if __name__ == '__main__':
    # Quick self-check
    print('Depth test:', simulate_underwater_run([0.00, 0.04, 0.06, 0.05, 0.00, 0.01, 0.00], [False, False, False, False, True, True, True]))
    pos = DeadReckoningSimulator().step(0.0, 0.0, 0.7, 0.0, 1.0)
    print('DR:', pos)
    trajectory = DiveTrajectoryGenerator(dt_sec=1.0).generate(duration_sec=60)
    print('Generated samples:', len(trajectory), 'first depth:', trajectory[0]['depth_m'], 'last depth:', trajectory[-1]['depth_m'])
