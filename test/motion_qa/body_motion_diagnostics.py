#!/usr/bin/env python3
"""
Body-Motion Diagnostic Signal Extractor

For every frame in every real video fixture, extracts:
- Lower body signals (knee angles, hip position/velocity, hip descent/ascent)
- Feet/jump signals (ankle displacement, velocity, foot separation, airborne likelihood)
- Torso signals (shoulder/hip center Y, torso length, torso translation)
- Pose quality signals (landmark confidence, missing counts, body scale)
- Temporal signals (consecutive matching frames, phase transition timing)

Then classifies each frame into diagnostic "motion concepts" and
aggregates per-rep failure analysis.

Output: JSON report + human-readable summary.
"""

import json
import os
import math
from collections import defaultdict

LANDMARK_NAMES = [
    'leftShoulder', 'rightShoulder',
    'leftElbow', 'rightElbow',
    'leftWrist', 'rightWrist',
    'leftHip', 'rightHip',
    'leftKnee', 'rightKnee',
    'leftAnkle', 'rightAnkle',
]

MIN_LIKELIHOOD = 0.35

def get_lm(frame, name):
    """Get landmark [x, y, z, likelihood] or None."""
    lms = frame.get('landmarks', {})
    lm = lms.get(name)
    if lm is None or len(lm) < 4 or lm[3] < MIN_LIKELIHOOD:
        return None
    return lm

def safe_div(a, b):
    if abs(b) < 1e-6:
        return 0.0
    return a / b

def clamp(v, lo, hi):
    return max(lo, min(hi, v))

def angle_3pt(a, b, c):
    """Angle at point b given points a, b, c (using x,y)."""
    abx = a[0] - b[0]
    aby = a[1] - b[1]
    cbx = c[0] - b[0]
    cby = c[1] - b[1]
    dot = abx * cbx + aby * cby
    ab = math.sqrt(abx**2 + aby**2)
    cb = math.sqrt(cbx**2 + cby**2)
    if ab < 1e-6 or cb < 1e-6:
        return 180.0
    cos_val = clamp(dot / (ab * cb), -1.0, 1.0)
    return math.degrees(math.acos(cos_val))

