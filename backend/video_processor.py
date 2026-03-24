import audioop
import importlib
import math
import os
import shutil
import subprocess
import uuid
from datetime import datetime
from typing import Optional

import cv2

from vlm_service import review_pet_vocalization

BACKEND_DIR = os.path.dirname(__file__)
UPLOADS_DIR = os.path.join(BACKEND_DIR, "uploads")
FRAMES_DIR = os.path.join(BACKEND_DIR, "frames")
CLIPS_DIR = os.path.join(UPLOADS_DIR, "clips")

os.makedirs(FRAMES_DIR, exist_ok=True)
os.makedirs(CLIPS_DIR, exist_ok=True)

PCM_SAMPLE_RATE = 16_000
PCM_SAMPLE_WIDTH = 2
VOCALIZATION_WINDOW_SECONDS = 0.5
VOCALIZATION_HOP_SECONDS = 0.25
VOCALIZATION_MIN_GAP_SECONDS = 1.5
VOCALIZATION_REVIEW_TOP_N = 3
VOCALIZATION_PRE_ROLL_SECONDS = 2.0
VOCALIZATION_POST_ROLL_SECONDS = 3.0
VOCALIZATION_MATCH_THRESHOLD = 0.6
COARSE_SCAN_FPS = 2.0
SEGMENT_PRE_ROLL_SECONDS = 2.0
SEGMENT_POST_ROLL_SECONDS = 3.0
SEGMENT_MERGE_GAP_SECONDS = 5.0
SEGMENT_MIN_SECONDS = 3.0
SEGMENT_TARGET_SECONDS = 25.0
SEGMENT_MAX_SECONDS = 45.0


def process_video(video_path: str, frame_interval: int = 5, motion_threshold: float = 5000.0):
    """
    Process a video file: detect motion and extract key frames.

    Args:
        video_path: Path to the video file
        frame_interval: Minimum seconds between captured frames
        motion_threshold: Threshold for motion detection (lower = more sensitive)

    Returns:
        List of dicts: [{"frame_path": str, "timestamp": float, "frame_index": int}]
    """
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise ValueError(f"Cannot open video: {video_path}")

    fps = cap.get(cv2.CAP_PROP_FPS) or 30
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    duration = total_frames / fps

    print(f"📹 Video: {video_path}")
    print(f"   FPS: {fps:.1f}, Total frames: {total_frames}, Duration: {duration:.1f}s")

    prev_gray = None
    captured_frames = []
    last_capture_time = -frame_interval
    frame_idx = 0

    while True:
        ret, frame = cap.read()
        if not ret:
            break

        current_time = frame_idx / fps
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        gray = cv2.GaussianBlur(gray, (21, 21), 0)

        if prev_gray is not None and (current_time - last_capture_time) >= frame_interval:
            frame_delta = cv2.absdiff(prev_gray, gray)
            thresh = cv2.threshold(frame_delta, 25, 255, cv2.THRESH_BINARY)[1]
            motion_score = thresh.sum() / 255

            if motion_score > motion_threshold:
                timestamp_str = datetime.now().strftime("%Y%m%d_%H%M%S")
                frame_filename = f"frame_{timestamp_str}_{frame_idx}.jpg"
                frame_path = os.path.join(FRAMES_DIR, frame_filename)
                cv2.imwrite(frame_path, frame)

                captured_frames.append({
                    "frame_path": frame_path,
                    "timestamp": current_time,
                    "frame_index": frame_idx,
                    "video_time_str": f"{int(current_time // 60):02d}:{int(current_time % 60):02d}",
                })

                last_capture_time = current_time
                print(f"   📸 Frame captured at {current_time:.1f}s (motion: {motion_score:.0f})")

        prev_gray = gray
        frame_idx += 1

    cap.release()
    print(f"   ✅ Total frames captured: {len(captured_frames)}")
    return captured_frames


