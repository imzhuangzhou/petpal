import sys
import types
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

fake_vlm_service = types.ModuleType("vlm_service")
fake_vlm_service.generate_text = lambda *args, **kwargs: ""
fake_vlm_service.get_vlm_client = lambda: None
fake_vlm_service.open_dashscope_stream = lambda *args, **kwargs: (None, [], 0.0)
fake_vlm_service.TEXT_MODEL = "test-model"
sys.modules.setdefault("vlm_service", fake_vlm_service)

import dialogue_engine


class HealthAlertsTests(unittest.TestCase):
    @patch("dialogue_engine.get_today_events")
    def test_returns_normal_alert_when_events_are_within_expected_range(self, mock_get_today_events):
        mock_get_today_events.return_value = [
            {"event_type": "eating"},
            {"event_type": "drinking"},
            {"event_type": "playing"},
            {"event_type": "sleeping"},
        ]

        alerts = dialogue_engine.get_health_alerts(1)

        self.assertEqual(len(alerts), 1)
        self.assertEqual(alerts[0]["level"], "normal")
        self.assertIn("一切正常", alerts[0]["title"])

    @patch("dialogue_engine.get_today_events")
    def test_flags_excessive_drinking(self, mock_get_today_events):
        mock_get_today_events.return_value = [
            {"event_type": "drinking"},
            {"event_type": "drinking"},
            {"event_type": "drinking"},
            {"event_type": "drinking"},
            {"event_type": "drinking"},
        ]

        alerts = dialogue_engine.get_health_alerts(1)

        self.assertEqual(len(alerts), 1)
        self.assertEqual(alerts[0]["level"], "warning")
        self.assertEqual(alerts[0]["title"], "饮水频率偏高")
        self.assertIn("5次水", alerts[0]["message"])

    @patch("dialogue_engine.get_today_events")
    def test_flags_missing_food_when_many_events_exist(self, mock_get_today_events):
        mock_get_today_events.return_value = [
            {"event_type": "playing"},
            {"event_type": "sleeping"},
            {"event_type": "drinking"},
            {"event_type": "resting"},
            {"event_type": "waiting"},
            {"event_type": "drinking"},
        ]

        alerts = dialogue_engine.get_health_alerts(1)

        self.assertEqual(len(alerts), 1)
        self.assertEqual(alerts[0]["level"], "critical")
        self.assertEqual(alerts[0]["title"], "今天没有进食记录")


class AnxietyScoreTests(unittest.TestCase):
    @patch("dialogue_engine.get_today_events")
    def test_returns_high_anxiety_with_multiple_long_waiting_events(self, mock_get_today_events):
        mock_get_today_events.return_value = [
            {"event_type": "waiting", "duration_seconds": 300},
            {"event_type": "waiting", "duration_seconds": 300},
            {"event_type": "resting", "duration_seconds": 120},
        ]

        result = dialogue_engine.get_anxiety_score(1)

        self.assertEqual(result["score"], 80)
        self.assertEqual(result["level"], "high")
        self.assertEqual(result["waiting_count"], 2)
        self.assertEqual(result["total_waiting_minutes"], 10.0)


class SystemPromptTests(unittest.TestCase):
    @patch("dialogue_engine.get_cached_event_context")
    def test_build_system_prompt_supports_chill_style(self, mock_get_cached_event_context):
        mock_get_cached_event_context.return_value = (
            "- 2026-03-22T09:00:00: 猫咪在窗边发呆（resting，持续600秒）",
            {
                "eating": 1,
                "drinking": 2,
                "sleeping": 3,
                "playing": 1,
                "waiting": 0,
                "litter_box": 0,
            },
            [],
        )
        pet = {
            "id": 1,
            "name": "奶糖",
            "species": "cat",
            "breed": "",
            "language_style": "chill",
            "style_prompt": "",
            "owner_alias": "",
            "voice_label": "月光喵",
        }

        prompt = dialogue_engine.build_system_prompt(pet, [])

        self.assertIn("慢慢来嘛", prompt)
        self.assertIn("饮水次数：2 次", prompt)
        self.assertIn("猫咪在窗边发呆", prompt)
        self.assertIn("铲屎官", prompt)
        self.assertNotIn("月光喵", prompt)
        self.assertNotIn("声音设定", prompt)

    @patch("dialogue_engine.get_cached_event_context")
    def test_build_system_prompt_prefers_owner_alias_when_provided(self, mock_get_cached_event_context):
        mock_get_cached_event_context.return_value = (
            "今天还没有记录到任何事件。",
            {
                "eating": 0,
                "drinking": 0,
                "sleeping": 0,
                "playing": 0,
                "waiting": 0,
                "litter_box": 0,
            },
            [],
        )
        pet = {
            "id": 2,
            "name": "可可",
            "species": "cat",
            "breed": "",
            "language_style": "tsundere",
            "style_prompt": "",
            "owner_alias": "boss",
        }

        prompt = dialogue_engine.build_system_prompt(pet, [])

        self.assertIn("boss", prompt)
        self.assertIn("优先使用“boss”", prompt)
        self.assertNotIn("铲屎官", prompt)


if __name__ == "__main__":
    unittest.main()
