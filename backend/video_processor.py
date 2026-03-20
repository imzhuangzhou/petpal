import os
import cv2
import time
from datetime import datetime, timedelta
import random


FRAMES_DIR = os.path.join(os.path.dirname(__file__), "frames")
os.makedirs(FRAMES_DIR, exist_ok=True)


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
    last_capture_time = -frame_interval  # Allow immediate first capture
    frame_idx = 0

    while True:
        ret, frame = cap.read()
        if not ret:
            break

        current_time = frame_idx / fps

        # Convert to grayscale for motion detection
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        gray = cv2.GaussianBlur(gray, (21, 21), 0)

        if prev_gray is not None and (current_time - last_capture_time) >= frame_interval:
            # Frame difference for motion detection
            frame_delta = cv2.absdiff(prev_gray, gray)
            thresh = cv2.threshold(frame_delta, 25, 255, cv2.THRESH_BINARY)[1]
            motion_score = thresh.sum() / 255

            if motion_score > motion_threshold:
                # Save frame
                timestamp_str = datetime.now().strftime("%Y%m%d_%H%M%S")
                frame_filename = f"frame_{timestamp_str}_{frame_idx}.jpg"
                frame_path = os.path.join(FRAMES_DIR, frame_filename)
                cv2.imwrite(frame_path, frame)

                captured_frames.append({
                    "frame_path": frame_path,
                    "timestamp": current_time,
                    "frame_index": frame_idx,
                    "video_time_str": f"{int(current_time // 60):02d}:{int(current_time % 60):02d}"
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
            "video_time_str": f"{int(current_time // 60):02d}:{int(current_time % 60):02d}"
        })

    cap.release()
    print(f"   ✅ Uniformly extracted {len(captured_frames)} frames")
    return captured_frames
