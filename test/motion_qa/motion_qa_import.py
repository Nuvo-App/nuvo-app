#!/usr/bin/env python3
"""
Motion QA Video Importer + Pose Extractor

Downloads video (YouTube via yt-dlp, or direct URL, or local file),
trims to specified segment, extracts pose data using MediaPipe,
and outputs a Nuvo-compatible JSON fixture.

Usage:
  python3 motion_qa_import.py --url <URL> --movement jump_squats --expected-reps 5 --start 5 --end 30 --id yt_jump_squat_001
  python3 motion_qa_import.py --file ./clip.mp4 --movement jump_squats --expected-reps 3 --id local_001
  python3 motion_qa_import.py --manifest real_video_sources.json --outdir test/motion_qa/fixtures/real

Output: JSON fixture file compatible with Nuvo ReplayFixture format.
"""

import argparse
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

try:
    import cv2
    import mediapipe as mp
    import numpy as np
except ImportError as e:
    print(f"ERROR: Missing dependency: {e}", file=sys.stderr)
    print("Install with: pip3 install --break-system-packages mediapipe opencv-python-headless numpy", file=sys.stderr)
    sys.exit(1)

# MediaPipe Pose landmark names (same as ML Kit naming used by Nuvo)
LANDMARK_NAMES = [
    'nose',
    'leftEyeInner', 'leftEye', 'leftEyeOuter',
    'rightEyeInner', 'rightEye', 'rightEyeOuter',
    'leftEar', 'rightEar',
    'mouthLeft', 'mouthRight',
    'leftShoulder', 'rightShoulder',
    'leftElbow', 'rightElbow',
    'leftWrist', 'rightWrist',
    'leftPinky', 'rightPinky',
    'leftIndex', 'rightIndex',
    'leftThumb', 'rightThumb',
    'leftHip', 'rightHip',
    'leftKnee', 'rightKnee',
    'leftAnkle', 'rightAnkle',
    'leftHeel', 'rightHeel',
    'leftFootIndex', 'rightFootIndex',
]

# Only output landmarks that Nuvo uses (subset)
NUVO_LANDMARKS = {
    11: 'leftShoulder', 12: 'rightShoulder',
    13: 'leftElbow', 14: 'rightElbow',
    15: 'leftWrist', 16: 'rightWrist',
    23: 'leftHip', 24: 'rightHip',
    25: 'leftKnee', 26: 'rightKnee',
    27: 'leftAnkle', 28: 'rightAnkle',
}


def download_video(url, output_path):
    """Download video using yt-dlp."""
    cmd = [
        'yt-dlp',
        '-f', 'best[height<=720][ext=mp4]/best[height<=720]/best',
        '--no-playlist',
        '--no-warnings',
        '-o', output_path,
        url,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"  yt-dlp failed: {result.stderr[:200]}", file=sys.stderr)
        return False
    return True


def trim_video(input_path, output_path, start_sec, end_sec):
    """Trim video to specified segment using ffmpeg."""
    duration = end_sec - start_sec if end_sec else None
    cmd = [
        'ffmpeg', '-y', '-loglevel', 'error',
        '-ss', str(start_sec),
        '-i', input_path,
    ]
    if duration:
        cmd.extend(['-t', str(duration)])
    cmd.extend([
        '-c:v', 'libx264', '-preset', 'fast', '-crf', '28',
        '-an',
        output_path,
    ])
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"  ffmpeg trim failed: {result.stderr[:200]}", file=sys.stderr)
        return False
    return True


def extract_poses(video_path, max_frames=300, model_path='test/motion_qa/models/pose_landmarker.task'):
    """Extract pose data from video using MediaPipe PoseLandmarker (Tasks API).
    
    Returns list of frames, each with normalized landmarks and likelihoods.
    """
    from mediapipe.tasks import python
    from mediapipe.tasks.python import vision
    
    if not os.path.exists(model_path):
        print(f"  ERROR: Model not found: {model_path}", file=sys.stderr)
        print(f"  Download: curl -L -o {model_path} 'https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/1/pose_landmarker_lite.task'", file=sys.stderr)
        return []
    
    frames = []
    frame_index = 0
    
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        print(f"  ERROR: Cannot open video: {video_path}", file=sys.stderr)
        return []
    
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    
    options = vision.PoseLandmarkerOptions(
        base_options=python.BaseOptions(model_asset_path=model_path),
        running_mode=vision.RunningMode.VIDEO,
        num_poses=1,
        min_pose_detection_confidence=0.3,
        min_pose_presence_confidence=0.3,
        min_tracking_confidence=0.3,
    )
    
    with vision.PoseLandmarker.create_from_options(options) as landmarker:
        while cap.isOpened() and frame_index < max_frames:
            ret, frame = cap.read()
            if not ret:
                break
            
            # Convert BGR to RGB
            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            h, w = rgb.shape[:2]
            
            # Create MediaPipe Image
            mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
            
            # Calculate timestamp in milliseconds
            timestamp_ms = int(frame_index * 1000.0 / fps)
            
            try:
                result = landmarker.detect_for_video(mp_image, timestamp_ms)
            except Exception as e:
                result = None
            
            landmarks = {}
            if result and result.pose_landmarks and len(result.pose_landmarks) > 0:
                pose_lms = result.pose_landmarks[0]
                for idx, name in NUVO_LANDMARKS.items():
                    if idx < len(pose_lms):
                        lm = pose_lms[idx]
                        # MediaPipe Tasks gives normalized [0,1] coords with visibility
                        likelihood = lm.visibility if lm.visibility > 0 else 0.0
                        # Output as [x, y, z, likelihood] array to match Dart RecordedLandmark
                        landmarks[name] = [
                            round(max(0.0, min(1.0, lm.x)), 6),
                            round(max(0.0, min(1.0, lm.y)), 6),
                            round(lm.z, 6),
                            round(max(0.0, min(1.0, likelihood)), 4),
                        ]
            
            frames.append({
                'frameIndex': frame_index,
                'landmarks': landmarks,
            })
            frame_index += 1
    
    cap.release()
    return frames


