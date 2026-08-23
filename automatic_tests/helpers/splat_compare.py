#!/usr/bin/env python3

import argparse
import json

import numpy as np
import trimesh
from PIL import Image

SH_C0 = 0.28209479177387814
BINS = 4


def image_mask(path):
    img = Image.open(path).convert("RGBA")
    arr = np.asarray(img).astype(np.float32)
    alpha = arr[..., 3]
    if alpha.min() < 250:
        return alpha > 128
    rgb = arr[..., :3]
    corners = np.stack([rgb[0, 0], rgb[0, -1], rgb[-1, 0], rgb[-1, -1]])
    background = corners.mean(axis=0)
    return np.linalg.norm(rgb - background, axis=-1) > 40


def histogram(rgb, weights=None):
    index = np.clip((rgb * BINS).astype(int), 0, BINS - 1)
    flat = index[:, 0] * BINS * BINS + index[:, 1] * BINS + index[:, 2]
    counts = np.bincount(flat, weights=weights, minlength=BINS ** 3).astype(np.float64)
    return counts / max(counts.sum(), 1e-9)


def image_histogram(path):
    arr = np.asarray(Image.open(path).convert("RGBA")).astype(np.float32)
    return histogram(arr[..., :3][image_mask(path)] / 255.0)


def splat_histogram(raw):
    dc = np.stack([raw["f_dc_0"], raw["f_dc_1"], raw["f_dc_2"]], axis=1).astype(np.float64)
    rgb = np.clip(0.5 + SH_C0 * dc, 0.0, 1.0)
    opacity = 1.0 / (1.0 + np.exp(-raw["opacity"].astype(np.float64)))
    return histogram(rgb, weights=opacity), opacity


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("splat")
    parser.add_argument("image")
    args = parser.parse_args()

    loaded = trimesh.load(args.splat)
    points = np.asarray(loaded.vertices, dtype=np.float64)

    out = {"gaussians": int(len(points))}
    if len(points) < 3:
        return print(json.dumps({**out, "error": "the splat has no gaussians"}))

    raw = loaded.metadata.get("_ply_raw", {}).get("vertex", {}).get("data")
    if raw is None or "f_dc_0" not in raw.dtype.names:
        return print(json.dumps({**out, "error": "the PLY carries no gaussian colour"}))

    centred = points - points.mean(axis=0)
    spread = np.linalg.svd(centred, compute_uv=False) / np.sqrt(len(points))
    out["extent_ratio"] = round(float(spread[2] / spread[0]), 3)

    splat_hist, opacity = splat_histogram(raw)
    out["mean_opacity"] = round(float(opacity.mean()), 3)
    out["colour_match"] = round(float(np.minimum(splat_hist, image_histogram(args.image)).sum()), 3)
    print(json.dumps(out))


main()
