import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from video_processor import detect_candidate_segments


class DetectCandidateSegmentsTests(unittest.TestCase):
    @patch("video_processor.get_video_duration", return_value=60.0)
    @patch(
        "video_processor.scan_video_signals",
        return_value=[
            {"second": 0.0, "motion_score": 0.0, "speed_score": 0.0, "novelty_score": 0.0, "edge_bias": 0.0},
            {"second": 1.0, "motion_score": 0.008, "speed_score": 0.03, "novelty_score": 0.01, "edge_bias": 0.5},
            {"second": 2.0, "motion_score": 0.009, "speed_score": 0.04, "novelty_score": 0.011, "edge_bias": 0.5},
            {"second": 3.0, "motion_score": 0.009, "speed_score": 0.05, "novelty_score": 0.008, "edge_bias": 0.4},
            {"second": 4.0, "motion_score": 0.0, "speed_score": 0.0, "novelty_score": 0.0, "edge_bias": 0.0},
            {"second": 5.0, "motion_score": 0.0, "speed_score": 0.0, "novelty_score": 0.0, "edge_bias": 0.0},
            {"second": 6.0, "motion_score": 0.0, "speed_score": 0.0, "novelty_score": 0.0, "edge_bias": 0.0},
        ],
    )
    def test_opens_and_closes_segment_from_signal_runs(self, mock_scan, mock_duration):
        segments = detect_candidate_segments("demo.mp4")

        self.assertEqual(len(segments), 1)
        self.assertLessEqual(segments[0]["start_seconds"], 0.0)
        self.assertGreaterEqual(segments[0]["end_seconds"], 4.0)
        mock_scan.assert_called_once_with("demo.mp4", sample_fps=2.0)
        mock_duration.assert_called()

    @patch("video_processor.get_video_duration", return_value=60.0)
    @patch(
        "video_processor.scan_video_signals",
        return_value=[
            {"second": 0.0, "motion_score": 0.0, "speed_score": 0.0, "novelty_score": 0.0, "edge_bias": 0.0},
            {"second": 10.0, "motion_score": 0.0, "speed_score": 0.0, "novelty_score": 0.0, "edge_bias": 0.0},
        ],
    )
    def test_creates_fallback_segment_when_no_candidates_detected(self, mock_scan, mock_duration):
        segments = detect_candidate_segments("demo.mp4")

        self.assertEqual(len(segments), 1)
        self.assertTrue(segments[0]["signal_summary"].get("fallback"))


if __name__ == "__main__":
    unittest.main()