def extract_signals(frames):
    """Extract per-frame body-motion signals."""
    signals = []
    prev_hip_y = None
    prev_ankle_avg_y = None
    prev_shoulder_y = None
    
    for i, frame in enumerate(frames):
        s = {'frame': i, 'valid': False}
        
        # Get key landmarks
        ls = get_lm(frame, 'leftShoulder')
        rs = get_lm(frame, 'rightShoulder')
        lh = get_lm(frame, 'leftHip')
        rh = get_lm(frame, 'rightHip')
        lk = get_lm(frame, 'leftKnee')
        rk = get_lm(frame, 'rightKnee')
        la = get_lm(frame, 'leftAnkle')
        ra = get_lm(frame, 'rightAnkle')
        lw = get_lm(frame, 'leftWrist')
        rw = get_lm(frame, 'rightWrist')
        
        # Confidence tracking
        confidences = {}
        for name in LANDMARK_NAMES:
            lm = frame.get('landmarks', {}).get(name)
            if lm and len(lm) >= 4:
                confidences[name] = lm[3]
            else:
                confidences[name] = 0.0
        
        s['confidences'] = confidences
        s['missing_count'] = sum(1 for v in confidences.values() if v < MIN_LIKELIHOOD)
        
        # Missing ankle/knee/hip specifically
        s['missing_ankles'] = (1 if la is None else 0) + (1 if ra is None else 0)
        s['missing_knees'] = (1 if lk is None else 0) + (1 if rk is None else 0)
        s['missing_hips'] = (1 if lh is None else 0) + (1 if rh is None else 0)
        
        if not all([ls, rs, lh, rh, lk, rk]):
            signals.append(s)
            prev_hip_y = None
            prev_ankle_avg_y = None
            prev_shoulder_y = None
            continue
        
        # Core positions
        shoulder_y = (ls[1] + rs[1]) / 2
        hip_y = (lh[1] + rh[1]) / 2
        knee_y = (lk[1] + rk[1]) / 2
        torso_height = abs(hip_y - shoulder_y)
        torso_height_clamped = clamp(torso_height, 0.12, 0.6)
        
        s['shoulder_y'] = round(shoulder_y, 6)
        s['hip_y'] = round(hip_y, 6)
        s['knee_y'] = round(knee_y, 6)
        s['torso_height'] = round(torso_height, 6)
        s['torso_height_clamped'] = round(torso_height_clamped, 6)
        
        # Hip-to-knee ratio (key signal)
        hkr = safe_div(knee_y - hip_y, torso_height)
        s['hip_to_knee_ratio'] = round(clamp(hkr, -2.0, 3.0), 6)
        
        # Knee angles
        if la and ra:
            s['left_knee_angle'] = round(angle_3pt(lh, lk, la), 2)
            s['right_knee_angle'] = round(angle_3pt(rh, rk, ra), 2)
            s['avg_knee_angle'] = round((s['left_knee_angle'] + s['right_knee_angle']) / 2, 2)
        elif la:
            s['left_knee_angle'] = round(angle_3pt(lh, lk, la), 2)
            s['avg_knee_angle'] = s['left_knee_angle']
        elif ra:
            s['right_knee_angle'] = round(angle_3pt(rh, rk, ra), 2)
            s['avg_knee_angle'] = s['right_knee_angle']
        
        # Bilateral knee flexion (how bent are knees, 180=straight, 90=deep)
        s['knee_flexion'] = round(180 - s.get('avg_knee_angle', 180), 2)
        
        # Hip vertical velocity (negative = descending, positive = ascending)
        if prev_hip_y is not None:
            s['hip_velocity'] = round(hip_y - prev_hip_y, 6)
        else:
            s['hip_velocity'] = 0.0
        
        # Ankle signals
        if la and ra:
            ankle_avg_y = (la[1] + ra[1]) / 2
            s['ankle_avg_y'] = round(ankle_avg_y, 6)
            s['foot_separation'] = round(abs(la[0] - ra[0]), 6)
            
            if prev_ankle_avg_y is not None:
                s['ankle_velocity'] = round(ankle_avg_y - prev_ankle_avg_y, 6)
            else:
                s['ankle_velocity'] = 0.0
            
            # Ankle rise relative to first valid frame (set baseline)
            # This is computed in post-processing
        else:
            s['ankle_avg_y'] = None
            s['foot_separation'] = None
            s['ankle_velocity'] = 0.0
        
        # Shoulder velocity (for camera motion detection)
        if prev_shoulder_y is not None:
            s['shoulder_velocity'] = round(shoulder_y - prev_shoulder_y, 6)
        else:
            s['shoulder_velocity'] = 0.0
        
        # Wrist positions (for jumping jack detection)
        if lw and rw:
            s['wrist_y_avg'] = round((lw[1] + rw[1]) / 2, 6)
            s['wrist_spread'] = round(abs(lw[0] - rw[0]), 6)
        
        # Body scale variation
        if torso_height > 0:
            s['body_scale'] = round(torso_height, 6)
        
        s['valid'] = True
        signals.append(s)
        prev_hip_y = hip_y
        prev_ankle_avg_y = s.get('ankle_avg_y')
        prev_shoulder_y = shoulder_y
    
    return signals

