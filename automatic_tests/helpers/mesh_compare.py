#!/usr/bin/env python3

import argparse
import json

import numpy as np
import trimesh
from PIL import Image, ImageDraw

CANVAS = 256


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


def mesh_mask(vertices, faces, angle):
    cos, sin = np.cos(angle), np.sin(angle)
    x = vertices[:, 0] * cos + vertices[:, 2] * sin
    y = vertices[:, 1]
    pts = np.stack([x, y], axis=1)

    lo, hi = pts.min(axis=0), pts.max(axis=0)
    span = (hi - lo).max()
    if span <= 0:
        return np.zeros((CANVAS, CANVAS), dtype=bool)
    pts = (pts - (lo + hi) / 2) / span * (CANVAS - 8) + CANVAS / 2

    img = Image.new("1", (CANVAS, CANVAS), 0)
    draw = ImageDraw.Draw(img)
    for tri in faces:
        a, b, c = pts[tri[0]], pts[tri[1]], pts[tri[2]]
        draw.polygon([(a[0], CANVAS - a[1]), (b[0], CANVAS - b[1]), (c[0], CANVAS - c[1])], fill=1)
    return np.asarray(img, dtype=bool)


def normalise(mask):
    rows, cols = np.any(mask, axis=1), np.any(mask, axis=0)
    if not rows.any() or not cols.any():
        return np.zeros((CANVAS, CANVAS), dtype=bool)
    r0, r1 = np.where(rows)[0][[0, -1]]
    c0, c1 = np.where(cols)[0][[0, -1]]
    crop = mask[r0:r1 + 1, c0:c1 + 1]

    height, width = crop.shape
    scale = (CANVAS - 4) / max(height, width)
    new_size = (max(1, int(round(width * scale))), max(1, int(round(height * scale))))
    resized = Image.fromarray(crop.astype(np.uint8) * 255).resize(new_size, Image.NEAREST)

    canvas = Image.new("L", (CANVAS, CANVAS), 0)
    canvas.paste(resized, ((CANVAS - new_size[0]) // 2, (CANVAS - new_size[1]) // 2))
    return np.asarray(canvas) > 127


def iou(a, b):
    union = np.logical_or(a, b).sum()
    return float(np.logical_and(a, b).sum() / union) if union else 0.0


def hu(mask):
    ys, xs = np.nonzero(mask)
    if len(xs) < 3:
        return [0.0] * 7
    x, y = xs - xs.mean(), ys - ys.mean()
    def mu(p, q):
        return (x ** p * y ** q).sum()
    m00 = float(len(xs))
    n = {(p, q): mu(p, q) / m00 ** (1 + (p + q) / 2) for p, q in
         [(2, 0), (0, 2), (1, 1), (3, 0), (0, 3), (2, 1), (1, 2)]}
    h = [
        n[(2, 0)] + n[(0, 2)],
        (n[(2, 0)] - n[(0, 2)]) ** 2 + 4 * n[(1, 1)] ** 2,
        (n[(3, 0)] - 3 * n[(1, 2)]) ** 2 + (3 * n[(2, 1)] - n[(0, 3)]) ** 2,
        (n[(3, 0)] + n[(1, 2)]) ** 2 + (n[(2, 1)] + n[(0, 3)]) ** 2,
    ]
    return [float(np.sign(v) * np.log10(abs(v) + 1e-30)) for v in h]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mesh")
    ap.add_argument("image")
    ap.add_argument("--views", type=int, default=16)
    args = ap.parse_args()

    loaded = trimesh.load(args.mesh, force="mesh")
    vertices = np.asarray(loaded.vertices, dtype=np.float64)
    faces = np.asarray(getattr(loaded, "faces", []), dtype=np.int64)

    out = {
        "vertices": int(len(vertices)),
        "faces": int(len(faces)),
    }
    if not len(vertices):
        return print(json.dumps({**out, "error": "geometry has no vertices"}))

    target = normalise(image_mask(args.image))
    best, best_angle = 0.0, 0.0
    for i in range(args.views):
        angle = 2 * np.pi * i / args.views
        score = iou(normalise(mesh_mask(vertices, faces, angle)), target)
        if score > best:
            best, best_angle = score, angle

    rendered = normalise(mesh_mask(vertices, faces, best_angle))
    hu_mesh, hu_image = hu(rendered), hu(target)
    out["silhouette_iou"] = round(best, 3)
    out["hu_distance"] = round(float(np.abs(np.array(hu_mesh) - np.array(hu_image)).mean()), 3)
    print(json.dumps(out))


if __name__ == "__main__":
    main()
