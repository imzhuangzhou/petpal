import sys
import types
import unittest
from pathlib import Path
from unittest.mock import patch

from fastapi import BackgroundTasks, HTTPException

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

fake_video_processor = types.ModuleType("video_processor")
fake_video_processor.extract_uniform_frames = lambda *args, **kwargs: []
sys.modules.setdefault("video_processor", fake_video_processor)

fake_vlm_service = types.ModuleType("vlm_service")
fake_vlm_service.DASHSCOPE_API_KEY = "test-key"
fake_vlm_service.classify_action = lambda *args, **kwargs: {"event_type": "other", "description": "测试"}
fake_vlm_service.describe_frame = lambda *args, **kwargs: "测试描述"
fake_vlm_service.generate_pet_avatar = lambda *args, **kwargs: (b"", "image/png")
sys.modules.setdefault("vlm_service", fake_vlm_service)

fake_dialogue_engine = types.ModuleType("dialogue_engine")
fake_dialogue_engine.invalidate_event_cache = lambda *args, **kwargs: None
sys.modules.setdefault("dialogue_engine", fake_dialogue_engine)

fake_video_analysis_service = types.ModuleType("video_analysis_service")
fake_video_analysis_service.build_debug_payload = lambda *args, **kwargs: {}
fake_video_analysis_service.build_memory_debug_payload = lambda *args, **kwargs: {}
fake_video_analysis_service.create_video_analysis_job = lambda *args, **kwargs: "job-test"
fake_video_analysis_service.process_video_analysis_job = lambda *args, **kwargs: None
sys.modules.setdefault("video_analysis_service", fake_video_analysis_service)

import routes.media as media_routes

sys.modules.pop("video_processor", None)
sys.modules.pop("vlm_service", None)
sys.modules.pop("dialogue_engine", None)
sys.modules.pop("video_analysis_service", None)


class _StubUpload:
    def __init__(self, filename: str = "demo.mp4", content_type: str = "video/mp4"):
        self.filename = filename
        self.content_type = content_type


class UploadDemoVideoRouteTests(unittest.TestCase):
    @patch("routes.media.create_video_analysis_job", return_value="job-123")
    @patch("routes.media._upsert_demo_camera", return_value=88)
    @patch("routes.media.save_upload_file", return_value=("saved.mp4", "/tmp/saved.mp4"))
    @patch("routes.media.query_db", return_value={"id": 9})
    def test_upload_demo_video_queues_async_job(
        self,
        mock_query_db,
        mock_save_upload_file,
        mock_upsert_camera,
        mock_create_job,
    ):
        background_tasks = BackgroundTasks()

        response = media_routes.upload_demo_video(
            background_tasks=background_tasks,
            user_id=3,
            pet_id=9,
            camera_name="客厅",
            camera_id=None,
            video=_StubUpload(),
        )

        self.assertEqual(response["camera_id"], 88)
        self.assertEqual(response["job_id"], "job-123")
        self.assertEqual(response["processing_status"], "queued")
        self.assertEqual(response["events_count"], 0)
        self.assertEqual(len(background_tasks.tasks), 1)
        mock_query_db.assert_called_once()
        mock_save_upload_file.assert_called_once()
        mock_upsert_camera.assert_called_once_with(
            user_id=3,
            camera_name="客厅",
            camera_id=None,
            video_relative_path="/media/videos/saved.mp4",
            original_filename="demo.mp4",
        )
        mock_create_job.assert_called_once_with(
            camera_id=88,
            pet_id=9,
            source_video_path="/tmp/saved.mp4",
            source_video_name="demo.mp4",
            demo_video_url="/media/videos/saved.mp4",
        )

    def test_upload_demo_video_rejects_non_video(self):
        with self.assertRaises(HTTPException) as context:
            media_routes.upload_demo_video(
                background_tasks=BackgroundTasks(),
                user_id=1,
                pet_id=1,
                camera_name="客厅",
                camera_id=None,
                video=_StubUpload(filename="demo.txt", content_type="text/plain"),
            )

        self.assertEqual(context.exception.status_code, 400)


class VideoAnalysisDebugRouteTests(unittest.TestCase):
    @patch(
        "routes.media.build_debug_payload",
        return_value={
            "camera_id": 7,
            "pet_id": 11,
            "job_id": "job-7",
            "demo_video_name": "demo.mp4",
            "demo_video_url": "/media/videos/demo.mp4",
            "context_summary": "正在处理中",
            "processing_status": "running",
            "step_states": [{"id": "video_saved", "title": "视频已保存", "state": "completed"}],
            "frames": [],
            "candidate_clips": [],
            "events": [],
            "last_updated_at": "2026-03-24 12:00:00",
        },
    )
    def test_returns_payload_from_debug_builder(self, mock_build_debug_payload):
        response = media_routes.get_video_analysis_debug(7)

        self.assertEqual(response["camera_id"], 7)
        self.assertEqual(response["processing_status"], "running")
        self.assertEqual(response["job_id"], "job-7")
        mock_build_debug_payload.assert_called_once_with(7)

    @patch("routes.media.build_debug_payload", return_value=None)
    def test_raises_404_when_camera_not_found(self, mock_build_debug_payload):
        with self.assertRaises(HTTPException) as context:
            media_routes.get_video_analysis_debug(99)

        self.assertEqual(context.exception.status_code, 404)
        mock_build_debug_payload.assert_called_once_with(99)


class MemoryDebugRouteTests(unittest.TestCase):
    @patch(
        "routes.media.build_memory_debug_payload",
        return_value={
            "pet_id": 5,
            "daily_memory": {"daily_summary": "今天大部分时间都在门口等人。"},
            "profile_memories": {"active": [], "stale": []},
        },
    )
    def test_returns_memory_debug_payload(self, mock_build_memory_debug_payload):
        response = media_routes.get_memory_debug(5)

        self.assertEqual(response["pet_id"], 5)
        self.assertIn("daily_memory", response)
        mock_build_memory_debug_payload.assert_called_once_with(5)


if __name__ == "__main__":
    unittest.main()