def classify_concepts(signals, baseline_ankle_y=None):
    """Classify each frame into motion concepts."""
    if baseline_ankle_y is None:
        # Find first valid ankle position as baseline
        for s in signals:
            if s.get('ankle_avg_y') is not None:
                baseline_ankle_y = s['ankle_avg_y']
                break
        if baseline_ankle_y is None:
            baseline_ankle_y = 0.6
    
    for s in signals:
        concepts = {}
        
        if not s['valid']:
            concepts['pose_quality_low'] = True
            s['concepts'] = concepts
            continue
        
        hkr = s.get('hip_to_knee_ratio', 0)
        knee_flex = s.get('knee_flexion', 0)
        hip_vel = s.get('hip_velocity', 0)
        ankle_vel = s.get('ankle_velocity', 0)
        shoulder_vel = s.get('shoulder_velocity', 0)
        
        # Standing-like: high hkr, knees relatively straight
        concepts['standing_like'] = hkr > 0.70 and knee_flex < 40
        
        # Athletic stance: moderate hkr, slight knee bend
        concepts['athletic_stance'] = 0.55 < hkr <= 0.75 and 20 < knee_flex < 60
        
        # Knees flexing: increasing knee flexion
        concepts['knees_flexing'] = knee_flex > 40 and hip_vel > 0.005
        
        # Knees extending: decreasing knee flexion (straightening)
        concepts['knees_extending'] = knee_flex > 30 and hip_vel < -0.005
        
        # Hips descending: hip Y increasing (moving down in image)
        concepts['hips_descending'] = hip_vel > 0.01
        
        # Hips ascending: hip Y decreasing (moving up in image)
        concepts['hips_ascending'] = hip_vel < -0.01
        
        # Body rising fast: significant upward movement
        concepts['body_rising_fast'] = hip_vel < -0.03
        
        # Feet rising: ankles moving up (Y decreasing)
        concepts['feet_rising'] = ankle_vel < -0.015
        
        # Airborne candidate: ankles significantly above baseline
        ankle_y = s.get('ankle_avg_y')
        if ankle_y is not None:
            ankle_rise = baseline_ankle_y - ankle_y
            torso_h = s.get('torso_height_clamped', 0.2)
            concepts['airborne_candidate'] = ankle_rise > torso_h * 0.18
            concepts['grounded_candidate'] = abs(ankle_rise) < torso_h * 0.10
            s['ankle_rise'] = round(ankle_rise, 6)
            s['ankle_rise_ratio'] = round(safe_div(ankle_rise, torso_h), 6)
        else:
            concepts['airborne_candidate'] = False
            concepts['grounded_candidate'] = False
            s['ankle_rise'] = None
            s['ankle_rise_ratio'] = None
        
        # Landing candidate: was airborne, now returning to grounded
        concepts['landing_candidate'] = concepts['grounded_candidate'] and ankle_vel > 0.01
        
        # Legs spreading (jumping jack)
        fs = s.get('foot_separation')
        if fs is not None:
            concepts['legs_spreading'] = fs > 0.15
            concepts['legs_closing'] = fs < 0.08
        
        # Camera translation estimate: shoulder and hip move together
        # but ankle doesn't (or all move together = camera)
        if abs(shoulder_vel) > 0.01 and abs(hip_vel) > 0.01:
            same_dir = (shoulder_vel > 0) == (hip_vel > 0)
            ankle_also = abs(ankle_vel) > 0.005 and (ankle_vel > 0) == (shoulder_vel > 0)
            if same_dir and ankle_also:
                concepts['camera_translation_likely'] = True
        
        # Pose quality
        if s['missing_ankles'] > 0:
            concepts['ankle_confidence_loss'] = True
        if s['missing_knees'] > 0:
            concepts['knee_confidence_loss'] = True
        if s.get('hip_to_knee_ratio', 0) > 2.5 or s.get('hip_to_knee_ratio', 0) < -1.5:
            concepts['pose_outlier'] = True
        
        s['concepts'] = concepts
    
    return signals

