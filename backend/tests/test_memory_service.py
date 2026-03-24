import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from memory_service import build_daily_memory_payload, build_memory_prompt_context


class BuildDailyMemoryPayloadTests(unittest.TestCase):
    def test_builds_waiting_metrics_and_health_defaults(self):
        clip_rows = [
            {
                "clip_id": 1,
                "summary": "在门口来回踱步",
                "actions_json": '[{"label":"等待主人"}]',
                "body_state_json": '{"state":"moving"}',
                "appearance_json": '{}',
                "interaction_json": '{"contains_person": false}',
                "environment_json": '{"zone_guess":"door"}',
                "mood_hypothesis_json": '{"label":"想你"}',
                "intent_hypothesis_json": '{"label":"等人"}',
                "health_signals_json": "[]",
                "novelty_signals_json": "[]",
                "evidence_json": '{}',
                "confidence_json": '{"actions": 0.9, "environment": 0.8, "mood": 0.7}',
                "primary_rule": "R08",
                "secondary_rules_json": "[]",
                "source_video_start_seconds": 5.0,
                "source_video_end_seconds": 17.0,
                "clip_url": "/media/clips/1.mp4",
                "thumbnail_url": "/frames/1.jpg",
                "clip_created_at": "2026-03-24T10:00:00",
            },
            {
                "clip_id": 2,
                "summary": "在沙发上安静休息",
                "actions_json": '[{"label":"休息"}]',
                "body_state_json": '{"state":"resting"}',
                "appearance_json": '{"outfit":"黄色背心"}',
                "interaction_json": '{"contains_person": false}',
                "environment_json": '{"zone_guess":"sofa"}',
                "mood_hypothesis_json": '{"label":"放松"}',
                "intent_hypothesis_json": '{"label":"发呆"}',
                "health_signals_json": "[]",
                "novelty_signals_json": "[]",
                "evidence_json": '{}',
                "confidence_json": '{"actions": 0.8, "appearance": 0.9, "mood": 0.8}',
                "primary_rule": "R10",
                "secondary_rules_json": "[]",
                "source_video_start_seconds": 22.0,
                "source_video_end_seconds": 40.0,
                "clip_url": "/media/clips/2.mp4",
                "thumbnail_url": "/frames/2.jpg",
                "clip_created_at": "2026-03-24T10:03:00",
            },
        ]

        payload = build_daily_memory_payload(
            pet_id=3,
            memory_date="2026-03-24",
            clip_rows=clip_rows,
            recent_daily_memories=[],
        )

        self.assertEqual(payload["activity_counts"]["clip_count"], 2)
        self.assertEqual(payload["activity_counts"]["waiting_count"], 1)
        self.assertAlmostEqual(payload["activity_counts"]["waiting_seconds"], 12.0)
        self.assertEqual(payload["appearance_of_day"]["top_outfit"], "黄色背心")
        self.assertEqual(payload["health_flags"][0]["level"], "normal")
        self.assertIn("summary", payload["change_vs_recent_baseline"])


class BuildMemoryPromptContextTests(unittest.TestCase):
    @patch("memory_service.get_profile_memories")
    @patch("memory_service.get_latest_daily_memory")
    @patch("memory_service.get_daily_memory")
    @patch("memory_service.get_recent_clip_memories")
    def test_includes_immediate_clip_details_and_baseline_summary(
        self,
        mock_recent_clips,
        mock_get_daily_memory,
        mock_get_latest_daily_memory,
        mock_get_profile_memories,
    ):
        mock_recent_clips.return_value = [
            {
                "summary": "在门口来回踱步",
                "source_video_start_seconds": 5.0,
                "source_video_end_seconds": 17.0,
                "actions": [{"label": "等待主人"}],
                "environment": {"zone_guess": "door"},
                "mood_hypothesis": {"label": "想你"},
                "intent_hypothesis": {"label": "等人"},
                "interaction": {"contains_person": False},
                "health_signals": [],
            }
        ]
        mock_get_daily_memory.return_value = {
            "daily_summary": "今天主要出现了等待主人。",
            "activity_counts": {"actions": {"等待主人": 1}},
            "health_flags": [],
            "change_vs_recent_baseline": {"summary": "今天的等待主人比最近几天更频繁。"},
        }
        mock_get_latest_daily_memory.return_value = None
        mock_get_profile_memories.return_value = [
            {"memory_type": "preferred_zone", "value": {"label": "窗边"}}
        ]

        context = build_memory_prompt_context(3)

        self.assertEqual(
            context["immediate_clip_lines"][0],
            "- 5.0s-17.0s：在门口来回踱步；动作：等待主人；位置：门口；情绪猜测：想你；意图猜测：等人",
        )
        self.assertEqual(context["baseline_summary"], "今天的等待主人比最近几天更频繁。")
        self.assertEqual(context["profile_lines"], ["- preferred_zone：窗边"])


if __name__ == "__main__":
    unittest.main()
