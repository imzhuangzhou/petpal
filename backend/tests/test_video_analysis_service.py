import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from video_analysis_service import _assign_rules, _project_event_shape, build_clip_debug_payload


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


class BuildClipDebugPayloadTests(unittest.TestCase):
    @patch("video_analysis_service.query_db")
    def test_builds_complete_clip_debug_payload(self, mock_query_db):
        mock_query_db.side_effect = [
            {
                "id": 8,
                "job_id": "job-1",
                "camera_id": 2,
                "pet_id": 3,
                "rule_id": "R12",
                "primary_rule": "人宠互动候选",
                "secondary_rules_json": '["R03"]',
                "source_video_start_seconds": 12.0,
                "source_video_end_seconds": 19.5,
                "clip_url": "/media/clips/8.mp4",
                "thumbnail_url": "/frames/8.jpg",
                "analysis_status": "completed",
                "summary": "主人靠近后，小狗兴奋地迎了上去。",
                "actions_json": '[{"label":"靠近主人","confidence":0.9}]',
                "body_state_json": '{"state":"standing"}',
                "appearance_json": '{"outfit":"黄色背心"}',
                "interaction_json": '{"contains_person":true}',
                "environment_json": '{"zone_guess":"door"}',
                "mood_hypothesis_json": '{"label":"兴奋","is_hypothesis":true}',
                "intent_hypothesis_json": '{"label":"求关注","is_hypothesis":true}',
                "health_signals_json": "[]",
                "novelty_signals_json": '[{"label":"门口停留变多"}]',
                "evidence_json": '{"source":"video"}',
                "confidence_json": '{"analysis":0.91}',
            },
            {"clip_sequence": 2},
        ]

        payload = build_clip_debug_payload(8)

        self.assertEqual(payload["id"], 8)
        self.assertEqual(payload["sequence"], 2)
        self.assertEqual(payload["event_type"], "other")
        self.assertEqual(payload["secondary_rules"], ["R03"])
        self.assertEqual(payload["companions"]["contains_person"], True)
        self.assertEqual(payload["actions"][0]["label"], "靠近主人")

    @patch("video_analysis_service.query_db")
    def test_returns_empty_qwen_sections_when_clip_memory_not_ready(self, mock_query_db):
        mock_query_db.side_effect = [
            {
                "id": 5,
                "job_id": "job-2",
                "camera_id": 1,
                "pet_id": 1,
                "rule_id": "R05",
                "primary_rule": "食盆停留候选",
                "secondary_rules_json": "[]",
                "source_video_start_seconds": 3.0,
                "source_video_end_seconds": 9.0,
                "clip_url": "/media/clips/5.mp4",
                "thumbnail_url": "/frames/5.jpg",
                "analysis_status": "running",
                "summary": None,
                "actions_json": None,
                "body_state_json": None,
                "appearance_json": None,
                "interaction_json": None,
                "environment_json": None,
                "mood_hypothesis_json": None,
                "intent_hypothesis_json": None,
                "health_signals_json": None,
                "novelty_signals_json": None,
                "evidence_json": None,
                "confidence_json": None,
            },
            {"clip_sequence": 1},
        ]

        payload = build_clip_debug_payload(5)

        self.assertEqual(payload["analysis_status"], "running")
        self.assertEqual(payload["event_type"], "eating")
        self.assertEqual(payload["summary"], "")
        self.assertEqual(payload["actions"], [])
        self.assertEqual(payload["body_state"], {})

    @patch("video_analysis_service.query_db", return_value=None)
    def test_returns_none_when_clip_is_missing(self, mock_query_db):
        payload = build_clip_debug_payload(404)

        self.assertIsNone(payload)
        mock_query_db.assert_called_once()


if __name__ == "__main__":
    unittest.main()
