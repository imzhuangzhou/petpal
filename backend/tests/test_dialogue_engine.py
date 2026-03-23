import sys
import re
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

sys.modules.pop("vlm_service", None)


class _FakeDelta:
    def __init__(self, content):
        self.content = content


class _FakeChoice:
    def __init__(self, content):
        self.delta = _FakeDelta(content)


class _FakeChunk:
    def __init__(self, content):
        self.choices = [_FakeChoice(content)]


class _FakeClient:
    def __init__(self):
        self.closed = False

    def close(self):
        self.closed = True


class HealthAlertsTests(unittest.TestCase):
    COPY_SYMBOL_PATTERN = re.compile(r"[\U0001F000-\U0001FAFF\u2600-\u27BF]")

    def assert_alert_copy_is_clean(self, alert):
        self.assertNotRegex(alert["title"], self.COPY_SYMBOL_PATTERN)
        self.assertNotRegex(alert["message"], self.COPY_SYMBOL_PATTERN)

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
        self.assertEqual(alerts[0]["title"], "一切正常")
        self.assert_alert_copy_is_clean(alerts[0])

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
        self.assert_alert_copy_is_clean(alerts[0])

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
        self.assert_alert_copy_is_clean(alerts[0])


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
        self.assertEqual(result["longest_waiting_minutes"], 5.0)
        self.assertEqual(result["waiting_share_percent"], 83)

    @patch("dialogue_engine.get_today_events")
    def test_returns_zeroed_explanatory_metrics_without_waiting_events(self, mock_get_today_events):
        mock_get_today_events.return_value = [
            {"event_type": "resting", "duration_seconds": 600},
            {"event_type": "playing", "duration_seconds": 300},
        ]

        result = dialogue_engine.get_anxiety_score(1)

        self.assertEqual(result["score"], 0)
        self.assertEqual(result["level"], "relaxed")
        self.assertEqual(result["waiting_count"], 0)
        self.assertEqual(result["total_waiting_minutes"], 0.0)
        self.assertEqual(result["longest_waiting_minutes"], 0.0)
        self.assertEqual(result["waiting_share_percent"], 0)

    @patch("dialogue_engine.get_today_events")
    def test_waiting_share_percent_falls_back_to_zero_when_total_duration_is_zero(self, mock_get_today_events):
        mock_get_today_events.return_value = [
            {"event_type": "waiting", "duration_seconds": 0},
            {"event_type": "resting", "duration_seconds": 0},
        ]

        result = dialogue_engine.get_anxiety_score(1)

        self.assertEqual(result["score"], 15)
        self.assertEqual(result["waiting_count"], 1)
        self.assertEqual(result["total_waiting_minutes"], 0.0)
        self.assertEqual(result["longest_waiting_minutes"], 0.0)
        self.assertEqual(result["waiting_share_percent"], 0)


class DailyReportCardTests(unittest.TestCase):
    def test_build_daily_report_card_includes_stats_tags_and_report(self):
        pet = {
            "name": "奶糖",
            "species": "cat",
            "language_style": "chill",
            "owner_alias": "Boss",
        }
        stats = {
            "eating": 1,
            "drinking": 2,
            "sleeping": 1,
            "playing": 0,
            "waiting": 0,
        }
        events = [
            {"event_type": "resting", "description": "在窗边发呆"},
            {"event_type": "eating", "description": "吃了一顿饭"},
            {"event_type": "drinking", "description": "去喝水"},
        ]

        card = dialogue_engine.build_daily_report_card(pet, stats, events, "今天我过得慢悠悠的。")

        self.assertEqual(card["mood"], "松弛")
        self.assertEqual(card["summary"], "今天我过得慢悠悠的。")
        self.assertEqual(card["stats"]["eating"], 1)
        self.assertEqual(card["stats"]["drinking"], 2)
        self.assertEqual(card["stats"]["playing"], 0)
        self.assertEqual(card["stats"]["waiting"], 0)
        self.assertEqual(card["activity_tags"], ["发呆", "吃饭", "喝水"])
        self.assertIn("Boss", card["headline"])

    def test_build_daily_report_card_returns_empty_state_when_no_events(self):
        pet = {
            "name": "可可",
            "species": "cat",
            "language_style": "tsundere",
            "owner_alias": "",
        }
        stats = {
            "eating": 0,
            "drinking": 0,
            "sleeping": 0,
            "playing": 0,
            "waiting": 0,
        }

        card = dialogue_engine.build_daily_report_card(pet, stats, [], "今天还没有记录到什么事。")

        self.assertEqual(card["mood"], "待机中")
        self.assertEqual(card["activity_tags"], [])
        self.assertEqual(card["summary"], "今天还没有记录到什么事。")

    @patch("dialogue_engine.generate_text")
    @patch("dialogue_engine.build_system_prompt")
    @patch("dialogue_engine.get_cached_event_context")
    @patch("dialogue_engine.query_db")
    def test_generate_daily_report_payload_keeps_report_and_adds_card(
        self,
        mock_query_db,
        mock_get_cached_event_context,
        mock_build_system_prompt,
        mock_generate_text,
    ):
        mock_query_db.return_value = {
            "id": 1,
            "name": "奶糖",
            "species": "cat",
            "breed": "",
            "language_style": "chill",
            "style_prompt": "",
            "owner_alias": "Boss",
        }
        mock_get_cached_event_context.return_value = (
            "summary",
            {
                "eating": 1,
                "drinking": 1,
                "sleeping": 1,
                "playing": 0,
                "waiting": 0,
                "litter_box": 0,
            },
            [{"event_type": "resting", "description": "晒太阳"}],
        )
        mock_build_system_prompt.return_value = "system"
        mock_generate_text.return_value = "Boss，今天我晒了太阳。"

        payload = dialogue_engine.generate_daily_report_payload(1)

        self.assertEqual(payload["report"], "Boss，今天我晒了太阳。")
        self.assertIn("card", payload)
        self.assertEqual(payload["card"]["summary"], "Boss，今天我晒了太阳。")
        self.assertIn("Boss", payload["card"]["headline"])