def extract_uniform_frames(video_path: str, num_frames: int = 20):
    """
    Extract frames uniformly distributed across the video.
    Useful for demo mode where we want good coverage.
    """
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise ValueError(f"Cannot open video: {video_path}")

    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    fps = cap.get(cv2.CAP_PROP_FPS) or 30

    if total_frames <= num_frames:
        interval = 1
    else:
        interval = total_frames // num_frames

    captured_frames = []
    for i in range(0, min(total_frames, num_frames * interval), interval):
        cap.set(cv2.CAP_PROP_POS_FRAMES, i)
        ret, frame = cap.read()
        if not ret:
            break

        current_time = i / fps
        timestamp_str = datetime.now().strftime("%Y%m%d_%H%M%S")
        frame_filename = f"frame_{timestamp_str}_{i}.jpg"
        frame_path = os.path.join(FRAMES_DIR, frame_filename)
        cv2.imwrite(frame_path, frame)

        captured_frames.append({
            "frame_path": frame_path,
            "timestamp": current_time,
            "frame_index": i,
            "video_time_str": f"{int(current_time // 60):02d}:{int(current_time % 60):02d}",
        })

    cap.release()
    print(f"   ✅ Uniformly extracted {len(captured_frames)} frames")
    return captured_frames


def detect_pet_vocalization_clip(video_path: str, species: str) -> dict:
    try:
        pcm_audio = _extract_audio_pcm(video_path)
    except RuntimeError:
        return {"matched": False, "reason": "视频中没有可分析的声音"}

    candidates = select_vocalization_candidates(pcm_audio)
    if not candidates:
        return {"matched": False, "reason": "没有发现明显叫声"}

    try:
        video_duration = get_video_duration(video_path)
    except RuntimeError:
        return {"matched": False, "reason": "无法读取视频时长"}
    best_match = None

    for candidate in candidates[:VOCALIZATION_REVIEW_TOP_N]:
        frame_paths = _extract_candidate_frames(
            video_path,
            candidate["center_seconds"],
            video_duration,
        )
        review = review_pet_vocalization(frame_paths=frame_paths, species=species)
        if not review.get("matched"):
            continue

        confidence = float(review.get("confidence", 0))
        if confidence < VOCALIZATION_MATCH_THRESHOLD:
            continue

        if best_match is None or confidence > best_match["confidence"]:
            best_match = {
                "confidence": confidence,
                "anchor_seconds": candidate["center_seconds"],
                "review_reason": review.get("reason", ""),
            }

    if best_match is None:
        return {"matched": False, "reason": "没有找到对着镜头发声的片段"}

    clip_start = max(best_match["anchor_seconds"] - VOCALIZATION_PRE_ROLL_SECONDS, 0.0)
    clip_end = min(best_match["anchor_seconds"] + VOCALIZATION_POST_ROLL_SECONDS, video_duration)

    if clip_end <= clip_start:
        return {"matched": False, "reason": "裁剪片段长度无效"}

    clip_url = clip_video_segment(video_path, clip_start, clip_end)
    return {
        "matched": True,
        "clip_url": clip_url,
        "anchor_seconds": best_match["anchor_seconds"],
        "reason": best_match["review_reason"],
    }


def select_vocalization_candidates(
    pcm_audio: bytes,
    *,
    sample_rate: int = PCM_SAMPLE_RATE,
    sample_width: int = PCM_SAMPLE_WIDTH,
    window_seconds: float = VOCALIZATION_WINDOW_SECONDS,
    hop_seconds: float = VOCALIZATION_HOP_SECONDS,
    min_gap_seconds: float = VOCALIZATION_MIN_GAP_SECONDS,
    top_n: int = VOCALIZATION_REVIEW_TOP_N,
) -> list[dict]:
    if not pcm_audio:
        return []

    bytes_per_second = sample_rate * sample_width
    window_bytes = max(int(bytes_per_second * window_seconds), sample_width)
    hop_bytes = max(int(bytes_per_second * hop_seconds), sample_width)
    if window_bytes <= 0 or hop_bytes <= 0:
        return []

    scores: list[dict] = []
    for offset in range(0, max(len(pcm_audio) - window_bytes + 1, 1), hop_bytes):
        chunk = pcm_audio[offset:offset + window_bytes]
        if len(chunk) < sample_width:
            continue

        score = float(audioop.rms(chunk, sample_width))
        center_seconds = (offset + len(chunk) / 2) / bytes_per_second
        scores.append(
            {
                "score": score,
                "center_seconds": center_seconds,
                "start_seconds": offset / bytes_per_second,
                "end_seconds": (offset + len(chunk)) / bytes_per_second,
            }
        )

    if not scores:
        return []

    scores.sort(key=lambda item: item["score"], reverse=True)
    if scores[0]["score"] <= 0:
        return []

    selected: list[dict] = []
    for candidate in scores:
        too_close = any(
            abs(candidate["center_seconds"] - existing["center_seconds"]) < min_gap_seconds
            for existing in selected
        )
        if too_close:
            continue

        selected.append(candidate)
        if len(selected) >= top_n:
            break

    return selected


