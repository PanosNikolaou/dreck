import math
import os
import unittest

from simulations.gsensros_sim import (
    DepthStateMachine,
    DeadReckoningSimulator,
    DiveTrajectoryGenerator,
    safe_numeric,
    simulate_underwater_run,
)


class TestGsensrosSimulationSuite(unittest.TestCase):
    def test_depth_thresholds_accept_shallow_dives(self):
        machine = DepthStateMachine()
        self.assertFalse(machine.process(0.0, is_recording=True, at_entry_position=False))
        self.assertTrue(machine.process(0.04, is_recording=True, at_entry_position=False))
        self.assertTrue(machine.process(0.02, is_recording=True, at_entry_position=False))
        self.assertFalse(machine.process(0.0, is_recording=True, at_entry_position=True))

    def test_surface_hysteresis_is_stable(self):
        trajectory = [0.00, 0.04, 0.06, 0.05, 0.00, 0.01, 0.00]
        entry_flags = [False, False, False, False, True, True, True]
        states = simulate_underwater_run(trajectory, entry_flags)
        self.assertTrue(states[1])
        self.assertTrue(states[2])
        self.assertTrue(states[3])
        self.assertFalse(states[-1])

    def test_non_finite_values_are_sanitized(self):
        self.assertEqual(safe_numeric(float('nan')), 0.0)
        self.assertEqual(safe_numeric(float('inf')), 0.0)
        self.assertEqual(safe_numeric(-float('inf')), 0.0)
        self.assertAlmostEqual(safe_numeric(1.5), 1.5)

    def test_dead_reckoning_step_stays_finite(self):
        sim = DeadReckoningSimulator()
        result = sim.step(east_m=0.0, north_m=0.0, speed_mps=0.7, heading_rad=0.0, dt_sec=1.0)
        self.assertTrue(math.isfinite(result['east_m']))
        self.assertTrue(math.isfinite(result['north_m']))
        self.assertTrue(math.isfinite(result['distance_m']))
        self.assertGreater(result['distance_m'], 0.0)

    def test_fit_files_are_optional_but_should_be_collectable(self):
        fit_dir = os.path.join(os.path.dirname(__file__), '..', 'fit')
        self.assertTrue(os.path.isdir(fit_dir), 'fit directory should exist for analysis checks')

        sample_files = [
            os.path.join(fit_dir, name)
            for name in os.listdir(fit_dir)
            if name.lower().endswith('.fit')
        ]
        self.assertGreater(len(sample_files), 0, 'at least one FIT sample should be present')

    def test_shallow_diving_trajectory_stays_valid(self):
        traj = DiveTrajectoryGenerator(dt_sec=1.0).generate(duration_sec=30)
        self.assertGreater(len(traj), 5)
        depths = [sample['depth_m'] for sample in traj]
        self.assertTrue(any(d > 0.03 for d in depths))
        self.assertTrue(any(d <= 0.05 for d in depths))


if __name__ == '__main__':
    unittest.main()