def analyze_rep_windows(signals, movement):
    """Identify candidate rep windows based on signal patterns."""
    windows = []
    
    if movement in ('jump_squats', 'vertical_jumps', 'lunge_jumps'):
        # Look for: standing → squat/dip → airborne → landing cycles
        in_window = False
        window_start = 0
        prev_airborne = False
        
        for i, s in enumerate(signals):
            if not s['valid']:
                continue
            
            concepts = s.get('concepts', {})
            is_airborne = concepts.get('airborne_candidate', False)
            is_standing = concepts.get('standing_like', False) or concepts.get('athletic_stance', False)
            is_squat = s.get('hip_to_knee_ratio', 1) < 0.58 or concepts.get('knees_flexing', False)
            
            if is_standing and not in_window:
                in_window = True
                window_start = i
            
            if is_airborne and in_window and not prev_airborne:
                # Airborne started - mark transition
                pass
            
            if concepts.get('grounded_candidate', False) and prev_airborne and in_window:
                # Landing detected - end of rep
                windows.append({
                    'start': window_start,
                    'end': i,
                    'airborne_frame': None,
                    'has_airborne': True,
                })
                in_window = False
            
            prev_airborne = is_airborne
    
    elif movement in ('normal_squats', 'deep_squats'):
        # Look for: standing → squat → standing cycles
        in_window = False
        window_start = 0
        was_squat = False
        
        for i, s in enumerate(signals):
            if not s['valid']:
                continue
            
            hkr = s.get('hip_to_knee_ratio', 1)
            is_standing = hkr > 0.65
            is_squat = hkr < 0.50
            
            if is_standing and not in_window:
                in_window = True
                window_start = i
                was_squat = False
            
            if is_squat and in_window:
                was_squat = True
            
            if is_standing and was_squat and in_window:
                windows.append({
                    'start': window_start,
                    'end': i,
                    'airborne_frame': None,
                    'has_airborne': False,
                })
                in_window = False
                was_squat = False
    
    elif movement == 'jumping_jacks':
        # Look for: legs closing → legs spreading → legs closing cycles
        in_window = False
        window_start = 0
        was_spread = False
        
        for i, s in enumerate(signals):
            if not s['valid']:
                continue
            
            concepts = s.get('concepts', {})
            is_spread = concepts.get('legs_spreading', False)
            is_closed = concepts.get('legs_closing', False)
            
            if is_closed and not in_window:
                in_window = True
                window_start = i
                was_spread = False
            
            if is_spread and in_window:
                was_spread = True
            
            if is_closed and was_spread and in_window and i - window_start > 3:
                windows.append({
                    'start': window_start,
                    'end': i,
                    'airborne_frame': None,
                    'has_airborne': False,
                })
                in_window = False
                was_spread = False
    
    return windows

def classify_failure(window, signals, movement, tracker_phases=None):
    """Classify why a rep was missed based on signal analysis."""
    failures = []
    
    start = window['start']
    end = window['end']
    window_signals = [s for s in signals[start:end+1] if s['valid']]
    
    if not window_signals:
        return ['BAD_SOURCE_CLIP']
    
    # Check for airborne issues
    if movement in ('jump_squats', 'vertical_jumps', 'lunge_jumps'):
        airborne_frames = [s for s in window_signals if s.get('concepts', {}).get('airborne_candidate', False)]
        
        if not airborne_frames:
            # No airborne detected at all
            ankle_rises = [s.get('ankle_rise_ratio') for s in window_signals if s.get('ankle_rise_ratio') is not None]
            if ankle_rises:
                max_rise = max(ankle_rises)
                if max_rise < 0.10:
                    failures.append('AIRBORNE_SIGNAL_TOO_STRICT')
                elif max_rise < 0.18:
                    failures.append('AIRBORNE_SIGNAL_TOO_STRICT')
                else:
                    failures.append('AIRBORNE_FALSE_NEGATIVE')
            else:
                failures.append('ANKLE_CONFIDENCE_LOSS')
        else:
            # Airborne detected but maybe too brief
            if len(airborne_frames) < 2:
                failures.append('TEMPORAL_STABILITY_TOO_STRICT')
        
        # Check for camera translation
        cam_frames = [s for s in window_signals if s.get('concepts', {}).get('camera_translation_likely', False)]
        if len(cam_frames) > len(window_signals) * 0.3:
            failures.append('AIRBORNE_FALSE_POSITIVE_CAMERA_SWAY')
    
    # Check standing primitive
    standing_frames = [s for s in window_signals if s.get('concepts', {}).get('standing_like', False)]
    athletic_frames = [s for s in window_signals if s.get('concepts', {}).get('athletic_stance', False)]
    
    if not standing_frames and athletic_frames:
        failures.append('ATHLETIC_STANCE_NOT_ACCEPTED')
    elif not standing_frames and not athletic_frames:
        failures.append('STANDING_PRIMITIVE_TOO_STRICT')
    
    # Check squat depth
    squat_frames = [s for s in window_signals if s.get('hip_to_knee_ratio', 1) < 0.58]
    if movement in ('jump_squats', 'normal_squats', 'deep_squats') and not squat_frames:
        mid_frames = [s for s in window_signals if 0.58 < s.get('hip_to_knee_ratio', 1) < 0.70]
        if mid_frames:
            failures.append('SQUAT_DEPTH_SIGNAL_WEAK')
    
    # Check hip descent
    descending = [s for s in window_signals if s.get('concepts', {}).get('hips_descending', False)]
    if movement in ('jump_squats', 'normal_squats', 'deep_squats') and not descending:
        failures.append('HIP_DESCENT_SIGNAL_WEAK')
    
    # Check landing
    if movement in ('jump_squats', 'vertical_jumps', 'lunge_jumps'):
        landing_frames = [s for s in window_signals if s.get('concepts', {}).get('landing_candidate', False)]
        if not landing_frames and window.get('has_airborne'):
            failures.append('LANDING_SIGNAL_WEAK')
    
    # Check pose quality
    low_conf_frames = [s for s in window_signals if s.get('concepts', {}).get('ankle_confidence_loss', False)]
    if len(low_conf_frames) > len(window_signals) * 0.3:
        failures.append('ANKLE_CONFIDENCE_LOSS')
    
    outlier_frames = [s for s in window_signals if s.get('concepts', {}).get('pose_outlier', False)]
    if outlier_frames:
        failures.append('POSE_OUTLIER')
    
    # Check temporal stability
    if not failures:
        # If no specific failure found but rep still missed, likely temporal
        failures.append('TEMPORAL_STABILITY_TOO_STRICT')
    
    return failures

