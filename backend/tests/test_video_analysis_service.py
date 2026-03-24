import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from video_analysis_service import _assign_rules, _project_event_shape


class AssignRulesTests(unittest.TestCase):
    def test_prefers_human_interaction_rule_when_person_present(self):
        rule, secondary = _assign_rules(
            {
                "contains_person": True,
                "pet_visible": True,
                "zone_guess": "door",
                "body_state_hint": "moving",
                "behavior_tags": ["waiting"],
            },
            {"max_motion": 0.01, "max_speed": 0.03, "max_novelty": 0.01, "max_edge_bias": 0.2},
        )

        self.assertEqual(rule, "R12")
        self.assertIn("R08", secondary)

    def test_maps_food_zone_to_food_rule(self):
        rule, secondary = _assign_rules(
            {
                "contains_person": False,
                "pet_visible": True,
                "zone_guess": "food",
                "body_state_hint": "standing",
                "behavior_tags": ["eating"],
            },
            {"max_motion": 0.005, "max_speed": 0.02, "max_novelty": 0.002, "max_edge_bias": 0.1},
        )

        self.assertEqual(rule, "R05")
        self.assertEqual(secondary, [])

    def test_falls_back_to_unknown_rule(self):
        rule, secondary = _assign_rules(
            {
                "contains_person": False,
                "pet_visible": False,
                "zone_guess": "unknown",
                "body_state_hint": "unknown",
                "behavior_tags": [],
            },
            {"max_motion": 0.0, "max_speed": 0.0, "max_novelty": 0.0, "max_edge_bias": 0.0},
        )

        self.assertEqual(rule, "R18")
        self.assertEqual(secondary, [])


class ProjectEventShapeTests(unittest.TestCase):
    def test_sleeping_rule_projects_sleeping_event(self):
        event_type, description = _project_event_shape(
            "R10",
            {
                "clip_summary": "趴在沙发上打盹",
                "actions": [{"label": "休息"}],
                "body_state": {"state": "sleeping"},
            },
        )

        self.assertEqual(event_type, "sleeping")
        self.assertEqual(description, "趴在沙发上打盹")

    def test_high_motion_rule_prefers_zoomies_when_running_text_exists(self):
        event_type, _ = _project_event_shape(
            "R03",
            {
                "clip_summary": "突然在客厅里飞快跑了一圈",
                "actions": [{"label": "跑酷"}],
                "body_state": {"state": "moving"},
            },
        )

        self.assertEqual(event_type, "zoomies")


if __name__ == "__main__":
    unittest.main()