def _extract_audio_pcm(video_path: str, sample_rate: int = PCM_SAMPLE_RATE) -> bytes:
    ffmpeg_executable = _get_ffmpeg_executable()
    command = [
        ffmpeg_executable,
        "-v",
        "error",
        "-i",
        video_path,
        "-vn",
        "-ac",
        "1",
        "-ar",
        str(sample_rate),
        "-f",
        "s16le",
        "-acodec",
        "pcm_s16le",
        "pipe:1",
    ]
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if result.returncode != 0 or not result.stdout:
        raise RuntimeError(result.stderr.decode("utf-8", errors="ignore") or "无法提取音频")
    return result.stdout


def _extract_candidate_frames(video_path: str, center_seconds: float, duration_seconds: float) -> list[str]:
    frame_paths: list[str] = []
    capture = cv2.VideoCapture(video_path)
    if not capture.isOpened():
        raise RuntimeError("无法读取视频画面")

    offsets = (-0.4, 0.0, 0.4)
    try:
        for offset in offsets:
            target_seconds = min(max(center_seconds + offset, 0.0), duration_seconds)
            capture.set(cv2.CAP_PROP_POS_MSEC, target_seconds * 1000)
            ok, frame = capture.read()
            if not ok:
                continue

            frame_name = f"frame_vocal_{uuid.uuid4().hex}.jpg"
            frame_path = os.path.join(FRAMES_DIR, frame_name)
            cv2.imwrite(frame_path, frame)
            frame_paths.append(frame_path)
    finally:
        capture.release()

    if not frame_paths:
        raise RuntimeError("无法从候选片段提取画面")
    return frame_paths


def clip_video_segment(video_path: str, start_seconds: float, end_seconds: float) -> str:
    ffmpeg_executable = _get_ffmpeg_executable()
    duration_seconds = max(end_seconds - start_seconds, 0.1)
    clip_name = f"{uuid.uuid4().hex}.mp4"
    clip_path = os.path.join(CLIPS_DIR, clip_name)

    command = [
        ffmpeg_executable,
        "-y",
        "-ss",
        f"{start_seconds:.3f}",
        "-i",
        video_path,
        "-t",
        f"{duration_seconds:.3f}",
        "-c:v",
        "libx264",
        "-preset",
        "veryfast",
        "-pix_fmt",
        "yuv420p",
        "-c:a",
        "aac",
        "-movflags",
        "+faststart",
        clip_path,
    ]
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.decode("utf-8", errors="ignore") or "无法裁剪视频片段")

    return f"/media/clips/{clip_name}"


def get_video_duration(video_path: str) -> float:
    capture = cv2.VideoCapture(video_path)
    if not capture.isOpened():
        raise RuntimeError("无法读取视频时长")

    fps = capture.get(cv2.CAP_PROP_FPS) or 30
    total_frames = capture.get(cv2.CAP_PROP_FRAME_COUNT) or 0
    capture.release()
    if total_frames <= 0:
        return 0.0
    return total_frames / fps