def analyze_fixture(filepath):
    """Analyze a single fixture file."""
    with open(filepath) as f:
        data = json.load(f)
    
    movement = data.get('movement', 'unknown')
    fixture_id = data.get('id', os.path.basename(filepath))
    expected_reps = data.get('expected', {}).get('reps', 0)
    frames = data.get('frames', [])
    camera_view = data.get('source', {}).get('cameraView', 'front')
    
    signals = extract_signals(frames)
    signals = classify_concepts(signals)
    windows = analyze_rep_windows(signals, movement)
    
    # Analyze each window for failures
    rep_analysis = []
    for i, window in enumerate(windows):
        failures = classify_failure(window, signals, movement)
        window_signals = [s for s in signals[window['start']:window['end']+1] if s['valid']]
        
        # Collect concept summary for this window
        concept_summary = defaultdict(int)
        for s in window_signals:
            for k, v in s.get('concepts', {}).items():
                if v:
                    concept_summary[k] += 1
        
        rep_analysis.append({
            'rep': i + 1,
            'start_frame': window['start'],
            'end_frame': window['end'],
            'failures': failures,
            'concept_summary': dict(concept_summary),
            'window_frames': len(window_signals),
        })
    
    # Camera motion analysis
    cam_motion_frames = sum(1 for s in signals if s.get('concepts', {}).get('camera_translation_likely', False))
    total_valid = sum(1 for s in signals if s['valid'])
    
    # Confidence analysis
    ankle_conf_avg = []
    knee_conf_avg = []
    hip_conf_avg = []
    for s in signals:
        c = s.get('confidences', {})
        if c.get('leftAnkle', 0) > 0 and c.get('rightAnkle', 0) > 0:
            ankle_conf_avg.append((c['leftAnkle'] + c['rightAnkle']) / 2)
        if c.get('leftKnee', 0) > 0 and c.get('rightKnee', 0) > 0:
            knee_conf_avg.append((c['leftKnee'] + c['rightKnee']) / 2)
        if c.get('leftHip', 0) > 0 and c.get('rightHip', 0) > 0:
            hip_conf_avg.append((c['leftHip'] + c['rightHip']) / 2)
    
    # Signal distributions
    hkr_values = [s['hip_to_knee_ratio'] for s in signals if s['valid'] and 'hip_to_knee_ratio' in s]
    airborne_rises = [s['ankle_rise_ratio'] for s in signals if s.get('ankle_rise_ratio') is not None]
    
    return {
        'id': fixture_id,
        'movement': movement,
        'expected_reps': expected_reps,
        'camera_view': camera_view,
        'total_frames': len(frames),
        'valid_frames': total_valid,
        'detected_rep_windows': len(windows),
        'rep_analysis': rep_analysis,
        'camera_motion': {
            'camera_translation_frames': cam_motion_frames,
            'camera_translation_pct': round(safe_div(cam_motion_frames, total_valid) * 100, 1) if total_valid else 0,
        },
        'confidence': {
            'ankle_avg': round(sum(ankle_conf_avg) / len(ankle_conf_avg), 4) if ankle_conf_avg else 0,
            'knee_avg': round(sum(knee_conf_avg) / len(knee_conf_avg), 4) if knee_conf_avg else 0,
            'hip_avg': round(sum(hip_conf_avg) / len(hip_conf_avg), 4) if hip_conf_avg else 0,
            'ankle_low_frames': sum(1 for c in ankle_conf_avg if c < 0.5),
            'knee_low_frames': sum(1 for c in knee_conf_avg if c < 0.5),
        },
        'signal_distributions': {
            'hkr_min': round(min(hkr_values), 4) if hkr_values else 0,
            'hkr_max': round(max(hkr_values), 4) if hkr_values else 0,
            'hkr_mean': round(sum(hkr_values) / len(hkr_values), 4) if hkr_values else 0,
            'airborne_rise_max': round(max(airborne_rises), 4) if airborne_rises else 0,
            'airborne_rise_mean': round(sum(airborne_rises) / len(airborne_rises), 4) if airborne_rises else 0,
        },
        'failure_counts': None,  # filled in by caller
    }