def build_fixture(fixture_id, movement, expected_reps, frames, source_info):
    """Build a Nuvo-compatible ReplayFixture JSON."""
    return {
        'id': fixture_id,
        'movement': movement,
        'expected': {
            'reps': expected_reps,
            'shouldMatch': movement == 'jump_squats',
        },
        'source': {
            'type': source_info.get('sourceType', 'local'),
            'name': source_info.get('title', fixture_id),
            'extractor': 'mediapipe',
            'cameraView': 'front',
            'qualityTier': 'real_video',
        },
        'frames': frames,
        'label': source_info.get('title', fixture_id),
        'tags': ['real_video', 'mediapipe', source_info.get('movement', '')],
    }


def process_single(url=None, file_path=None, fixture_id=None, movement='jump_squats',
                    expected_reps=3, start_sec=0, end_sec=None, source_info=None,
                    output_dir='test/motion_qa/fixtures/real'):
    """Process a single video source."""
    if source_info is None:
        source_info = {}
    
    os.makedirs(output_dir, exist_ok=True)
    
    with tempfile.TemporaryDirectory() as tmpdir:
        if file_path:
            video_path = file_path
            print(f"  Using local file: {video_path}")
        else:
            # Download from YouTube or URL
            raw_path = os.path.join(tmpdir, 'raw.mp4')
            print(f"  Downloading: {url}")
            if not download_video(url, raw_path):
                print(f"  FAILED to download", file=sys.stderr)
                return None
            video_path = raw_path
        
        # Trim if needed
        if start_sec > 0 or end_sec is not None:
            trimmed_path = os.path.join(tmpdir, 'trimmed.mp4')
            print(f"  Trimming: {start_sec}s - {end_sec}s")
            if not trim_video(video_path, trimmed_path, start_sec, end_sec or 999):
                # If trim fails, try using the raw video
                print(f"  Trim failed, using full video")
            else:
                video_path = trimmed_path
        
        # Extract poses
        print(f"  Extracting poses...")
        frames = extract_poses(video_path)
        
        if not frames:
            print(f"  No frames extracted!", file=sys.stderr)
            return None
        
        print(f"  Extracted {len(frames)} frames")
        
        # Build fixture
        fixture = build_fixture(fixture_id, movement, expected_reps, frames, source_info)
        
        # Write output
        output_path = os.path.join(output_dir, f'{fixture_id}.json')
        with open(output_path, 'w') as f:
            json.dump(fixture, f, indent=2)
        
        print(f"  Written: {output_path}")
        return output_path


def process_manifest(manifest_path, output_dir):
    """Process all entries in a source manifest."""
    with open(manifest_path) as f:
        sources = json.load(f)
    
    results = []
    for src in sources:
        sid = src['id']
        print(f"\n[{sid}] {src.get('title', 'unknown')}")
        
        source_info = {
            'sourceType': src.get('sourceType', 'youtube'),
            'title': src.get('title', sid),
            'movement': src.get('movement', ''),
        }
        
        result = process_single(
            url=src.get('url'),
            fixture_id=sid,
            movement=src.get('movement', 'jump_squats'),
            expected_reps=src.get('expectedReps', 3),
            start_sec=src.get('startSec', 0),
            end_sec=src.get('endSec'),
            source_info=source_info,
            output_dir=output_dir,
        )
        
        results.append({
            'id': sid,
            'success': result is not None,
            'output': result,
            'movement': src.get('movement'),
            'expectedReps': src.get('expectedReps'),
            'url': src.get('url'),
            'uploader': src.get('uploader'),
            'license': src.get('license'),
            'usageStatus': src.get('usageStatus'),
        })
    
    # Write import log
    log_path = os.path.join(output_dir, 'import_log.json')
    with open(log_path, 'w') as f:
        json.dump(results, f, indent=2)
    
    successful = sum(1 for r in results if r['success'])
    print(f"\n=== Import complete: {successful}/{len(results)} succeeded ===")
    print(f"Log: {log_path}")
    return results


def main():
    parser = argparse.ArgumentParser(description='Motion QA Video Importer')
    parser.add_argument('--url', help='Video URL (YouTube or direct)')
    parser.add_argument('--file', help='Local video file path')
    parser.add_argument('--manifest', help='JSON manifest of sources')
    parser.add_argument('--id', help='Fixture ID', default='real_001')
    parser.add_argument('--movement', default='jump_squats',
                        choices=['jump_squats', 'normal_squats', 'vertical_jumps', 'jumping_jacks'])
    parser.add_argument('--expected-reps', type=int, default=3)
    parser.add_argument('--start', type=float, default=0, help='Start time in seconds')
    parser.add_argument('--end', type=float, default=None, help='End time in seconds')
    parser.add_argument('--outdir', default='test/motion_qa/fixtures/real',
                        help='Output directory for fixtures')
    
    args = parser.parse_args()
    
    if args.manifest:
        process_manifest(args.manifest, args.outdir)
    elif args.url or args.file:
        process_single(
            url=args.url,
            file_path=args.file,
            fixture_id=args.id,
            movement=args.movement,
            expected_reps=args.expected_reps,
            start_sec=args.start,
            end_sec=args.end,
            output_dir=args.outdir,
        )
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == '__main__':
    main()
