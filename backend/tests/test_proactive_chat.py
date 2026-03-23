import struct
import sys
import types
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

fake_vlm_service = sys.modules.setdefault("vlm_service", types.ModuleType("vlm_service"))
fake_vlm_service.review_pet_vocalization = lambda *args, **kwargs: {
    "matched": False,
    "confidence": 0.0,
    "reason": "",
}

import proactive_chat
import video_processor

sys.modules.pop("vlm_service", None)


def _pcm_block(amplitude: int, samples: int) -> bytes:
    return struct.pack("<" + "h" * samples, *([amplitude] * samples))


class VocalizationCandidateTests(unittest.TestCase):
    def test_select_vocalization_candidates_picks_highest_non_overlapping_windows(self):
        sample_rate = 100
        pcm_audio = b"".join(
            [
                _pcm_block(0, 50),
                _pcm_block(500, 50),
                _pcm_block(0, 50),
                _pcm_block(1500, 50),
                _pcm_block(0, 50),
            ]
        )

        candidates = video_processor.select_vocalization_candidates(
            pcm_audio,
            sample_rate=sample_rate,
            window_seconds=0.5,
            hop_seconds=0.5,
            min_gap_seconds=0.75,
            top_n=2,
        )

        self.assertEqual(len(candidates), 2)
        self.assertGreater(candidates[0]["score"], candidates[1]["score"])
        self.assertAlmostEqual(candidates[0]["center_seconds"], 1.75, places=2)
        self.assertAlmostEqual(candidates[1]["center_seconds"], 0.75, places=2)


class FfmpegResolutionTests(unittest.TestCase):
    @patch("video_processor.shutil.which", side_effect=["/usr/local/bin/ffmpeg"])
    def test_get_ffmpeg_executable_uses_system_ffmpeg_when_available(self, mock_which):
        executable = video_processor._get_ffmpeg_executable()

        self.assertEqual(executable, "/usr/local/bin/ffmpeg")
        mock_which.assert_called_once_with("ffmpeg")

    @patch("video_processor.importlib.import_module", side_effect=ImportError)
    @patch("video_processor.shutil.which", return_value=None)
    def test_get_ffmpeg_executable_raises_clear_error_when_unavailable(
        self,
        _mock_which,
        _mock_import_module,
    ):
        with self.assertRaisesRegex(RuntimeError, "未找到可用的 ffmpeg"):
            video_processor._get_ffmpeg_executable()


class ProactiveMessageTests(unittest.TestCase):
    @patch("proactive_chat.os.path.exists", return_value=True)
    @patch("proactive_chat.execute_db", return_value=11)
    @patch("proactive_chat.detect_pet_vocalization_clip")
    @patch("proactive_chat.query_db")
    def test_trigger_pet_vocalization_message_returns_video_message_when_matched(
        self,
        mock_query_db,
        mock_detect,
        mock_execute_db,
        _mock_exists,
    ):
        mock_query_db.side_effect = [
            {"id": 1, "species": "cat"},
            {"id": 2, "demo_video_path": "/media/videos/demo.mp4"},
            {
                "id": 11,
                "role": "assistant",
                "content": "猫言猫语：主人，我想你啦",
                "message_type": "video",
                "media_kind": "video",
                "media_url": "/media/clips/focus.mp4",
                "trigger_source": "proactive_vocalization",
                "created_at": "2026-03-22 12:00:00",
            },
        ]
        mock_detect.return_value = {
            "matched": True,
            "clip_url": "/media/clips/focus.mp4",
            "anchor_seconds": 9.0,
        }

        response = proactive_chat.trigger_pet_vocalization_message(pet_id=1, camera_id=2)

        self.assertTrue(response["matched"])
        self.assertEqual(response["notification_title"], "猫言猫语")
        self.assertEqual(response["message"]["message_type"], "video")
        self.assertEqual(response["message"]["media_url"], "/media/clips/focus.mp4")
        self.assertEqual(response["message"]["trigger_source"], "proactive_vocalization")
        mock_execute_db.assert_called_once()

    @patch("proactive_chat.os.path.exists", return_value=True)
    @patch("proactive_chat.execute_db", return_value=12)
    @patch("proactive_chat.detect_pet_vocalization_clip")
    @patch("proactive_chat.query_db")
    def test_trigger_pet_vocalization_message_returns_text_message_when_unmatched(
        self,
        mock_query_db,
        mock_detect,
        _mock_execute_db,
        _mock_exists,
    ):
        mock_query_db.side_effect = [
            {"id": 1, "species": "dog"},
            {"id": 2, "demo_video_path": "/media/videos/demo.mp4"},
            {
                "id": 12,
                "role": "assistant",
                "content": "汪言汪语：这次我还没有对着镜头汪到能发给你看呢。",
                "message_type": "text",
                "media_kind": "",
                "media_url": "",
                "trigger_source": "proactive_vocalization",
                "created_at": "2026-03-22 12:00:00",
            },
        ]
        mock_detect.return_value = {"matched": False, "reason": "没有找到对着镜头发声的片段"}

        response = proactive_chat.trigger_pet_vocalization_message(pet_id=1, camera_id=2)

        self.assertFalse(response["matched"])
        self.assertEqual(response["notification_title"], "")
        self.assertEqual(response["message"]["message_type"], "text")
        self.assertEqual(response["message"]["media_url"], "")


class ChatSerializationTests(unittest.TestCase):
    def test_serialize_chat_message_keeps_legacy_rows_compatible(self):
        row = {
            "id": 7,
            "role": "assistant",
            "content": "旧消息",
            "created_at": "2026-03-22 11:00:00",
        }

        serialized = proactive_chat.serialize_chat_message(row)

        self.assertEqual(serialized["id"], "7")
        self.assertEqual(serialized["message_type"], "text")
        self.assertEqual(serialized["media_kind"], "")
        self.assertEqual(serialized["media_url"], "")
        self.assertEqual(serialized["trigger_source"], "chat")


if __name__ == "__main__":
    unittest.main()
