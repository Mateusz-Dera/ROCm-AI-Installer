#!/usr/bin/env python3

import argparse
import json

import librosa
import numpy as np


def analyse(path, expected_bpm):
    y, sr = librosa.load(path, sr=None, mono=True)
    duration = len(y) / sr if sr else 0.0
    out = {"seconds": round(duration, 2)}
    if duration <= 0:
        return {**out, "error": "empty audio"}

    rms_frames = librosa.feature.rms(y=y)[0]
    out["rms"] = round(float(np.sqrt((y ** 2).mean())), 5)
    out["rms_variation"] = round(float(rms_frames.std() / (rms_frames.mean() + 1e-9)), 3)
    out["clipped_fraction"] = round(float((np.abs(y) > 0.999).mean()), 5)

    flatness = librosa.feature.spectral_flatness(y=y)[0]
    out["spectral_flatness"] = round(float(np.median(flatness)), 4)

    harmonic, percussive = librosa.effects.hpss(y)
    h_energy = float((harmonic ** 2).sum())
    p_energy = float((percussive ** 2).sum())
    total = h_energy + p_energy + 1e-12
    out["harmonic_fraction"] = round(h_energy / total, 3)
    out["percussive_fraction"] = round(p_energy / total, 3)

    tempo, beats = librosa.beat.beat_track(y=y, sr=sr, units="time")
    tempo = float(np.atleast_1d(tempo)[0])
    out["tempo"] = round(tempo, 1)
    if len(beats) > 3:
        intervals = np.diff(beats)
        out["beat_count"] = int(len(beats))
        out["beat_interval_cv"] = round(float(intervals.std() / (intervals.mean() + 1e-9)), 3)
    else:
        out["beat_count"] = int(len(beats))
        out["beat_interval_cv"] = 1.0

    if expected_bpm:
        ratios = [tempo / expected_bpm * f for f in (1.0, 2.0, 0.5)]
        out["tempo_error"] = round(min(abs(r - 1.0) for r in ratios), 3)

    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("path")
    ap.add_argument("--bpm", type=float, default=0)
    args = ap.parse_args()
    print(json.dumps(analyse(args.path, args.bpm)))


if __name__ == "__main__":
    main()
