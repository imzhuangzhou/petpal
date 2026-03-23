import sys
import types
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

fake_video_processor = types.ModuleType("video_processor")
fake_video_processor.extract_uniform_frames = lambda *args, **kwargs: []
fake_video_processor.clip_video_segment = lambda *args, **kwargs: "/media/clips/test.mp4"
fake_video_processor.get_video_duration = lambda *args, **kwargs: 60.0
sys.modules.setdefault("video_processor", fake_video_processor)

fake_vlm_service = types.ModuleType("vlm_service")
fake_vlm_service.DASHSCOPE_API_KEY = "test-key"
fake_vlm_service.classify_action = lambda *args, **kwargs: {"event_type": "other", "description": "测试"}
fake_vlm_service.describe_frame = lambda *args, **kwargs: "测试描述"
fake_vlm_service.generate_pet_avatar = lambda *args, **kwargs: (b"", "image/png")
fake_vlm_service.generate_text = lambda *args, **kwargs: ""
fake_vlm_service.open_dashscope_stream = lambda *args, **kwargs: (None, [], 0.0)
fake_vlm_service.TEXT_MODEL = "test-model"
sys.modules.setdefault("vlm_service", fake_vlm_service)

fake_dialogue_engine = types.ModuleType("dialogue_engine")
fake_dialogue_engine.invalidate_event_cache = lambda *args, **kwargs: None
sys.modules.setdefault("dialogue_engine", fake_dialogue_engine)

import routes.media as media_routes

sys.modules.pop("video_processor", None)
sys.modules.pop("vlm_service", None)
sys.modules.pop("dialogue_engine", None)


class _StubUpload:
    def __init__(self, filename: str = "demo.mp4", content_type: str = "video/mp4"):
        self.filename = filename
        self.content_type = content_type


class UploadDemoVideoRouteTests(unittest.TestCase):
    @patch("routes.media._persist_video_analysis_debug_snapshot")
    @patch("routes.media._persist_analyzed_events", return_value=88)
    @patch(
        "routes.media._analyze_uploaded_video",
        return_value=(
            [
                {
                    "event_type": "playing",
                    "description": "在地上追球",
                    "timestamp": "2026-03-23T10:00:00",
                    "duration_seconds": 30,
                    "video_start_seconds": 5.0,
                    "video_end_seconds": 35.0,
                    "frame_path": "/frames/a.jpg",
                }
            ],
            "识别出 1 段事件",
            [
                {
                    "sequence": 1,
                    "frame_url": "/frames/a.jpg",
                    "video_seconds": 5.0,
                    "video_time_text": "00:05",
                    "event_type": "playing",
                    "description": "在地上追球",
                }
            ],
        ),
    )
    @patch("routes.media.save_upload_file", return_value=("saved.mp4", "/tmp/saved.mp4"))
    @patch("routes.media.query_db", return_value={"id": 9})
    def test_upload_demo_video_persists_debug_snapshot(
        self,
        mock_query_db,
        mock_save_upload_file,
        mock_analyze_uploaded_video,
        mock_persist_analyzed_events,
        mock_persist_snapshot,
    ):
        response = media_routes.upload_demo_video(
            user_id=3,
            pet_id=9,
            camera_name="客厅",
            camera_id=None,
            video=_StubUpload(),
        )

        self.assertEqual(response["camera_id"], 88)
        self.assertEqual(response["demo_video_url"], "/media/videos/saved.mp4")
        mock_query_db.assert_called_once()
        mock_save_upload_file.assert_called_once()
        mock_analyze_uploaded_video.assert_called_once_with("/tmp/saved.mp4", "demo.mp4")
        mock_persist_analyzed_events.assert_called_once()
        mock_persist_snapshot.assert_called_once_with(
            camera_id=88,
            pet_id=9,
            demo_video_name="demo.mp4",
            demo_video_url="/media/videos/saved.mp4",
            context_summary="识别出 1 段事件",
            frames=[
                {
                    "sequence": 1,
                    "frame_url": "/frames/a.jpg",
                    "video_seconds": 5.0,
                    "video_time_text": "00:05",
                    "event_type": "playing",
                    "description": "在地上追球",
                }
            ],
        )


