#!/usr/bin/env python3
"""
Synthetic vs Real Distribution Gap Analysis

Compares key signal distributions between synthetic fixtures and real video
fixtures to identify where synthetic data is unrealistic.

Outputs a report showing where the gap is and what synthetic generation
should improve.
"""

import json
import os
import math

MIN_LIKELIHOOD = 0.35

def get_lm(frame_data, name):
    lms = frame_data.get('landmarks', {})
    lm = lms.get(name)
    if lm is None or len(lm) < 4 or lm[3] < MIN_LIKELIHOOD:
        return None
    return lm

def clamp(v, lo, hi):
    return max(lo, min(hi, v))

def safe_div(a, b):
    if abs(b) < 1e-6:
        return 0.0
    return a / b

def extract_distribution(filepath):
    """Extract signal distributions from a fixture file."""
    with open(filepath) as f:
        data = json.load(f)
    
    movement = data.get('movement', 'unknown')
    fixture_id = data.get('id', os.path.basename(filepath))
    frames = data.get('frames', [])
    is_real = 'real' in filepath or data.get('source', {}).get('qualityTier') == 'real_video'
    
    hkr_values = []
    airborne_durations = []  # consecutive frames where ankle rise > threshold
    ankle_confidences = []
    knee_confidences = []
    hip_confidences = []
    torso_heights = []
    frame_counts = []
    
    # Track airborne runs
    airborne_run = 0
    max_airborne_run = 0
    
    # Baseline ankle Y
    baseline_ankle_y = None
    
    for i, frame in enumerate(frames):
        ls = get_lm(frame, 'leftShoulder')
        rs = get_lm(frame, 'rightShoulder')
        lh = get_lm(frame, 'leftHip')
        rh = get_lm(frame, 'rightHip')
        lk = get_lm(frame, 'leftKnee')
        rk = get_lm(frame, 'rightKnee')
        la = get_lm(frame, 'leftAnkle')
        ra = get_lm(frame, 'rightAnkle')
        
        # Confidence
        for name in ['leftAnkle', 'rightAnkle']:
            lm = frame.get('landmarks', {}).get(name)
            if lm and len(lm) >= 4:
                ankle_confidences.append(lm[3])
        for name in ['leftKnee', 'rightKnee']:
            lm = frame.get('landmarks', {}).get(name)
            if lm and len(lm) >= 4:
                knee_confidences.append(lm[3])
        for name in ['leftHip', 'rightHip']:
            lm = frame.get('landmarks', {}).get(name)
            if lm and len(lm) >= 4:
                hip_confidences.append(lm[3])
        
        if not all([ls, rs, lh, rh, lk, rk]):
            airborne_run = 0
            continue
        
        shoulder_y = (ls[1] + rs[1]) / 2
        hip_y = (lh[1] + rh[1]) / 2
        knee_y = (lk[1] + rk[1]) / 2
        torso_h = abs(hip_y - shoulder_y)
        torso_heights.append(torso_h)
        
        hkr = clamp(safe_div(knee_y - hip_y, torso_h), -2.0, 3.0)
        hkr_values.append(hkr)
        
        if la and ra:
            ankle_avg_y = (la[1] + ra[1]) / 2
            if baseline_ankle_y is None:
                baseline_ankle_y = ankle_avg_y
            
            ankle_rise = baseline_ankle_y - ankle_avg_y
            rise_ratio = safe_div(ankle_rise, clamp(torso_h, 0.12, 0.6))
            
            if rise_ratio > 0.18:
                airborne_run += 1
                max_airborne_run = max(max_airborne_run, airborne_run)
            else:
                if airborne_run > 0:
                    airborne_durations.append(airborne_run)
                airborne_run = 0
        else:
            if airborne_run > 0:
                airborne_durations.append(airborne_run)
            airborne_run = 0
    
    if airborne_run > 0:
        airborne_durations.append(airborne_run)
    
    def stats(vals):
        if not vals:
            return {'min': 0, 'max': 0, 'mean': 0, 'median': 0, 'count': 0}
        vals_sorted = sorted(vals)
        n = len(vals)
        return {
            'min': round(min(vals), 4),
            'max': round(max(vals), 4),
            'mean': round(sum(vals) / n, 4),
            'median': round(vals_sorted[n // 2], 4),
            'count': n,
        }
    
    return {
        'id': fixture_id,
        'movement': movement,
        'is_real': is_real,
        'total_frames': len(frames),
        'hkr': stats(hkr_values),
        'airborne_duration_frames': stats(airborne_durations),
        'max_airborne_run': max_airborne_run,
        'ankle_confidence': stats(ankle_confidences),
        'knee_confidence': stats(knee_confidences),
        'hip_confidence': stats(hip_confidences),
        'torso_height': stats(torso_heights),
    }

def main():
    # Analyze synthetic fixtures
    synth_dir = 'test/motion_qa/fixtures'
    real_dir = 'test/motion_qa/fixtures/real'
    
    synth_results = []
    real_results = []
    
    # Synthetic: load from manifest
    manifest_path = os.path.join(synth_dir, 'manifest.json')
    if os.path.exists(manifest_path):
        with open(manifest_path) as f:
            manifest = json.load(f)
        for entry in manifest.get('fixtures', []):
            fid = entry['id']
            # Only analyze clean (non-augmented) jump squat fixtures
            if '__' in fid:
                continue
            fpath = os.path.join(synth_dir, f'{fid}.json')
            if os.path.exists(fpath):
                synth_results.append(extract_distribution(fpath))
    
    # Real: load all
    if os.path.isdir(real_dir):
        for fname in sorted(os.listdir(real_dir)):
            if not fname.endswith('.json') or 'import_log' in fname:
                continue
            fpath = os.path.join(real_dir, fname)
            real_results.append(extract_distribution(fpath))
    
    # Compare distributions for jump squats
    print("=" * 70)
    print("SYNTHETIC vs REAL DISTRIBUTION GAP ANALYSIS")
    print("=" * 70)
    
    movements_to_compare = ['jump_squats', 'normal_squats', 'jumping_jacks']
    
    for mv in movements_to_compare:
        synth_mv = [r for r in synth_results if r['movement'] == mv]
        real_mv = [r for r in real_results if r['movement'] == mv]
        
        if not synth_mv and not real_mv:
            continue
        
        print(f"\n--- {mv.upper()} ---")
        print(f"  Synthetic clips: {len(synth_mv)}")
        print(f"  Real clips: {len(real_mv)}")
        
        if synth_mv:
            print(f"\n  SYNTHETIC hipToKneeRatio:")
            s = synth_mv[0]['hkr']
            print(f"    min={s['min']}, max={s['max']}, mean={s['mean']}, median={s['median']}")
            
            print(f"  SYNTHETIC airborne duration (frames):")
            for r in synth_mv:
                print(f"    {r['id']}: max_run={r['max_airborne_run']}, durations={r['airborne_duration_frames']}")
            
            print(f"  SYNTHETIC ankle confidence:")
            s = synth_mv[0]['ankle_confidence']
            print(f"    min={s['min']}, max={s['max']}, mean={s['mean']}")
        
        if real_mv:
            print(f"\n  REAL hipToKneeRatio:")
            for r in real_mv:
                s = r['hkr']
                print(f"    {r['id']}: min={s['min']}, max={s['max']}, mean={s['mean']}")
            
            print(f"\n  REAL airborne duration (frames):")
            for r in real_mv:
                print(f"    {r['id']}: max_run={r['max_airborne_run']}, durations={r['airborne_duration_frames']}")
            
            print(f"\n  REAL ankle confidence:")
            for r in real_mv:
                s = r['ankle_confidence']
                print(f"    {r['id']}: min={s['min']}, max={s['max']}, mean={s['mean']}")
    
    # Gap summary
    print(f"\n{'=' * 70}")
    print("KEY GAPS IDENTIFIED:")
    print("=" * 70)
    
    # Compare jump squat specifically
    synth_jsq = [r for r in synth_results if r['movement'] == 'jump_squats']
    real_jsq = [r for r in real_results if r['movement'] == 'jump_squats']
    
    if synth_jsq and real_jsq:
        synth_airborne_max = max(r['max_airborne_run'] for r in synth_jsq)
        real_airborne_maxes = [r['max_airborne_run'] for r in real_jsq]
        real_airborne_avg = sum(real_airborne_maxes) / len(real_airborne_maxes) if real_airborne_maxes else 0
        
        print(f"\n  1. AIRBORNE DURATION:")
        print(f"     Synthetic max airborne run: {synth_airborne_max} frames")
        print(f"     Real max airborne runs: {real_airborne_maxes}")
        print(f"     Real avg max airborne: {real_airborne_avg:.1f} frames")
        if real_airborne_avg < synth_airborne_max * 0.5:
            print(f"     GAP: Real airborne is {real_airborne_avg/synth_airborne_max*100:.0f}% of synthetic — too short")
        
        synth_ankle = synth_jsq[0]['ankle_confidence']['mean']
        real_ankles = [r['ankle_confidence']['mean'] for r in real_jsq]
        real_ankle_avg = sum(real_ankles) / len(real_ankles) if real_ankles else 0
        
        print(f"\n  2. ANKLE CONFIDENCE:")
        print(f"     Synthetic ankle conf: {synth_ankle}")
        print(f"     Real ankle conf: {real_ankles}")
        print(f"     Real avg: {real_ankle_avg:.4f}")
        if real_ankle_avg < synth_ankle * 0.8:
            print(f"     GAP: Real ankle confidence is {real_ankle_avg/synth_ankle*100:.0f}% of synthetic — lower")
        
        synth_hkr_range = synth_jsq[0]['hkr']['max'] - synth_jsq[0]['hkr']['min']
        real_hkr_ranges = [r['hkr']['max'] - r['hkr']['min'] for r in real_jsq]
        real_hkr_avg_range = sum(real_hkr_ranges) / len(real_hkr_ranges) if real_hkr_ranges else 0
        
        print(f"\n  3. hipToKneeRatio RANGE:")
        print(f"     Synthetic range: {synth_hkr_range:.4f} ({synth_jsq[0]['hkr']['min']:.4f} to {synth_jsq[0]['hkr']['max']:.4f})")
        print(f"     Real ranges: {[round(r, 4) for r in real_hkr_ranges]}")
        print(f"     Real avg range: {real_hkr_avg_range:.4f}")
    
    # Write JSON report
    report = {
        'synthetic': synth_results,
        'real': real_results,
    }
    report_path = 'test/motion_qa/synthetic_real_gap.json'
    with open(report_path, 'w') as f:
        json.dump(report, f, indent=2)
    print(f"\nFull report: {report_path}")

if __name__ == '__main__':
    main()
