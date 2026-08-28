#!/usr/bin/env python3
import argparse
import json
import sys

import numpy as np


def load_image(path):
    from PIL import Image
    with Image.open(path) as im:
        return np.asarray(im.convert("RGB"), dtype=np.float32)


def load_video(path):
    import av
    frames = []
    with av.open(path) as container:
        stream = container.streams.video[0]
        fps = float(stream.average_rate) if stream.average_rate else 0.0
        for frame in container.decode(stream):
            frames.append(frame.to_ndarray(format="rgb24").astype(np.float32))
    return np.stack(frames), fps


def fingerprint(rgb):
    from PIL import Image
    small = Image.fromarray(rgb.astype(np.uint8)).convert("L").resize((16, 16))
    a = np.asarray(small, dtype=np.float32)
    return (a > a.mean()).flatten()


def image_stats(rgb):
    return {
        "width": int(rgb.shape[1]),
        "height": int(rgb.shape[0]),
        "std": round(float(rgb.std()), 4),
        "mean": round(float(rgb.mean()), 4),
        "unique_ratio": round(float(len(np.unique(rgb.astype(np.uint8))) / 256.0), 4),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("path")
    ap.add_argument("--video", action="store_true")
    ap.add_argument("--compare")
    args = ap.parse_args()

    if args.video:
        frames, fps = load_video(args.path)
        out = image_stats(frames[0])
        out["frames"] = int(frames.shape[0])
        out["fps"] = round(fps, 2)
        diffs = np.abs(np.diff(frames, axis=0)).mean(axis=(1, 2, 3))
        out["motion_mean"] = round(float(diffs.mean()), 4)
        out["motion_min"] = round(float(diffs.min()), 4)
        out["static_frames"] = int((diffs < 0.5).sum())
    else:
        rgb = load_image(args.path)
        out = image_stats(rgb)
        if args.compare:
            other = load_image(args.compare)
            a, b = fingerprint(rgb), fingerprint(other)
            out["hamming"] = int(np.count_nonzero(a != b))
            if rgb.shape == other.shape:
                out["pixel_diff"] = round(float(np.abs(rgb - other).mean()), 4)

    json.dump(out, sys.stdout)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