class MatchRelatedEventsTests(unittest.TestCase):
    @patch("dialogue_engine.get_cached_event_context")
    def test_match_related_events_returns_event_metadata_without_frame_url(self, mock_get_cached_event_context):
        mock_get_cached_event_context.return_value = (
            "",
            {},
            [
                {
                    "id": 3,
                    "event_type": "playing",
                    "description": "在客厅追球",
                    "timestamp": "2026-03-23T10:00:00",
                    "frame_path": "/frames/ball.jpg",
                }
            ],
        )

        related = dialogue_engine.match_related_events("刚刚是不是在客厅追球呀", pet_id=1)

        self.assertEqual(len(related), 1)
        self.assertEqual(related[0]["event_id"], 3)
        self.assertEqual(related[0]["video_clip_url"], "")


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
        self.assertIn("1到3句", prompt)
        self.assertIn("默认不要用emoji", prompt)
        self.assertNotIn("月光喵", prompt)
        self.assertNotIn("声音设定", prompt)
        self.assertNotIn("颜文字或表情", prompt)

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


class TextCleaningTests(unittest.TestCase):
    def test_clean_chat_reply_removes_emoji_stage_directions_and_invisible_chars(self):
        cleaned = dialogue_engine.clean_chat_reply(
            "Boss好呀～（慢悠悠伸个懒腰）\u200b\n我刚刚在窗边发呆呢🌞\ufe0f\n你摸摸我头😺"
        )

        self.assertEqual(cleaned, "Boss好呀～\n我刚刚在窗边发呆呢\n你摸摸我头")

    def test_clean_stream_token_removes_display_risky_chars(self):
        self.assertEqual(dialogue_engine.clean_stream_token("哈🌞\ufe0f\u200b"), "哈")


class ChatReplyPersistenceTests(unittest.TestCase):
    @patch("dialogue_engine.invalidate_event_cache")
    @patch("database.execute_db")
    @patch("dialogue_engine.generate_text")
    @patch("dialogue_engine._prepare_chat_context")
    def test_chat_with_pet_cleans_reply_before_return_and_persist(
        self,
        mock_prepare_chat_context,
        mock_generate_text,
        mock_execute_db,
        mock_invalidate_event_cache,
    ):
        mock_prepare_chat_context.return_value = (
            {"id": 1, "name": "奶糖"},
            "system",
            "user prompt",
        )
        mock_generate_text.return_value = "Boss好呀🌞（慢悠悠伸个懒腰）你摸摸我😺"

        response = dialogue_engine.chat_with_pet(1, "你好")

        self.assertEqual(response, "Boss好呀你摸摸我")
        assistant_insert = mock_execute_db.call_args_list[1]
        self.assertEqual(
            assistant_insert.args[1],
            (1, "assistant", "Boss好呀你摸摸我"),
        )
        mock_invalidate_event_cache.assert_called_once_with(1)

    @patch("dialogue_engine.invalidate_event_cache")
    @patch("database.execute_db")
    @patch("dialogue_engine.open_dashscope_stream")
    @patch("dialogue_engine._prepare_chat_context")
    def test_chat_with_pet_stream_cleans_tokens_for_display_and_reply_for_storage(
        self,
        mock_prepare_chat_context,
        mock_open_dashscope_stream,
        mock_execute_db,
        mock_invalidate_event_cache,
    ):
        mock_prepare_chat_context.return_value = (
            {"id": 1, "name": "奶糖"},
            "system",
            "user prompt",
        )
        fake_client = _FakeClient()
        stream = [
            _FakeChunk("Boss好呀🌞"),
            _FakeChunk("（慢悠悠伸个懒腰）"),
            _FakeChunk("我刚刚在发呆呢😺"),
        ]
        mock_open_dashscope_stream.return_value = (fake_client, stream, 0.0)

        chunks = list(dialogue_engine.chat_with_pet_stream(1, "你好"))

        self.assertEqual(chunks, ["Boss好呀", "（慢悠悠伸个懒腰）", "我刚刚在发呆呢"])
        assistant_insert = mock_execute_db.call_args_list[1]
        self.assertEqual(
            assistant_insert.args[1],
            (1, "assistant", "Boss好呀我刚刚在发呆呢"),
        )
        self.assertTrue(fake_client.closed)
        mock_invalidate_event_cache.assert_called_once_with(1)


if __name__ == "__main__":
    unittest.main()