class VideoAnalysisDebugRouteTests(unittest.TestCase):
    @patch(
        "routes.media.query_db",
        side_effect=[
            {
                "id": 7,
                "name": "客厅",
                "status": "ready",
                "demo_video_path": "/media/videos/demo.mp4",
                "demo_video_name": "demo.mp4",
            },
            {
                "camera_id": 7,
                "pet_id": 11,
                "demo_video_name": "demo.mp4",
                "demo_video_url": "/media/videos/demo.mp4",
                "context_summary": "识别出两段事件",
                "processing_status": "completed",
                "step_states_json": '[{"id":"video_saved","title":"视频已保存","state":"completed"}]',
                "frames_json": '[{"sequence":1,"frame_url":"/frames/1.jpg","video_seconds":3.0,"video_time_text":"00:03","event_type":"resting","description":"趴着"}]',
                "updated_at": "2026-03-23 12:00:00",
            },
            [
                {
                    "id": 1,
                    "pet_id": 11,
                    "event_type": "resting",
                    "description": "趴着",
                    "timestamp": "2026-03-23T12:00:00",
                    "duration_seconds": 20,
                    "video_start_seconds": 3.0,
                    "video_end_seconds": 23.0,
                    "frame_path": "/frames/1.jpg",
                }
            ],
        ],
    )
    def test_returns_snapshot_with_events(self, mock_query_db):
        response = media_routes.get_video_analysis_debug(7)

        self.assertEqual(response["camera_id"], 7)
        self.assertEqual(response["pet_id"], 11)
        self.assertEqual(response["processing_status"], "completed")
        self.assertEqual(len(response["step_states"]), 1)
        self.assertEqual(len(response["frames"]), 1)
        self.assertEqual(len(response["events"]), 1)
        self.assertEqual(response["events"][0]["frame_url"], "/frames/1.jpg")
        self.assertEqual(response["events"][0]["video_start_seconds"], 3.0)
        self.assertEqual(response["events"][0]["video_end_seconds"], 23.0)
        self.assertEqual(mock_query_db.call_count, 3)

    @patch(
        "routes.media.query_db",
        side_effect=[
            {
                "id": 7,
                "name": "客厅",
                "status": "ready",
                "demo_video_path": "/media/videos/demo.mp4",
                "demo_video_name": "demo.mp4",
            },
            None,
            [],
        ],
    )
    def test_returns_empty_debug_payload_when_snapshot_missing(self, mock_query_db):
        response = media_routes.get_video_analysis_debug(7)

        self.assertEqual(response["processing_status"], "not_available")
        self.assertEqual(response["step_states"], [])
        self.assertEqual(response["frames"], [])
        self.assertEqual(response["events"], [])
        self.assertEqual(response["demo_video_url"], "/media/videos/demo.mp4")
        self.assertEqual(mock_query_db.call_count, 3)


class MergeAnalyzedFramesTests(unittest.TestCase):
    def test_merge_analyzed_frames_keeps_video_ranges_for_combined_events(self):
        analyzed_frames = [
            {
                "event_type": "playing",
                "description": "追球",
                "event_time": media_routes.datetime.fromisoformat("2026-03-23T10:00:00"),
                "frame_path": "/frames/1.jpg",
                "video_seconds": 5.0,
                "fallback_duration": 10.0,
            },
            {
                "event_type": "playing",
                "description": "继续追球",
                "event_time": media_routes.datetime.fromisoformat("2026-03-23T10:00:10"),
                "frame_path": "/frames/2.jpg",
                "video_seconds": 15.0,
                "fallback_duration": 10.0,
            },
            {
                "event_type": "resting",
                "description": "停下来休息",
                "event_time": media_routes.datetime.fromisoformat("2026-03-23T10:00:25"),
                "frame_path": "/frames/3.jpg",
                "video_seconds": 25.0,
                "fallback_duration": 10.0,
            },
        ]

        merged = media_routes._merge_analyzed_frames(analyzed_frames)

        self.assertEqual(len(merged), 2)
        self.assertEqual(merged[0]["event_type"], "playing")
        self.assertEqual(merged[0]["video_start_seconds"], 5.0)
        self.assertEqual(merged[0]["video_end_seconds"], 25.0)
        self.assertEqual(merged[0]["duration_seconds"], 20.0)
        self.assertEqual(merged[1]["video_start_seconds"], 25.0)
        self.assertEqual(merged[1]["video_end_seconds"], 35.0)


if __name__ == "__main__":
    unittest.main()