def scan_video_signals(video_path: str, sample_fps: float = COARSE_SCAN_FPS) -> list[dict]:
    capture = cv2.VideoCapture(video_path)
    if not capture.isOpened():
        raise RuntimeError("无法读取视频画面")

    duration = get_video_duration(video_path)
    if duration <= 0:
        capture.release()
        return []

    sample_interval = max(1.0 / max(sample_fps, 0.1), 0.1)
    timestamps = []
    current = 0.0
    while current < duration:
        timestamps.append(round(current, 3))
        current += sample_interval
    if not timestamps or timestamps[-1] < duration:
        timestamps.append(round(duration, 3))

    samples: list[dict] = []
    prev_gray = None
    prev_centroid = None

    try:
        for timestamp in timestamps:
            capture.set(cv2.CAP_PROP_POS_MSEC, timestamp * 1000)
            ok, frame = capture.read()
            if not ok:
                continue

            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
            gray = cv2.GaussianBlur(gray, (21, 21), 0)
            frame_height, frame_width = gray.shape[:2]
            frame_area = max(frame_height * frame_width, 1)
            motion_score = 0.0
            contour_count = 0
            area_ratio = 0.0
            edge_bias = 0.0
            speed_score = 0.0
            centroid_x = None
            centroid_y = None

            if prev_gray is not None:
                frame_delta = cv2.absdiff(prev_gray, gray)
                thresh = cv2.threshold(frame_delta, 20, 255, cv2.THRESH_BINARY)[1]
                thresh = cv2.dilate(thresh, None, iterations=2)
                motion_pixels = float(cv2.countNonZero(thresh))
                motion_score = motion_pixels / frame_area

                contours, _ = cv2.findContours(
                    thresh,
                    cv2.RETR_EXTERNAL,
                    cv2.CHAIN_APPROX_SIMPLE,
                )
                meaningful_contours = [cnt for cnt in contours if cv2.contourArea(cnt) >= 200]
                contour_count = len(meaningful_contours)
                if meaningful_contours:
                    x, y, w, h = cv2.boundingRect(cv2.vconcat(meaningful_contours))
                    area_ratio = (w * h) / frame_area
                    moments = cv2.moments(thresh)
                    if moments["m00"]:
                        centroid_x = float(moments["m10"] / moments["m00"]) / frame_width
                        centroid_y = float(moments["m01"] / moments["m00"]) / frame_height
                        if prev_centroid is not None:
                            speed_score = math.dist(prev_centroid, (centroid_x, centroid_y))
                        if centroid_x <= 0.2 or centroid_x >= 0.8:
                            edge_bias += 0.5
                        if centroid_y <= 0.2 or centroid_y >= 0.8:
                            edge_bias += 0.5

            if motion_score > 0.002 and centroid_x is not None and centroid_y is not None:
                prev_centroid = (centroid_x, centroid_y)
            elif motion_score <= 0.001:
                prev_centroid = None

            samples.append(
                {
                    "timestamp": timestamp,
                    "motion_score": round(motion_score, 6),
                    "contour_count": contour_count,
                    "area_ratio": round(area_ratio, 6),
                    "edge_bias": round(edge_bias, 3),
                    "speed_score": round(speed_score, 6),
                    "centroid_x": centroid_x,
                    "centroid_y": centroid_y,
                }
            )
            prev_gray = gray
    finally:
        capture.release()

    by_second: dict[int, list[dict]] = {}
    for sample in samples:
        second_bucket = int(sample["timestamp"])
        by_second.setdefault(second_bucket, []).append(sample)

    signals: list[dict] = []
    prev_motion = 0.0
    for second in sorted(by_second):
        bucket = by_second[second]
        motion_values = [item["motion_score"] for item in bucket]
        speed_values = [item["speed_score"] for item in bucket]
        edge_values = [item["edge_bias"] for item in bucket]
        active_ratio = sum(1 for item in bucket if item["motion_score"] >= 0.003) / max(len(bucket), 1)
        motion_score = max(motion_values) if motion_values else 0.0
        novelty_score = abs(motion_score - prev_motion)
        signals.append(
            {
                "second": float(second),
                "motion_score": round(motion_score, 6),
                "mean_motion_score": round(sum(motion_values) / max(len(motion_values), 1), 6),
                "speed_score": round(max(speed_values) if speed_values else 0.0, 6),
                "edge_bias": round(max(edge_values) if edge_values else 0.0, 3),
                "active_ratio": round(active_ratio, 3),
                "novelty_score": round(novelty_score, 6),
                "sample_count": len(bucket),
            }
        )
        prev_motion = motion_score

    return signals


