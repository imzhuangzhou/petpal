import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import routes.events as event_routes


class EventClipRouteTests(unittest.TestCase):
    @patch("routes.events.os.path.exists", return_value=True)
    @patch("routes.events.execute_db")
    @patch("routes.events.query_db")
    def test_backfills_existing_event_clip_from_candidate_clips(
        self,
        mock_query_db,
        mock_execute_db,
        _mock_exists,
    ):
        mock_query_db.side_effect = [
            {
                "id": 9,
                "camera_id": 1,
                "pet_id": 2,
                "clip_url": "",
                "video_start_seconds": 5.0,
                "video_end_seconds": 11.0,
                "demo_video_path": "/media/videos/demo.mp4",
            },
            {
                "clip_url": "/media/clips/prebuilt-backfill.mp4",
            },
        ]

        response = event_routes.get_event_clip(9)

        self.assertEqual(response["video_clip_url"], "/media/clips/prebuilt-backfill.mp4")
        mock_execute_db.assert_called_once_with(
            "UPDATE events SET clip_url = ? WHERE id = ?",
            ("/media/clips/prebuilt-backfill.mp4", 9),
        )

    @patch("routes.events.os.path.exists", return_value=True)
    @patch("routes.events.query_db")
    def test_returns_existing_short_clip_without_recropping(self, mock_query_db, _mock_exists):
        mock_query_db.return_value = {
            "id": 9,
            "camera_id": 1,
            "pet_id": 2,
            "clip_url": "/media/clips/prebuilt.mp4",
            "video_start_seconds": 5.0,
            "video_end_seconds": 11.0,
            "demo_video_path": "/media/videos/demo.mp4",
        }

        with patch("routes.events.clip_video_segment") as mock_clip_video_segment:
            response = event_routes.get_event_clip(9)

        self.assertEqual(response["event_id"], 9)
        self.assertEqual(response["video_clip_url"], "/media/clips/prebuilt.mp4")
        mock_clip_video_segment.assert_not_called()

    @patch("routes.events.clip_video_segment", return_value="/media/clips/event-focus.mp4")
    @patch("routes.events.get_video_duration", return_value=30.0)
    @patch("routes.events.os.path.exists", return_value=True)
    @patch("routes.events.query_db")
    def test_returns_event_clip_url_for_valid_event(
        self,
        mock_query_db,
        _mock_exists,
        mock_get_video_duration,
        mock_clip_video_segment,
    ):
        mock_query_db.return_value = {
            "id": 9,
            "camera_id": 1,
            "pet_id": 2,
            "clip_url": "",
            "video_start_seconds": 5.0,
            "video_end_seconds": 11.0,
            "demo_video_path": "/media/videos/demo.mp4",
        }

        response = event_routes.get_event_clip(9)

        self.assertEqual(response["event_id"], 9)
        self.assertEqual(response["video_clip_url"], "/media/clips/event-focus.mp4")
        mock_get_video_duration.assert_called_once()
        mock_clip_video_segment.assert_called_once()
        clip_args = mock_clip_video_segment.call_args.args
        self.assertTrue(clip_args[0].endswith("uploads/videos/demo.mp4"))
        self.assertEqual(clip_args[1], 3.5)
        self.assertEqual(clip_args[2], 12.5)

    @patch("routes.events.query_db")
    def test_rejects_events_without_video_ranges(self, mock_query_db):
        mock_query_db.return_value = {
            "id": 9,
            "camera_id": 1,
            "pet_id": 2,
            "clip_url": "",
            "video_start_seconds": None,
            "video_end_seconds": None,
            "demo_video_path": "/media/videos/demo.mp4",
        }

        with self.assertRaises(event_routes.HTTPException) as context:
            event_routes.get_event_clip(9)

        self.assertEqual(context.exception.status_code, 409)
        self.assertIn("缺少视频时间范围", context.exception.detail)

    @patch("routes.events.os.path.exists", return_value=False)
    @patch("routes.events.query_db")
    def test_returns_not_found_when_source_video_is_missing(self, mock_query_db, _mock_exists):
        mock_query_db.return_value = {
            "id": 9,
            "camera_id": 1,
            "pet_id": 2,
            "clip_url": "",
            "video_start_seconds": 5.0,
            "video_end_seconds": 11.0,
            "demo_video_path": "/media/videos/demo.mp4",
        }

        with self.assertRaises(event_routes.HTTPException) as context:
            event_routes.get_event_clip(9)

        self.assertEqual(context.exception.status_code, 404)
        self.assertIn("原始视频不存在", context.exception.detail)


if __name__ == "__main__":
    unittest.main()