def main():
    import sys
    
    real_dir = 'test/motion_qa/fixtures/real'
    if not os.path.isdir(real_dir):
        print(f"ERROR: {real_dir} not found", file=sys.stderr)
        sys.exit(1)
    
    results = []
    failure_taxonomy = defaultdict(int)
    
    files = sorted([f for f in os.listdir(real_dir) 
                    if f.endswith('.json') and not f.endswith('import_log.json')])
    
    for fname in files:
        filepath = os.path.join(real_dir, fname)
        try:
            result = analyze_fixture(filepath)
            
            # Aggregate failures
            for rep in result['rep_analysis']:
                for f in rep['failures']:
                    failure_taxonomy[f] += 1
            
            results.append(result)
            print(f"  {result['id']}: {result['movement']} - {result['detected_rep_windows']} rep windows, {result['valid_frames']}/{result['total_frames']} valid frames")
        except Exception as e:
            print(f"  ERROR analyzing {fname}: {e}", file=sys.stderr)
    
    # Build failure taxonomy
    taxonomy_list = sorted(failure_taxonomy.items(), key=lambda x: -x[1])
    
    # Build summary by movement
    by_movement = defaultdict(list)
    for r in results:
        by_movement[r['movement']].append(r)
    
    print("\n" + "=" * 70)
    print("BODY-MOTION DIAGNOSTIC ANALYSIS SUMMARY")
    print("=" * 70)
    
    print(f"\nTotal fixtures analyzed: {len(results)}")
    print(f"\nBy movement:")
    for mv, clips in sorted(by_movement.items()):
        print(f"  {mv}: {len(clips)} clips, {sum(c['detected_rep_windows'] for c in clips)} rep windows detected")
    
    print(f"\nFailure taxonomy (across all rep windows):")
    for failure, count in taxonomy_list:
        print(f"  {failure}: {count}")
    
    print(f"\nCamera motion:")
    for r in results:
        cm = r['camera_motion']
        if cm['camera_translation_pct'] > 10:
            print(f"  {r['id']}: {cm['camera_translation_pct']}% camera translation frames")
    
    print(f"\nConfidence issues:")
    for r in results:
        c = r['confidence']
        if c['ankle_low_frames'] > 10 or c['ankle_avg'] < 0.5:
            print(f"  {r['id']}: ankle_avg={c['ankle_avg']}, low_frames={c['ankle_low_frames']}")
    
    # Write full JSON report
    report = {
        'fixtures': results,
        'failure_taxonomy': dict(taxonomy_list),
        'summary': {
            'total_fixtures': len(results),
            'by_movement': {mv: len(clips) for mv, clips in by_movement.items()},
        },
    }
    
    report_path = 'test/motion_qa/body_motion_diagnostics.json'
    with open(report_path, 'w') as f:
        json.dump(report, f, indent=2)
    print(f"\nFull report: {report_path}")

if __name__ == '__main__':
    main()