def detect_candidate_segments(video_path: str, sample_fps: float = COARSE_SCAN_FPS) -> list[dict]:
    duration = get_video_duration(video_path)
    signals = scan_video_signals(video_path, sample_fps=sample_fps)
    if not signals:
        return []

    segments: list[dict] = []
    open_start = None
    active_run = 0
    inactive_run = 0
    window_metrics = {
        "max_motion": 0.0,
        "max_speed": 0.0,
        "max_novelty": 0.0,
        "max_edge_bias": 0.0,
    }

    for signal in signals:
        interesting = (
            signal["motion_score"] >= 0.006
            or signal["speed_score"] >= 0.08
            or signal["novelty_score"] >= 0.01
            or (signal["edge_bias"] >= 0.5 and signal["motion_score"] >= 0.003)
        )

        if interesting:
            active_run += 1
            inactive_run = 0
            if open_start is None and active_run >= 2:
                open_start = max(signal["second"] - 1.0, 0.0)
                window_metrics = {
                    "max_motion": signal["motion_score"],
                    "max_speed": signal["speed_score"],
                    "max_novelty": signal["novelty_score"],
                    "max_edge_bias": signal["edge_bias"],
                }
            elif open_start is not None:
                window_metrics["max_motion"] = max(window_metrics["max_motion"], signal["motion_score"])
                window_metrics["max_speed"] = max(window_metrics["max_speed"], signal["speed_score"])
                window_metrics["max_novelty"] = max(window_metrics["max_novelty"], signal["novelty_score"])
                window_metrics["max_edge_bias"] = max(window_metrics["max_edge_bias"], signal["edge_bias"])
        else:
            inactive_run += 1
            active_run = 0
            if open_start is not None and inactive_run >= 3:
                end_second = min(signal["second"] - 2.0, duration)
                if end_second - open_start >= SEGMENT_MIN_SECONDS:
                    segments.append(
                        {
                            "start_seconds": max(open_start - SEGMENT_PRE_ROLL_SECONDS, 0.0),
                            "end_seconds": min(end_second + SEGMENT_POST_ROLL_SECONDS, duration),
                            "signal_summary": dict(window_metrics),
                        }
                    )
                open_start = None

    if open_start is not None:
        end_second = duration
        if end_second - open_start >= SEGMENT_MIN_SECONDS:
            segments.append(
                {
                    "start_seconds": max(open_start - SEGMENT_PRE_ROLL_SECONDS, 0.0),
                    "end_seconds": min(end_second + SEGMENT_POST_ROLL_SECONDS, duration),
                    "signal_summary": dict(window_metrics),
                }
            )

    segments = _merge_segments(segments, duration)
    segments = _split_segments(segments)
    segments = _inject_rest_segments(segments, duration)
    segments = _merge_segments(segments, duration)

    if not segments:
        peak_signal = max(signals, key=lambda item: item["motion_score"] + item["novelty_score"])
        start_seconds = max(peak_signal["second"] - 4.0, 0.0)
        end_seconds = min(start_seconds + 10.0, duration)
        segments = [
            {
                "start_seconds": start_seconds,
                "end_seconds": max(end_seconds, min(duration, start_seconds + SEGMENT_MIN_SECONDS)),
                "signal_summary": {
                    "max_motion": peak_signal["motion_score"],
                    "max_speed": peak_signal["speed_score"],
                    "max_novelty": peak_signal["novelty_score"],
                    "max_edge_bias": peak_signal["edge_bias"],
                    "fallback": True,
                },
            }
        ]

    return segments


def _inject_rest_segments(segments: list[dict], duration: float) -> list[dict]:
    if not segments:
        return segments

    enriched = list(segments)
    sorted_segments = sorted(segments, key=lambda item: item["start_seconds"])
    for index in range(len(sorted_segments) - 1):
        gap_start = sorted_segments[index]["end_seconds"]
        gap_end = sorted_segments[index + 1]["start_seconds"]
        gap = gap_end - gap_start
        if gap < 20.0:
            continue

        start_seconds = gap_start
        end_seconds = min(gap_start + 20.0, gap_end, duration)
        if end_seconds - start_seconds < SEGMENT_MIN_SECONDS:
            continue

        enriched.append(
            {
                "start_seconds": start_seconds,
                "end_seconds": end_seconds,
                "signal_summary": {
                    "max_motion": 0.0,
                    "max_speed": 0.0,
                    "max_novelty": 0.0,
                    "max_edge_bias": 0.0,
                    "rest_candidate": True,
                },
            }
        )
    return enriched


