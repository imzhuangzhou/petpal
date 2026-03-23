import audioop
import importlib
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