def _merge_segments(segments: list[dict], duration: float) -> list[dict]:
    if not segments:
        return []

    merged = []
    for segment in sorted(segments, key=lambda item: item["start_seconds"]):
        start_seconds = max(float(segment["start_seconds"]), 0.0)
        end_seconds = min(float(segment["end_seconds"]), duration)
        if end_seconds - start_seconds < SEGMENT_MIN_SECONDS:
            continue

        if merged and start_seconds - merged[-1]["end_seconds"] < SEGMENT_MERGE_GAP_SECONDS:
            merged[-1]["end_seconds"] = max(merged[-1]["end_seconds"], end_seconds)
            for metric_key, metric_value in segment.get("signal_summary", {}).items():
                if isinstance(metric_value, (int, float)):
                    merged[-1]["signal_summary"][metric_key] = max(
                        float(merged[-1]["signal_summary"].get(metric_key, 0.0)),
                        float(metric_value),
                    )
                else:
                    merged[-1]["signal_summary"][metric_key] = metric_value
            continue

        merged.append(
            {
                "start_seconds": start_seconds,
                "end_seconds": end_seconds,
                "signal_summary": dict(segment.get("signal_summary", {})),
            }
        )
    return merged


def _split_segments(segments: list[dict]) -> list[dict]:
    split_segments: list[dict] = []
    for segment in segments:
        start_seconds = float(segment["start_seconds"])
        end_seconds = float(segment["end_seconds"])
        signal_summary = dict(segment.get("signal_summary", {}))
        if end_seconds - start_seconds <= SEGMENT_MAX_SECONDS:
            split_segments.append(segment)
            continue

        current_start = start_seconds
        while current_start < end_seconds:
            current_end = min(current_start + SEGMENT_TARGET_SECONDS, end_seconds)
            if current_end - current_start < SEGMENT_MIN_SECONDS:
                break
            split_segments.append(
                {
                    "start_seconds": current_start,
                    "end_seconds": current_end,
                    "signal_summary": dict(signal_summary),
                }
            )
            current_start = current_end
    return split_segments


def capture_frame_at(video_path: str, at_seconds: float, prefix: str = "frame_clip") -> Optional[str]:
    capture = cv2.VideoCapture(video_path)
    if not capture.isOpened():
        raise RuntimeError("无法读取视频画面")

    try:
        capture.set(cv2.CAP_PROP_POS_MSEC, max(at_seconds, 0.0) * 1000)
        ok, frame = capture.read()
        if not ok:
            return None

        frame_name = f"{prefix}_{uuid.uuid4().hex}.jpg"
        frame_path = os.path.join(FRAMES_DIR, frame_name)
        cv2.imwrite(frame_path, frame)
        return frame_path
    finally:
        capture.release()


def extract_representative_frames(
    video_path: str,
    *,
    start_seconds: float = 0.0,
    end_seconds: Optional[float] = None,
    num_frames: int = 3,
    prefix: str = "frame_clip",
) -> list[str]:
    duration = get_video_duration(video_path)
    end = min(end_seconds if end_seconds is not None else duration, duration)
    start = max(start_seconds, 0.0)
    if end <= start:
        return []

    if num_frames <= 1:
        timestamps = [(start + end) / 2.0]
    else:
        span = max(end - start, 0.1)
        timestamps = [start + span * (index + 1) / (num_frames + 1) for index in range(num_frames)]

    frame_paths = []
    for timestamp in timestamps:
        frame_path = capture_frame_at(video_path, timestamp, prefix=prefix)
        if frame_path:
            frame_paths.append(frame_path)
    return frame_paths


def _get_ffmpeg_executable() -> str:
    for env_key in ("PETPAL_FFMPEG_PATH", "IMAGEIO_FFMPEG_EXE"):
        configured_path = _resolve_executable(os.environ.get(env_key))
        if configured_path:
            return configured_path

    system_ffmpeg = _resolve_executable("ffmpeg")
    if system_ffmpeg:
        return system_ffmpeg

    try:
        imageio_ffmpeg = importlib.import_module("imageio_ffmpeg")
    except ImportError as exc:
        raise RuntimeError(
            "未找到可用的 ffmpeg。请安装系统 ffmpeg，或在后端环境中安装 imageio-ffmpeg。"
        ) from exc

    return imageio_ffmpeg.get_ffmpeg_exe()


def _resolve_executable(candidate: Optional[str]) -> Optional[str]:
    if not candidate:
        return None
    return shutil.which(candidate)
