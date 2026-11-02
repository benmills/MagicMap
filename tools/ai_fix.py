#!/usr/bin/env python3
"""An MVP: repaint a broken part of the map with OpenAI's image edits, and see whether we like it.

Give it a range of the map in tile units (the demo's URL shows them: x is col, y is row); the broken ground in it is the
map review's accepted issues and any flat ground found there, or --whole-box. It writes demo/aifix/<name>/ (gitignored: Blizzard's art is in it):

  window.png      the range and the good ground round it, at the game's 512 px a tile
  broken.png      what the model is to repaint (white)
  input/          what each recipe sends, as sent
  <recipe>_<i>.raw.png    the model's picture, as it came (kept: a rerun recomposites without a call; --force to call again)
  <recipe>_<i>.fixed.png  ...put back: only the broken ground is replaced, the rest is the game's own pixels, exactly
  sheet.png       the original and every result side by side
  results.json    each result's scores, tokens, cost, time

A mask only guides these models ("may not follow its exact shape with complete precision", OpenAI's guide) and they redraw the whole
picture, so the put-back is ours: the model's colours pulled to the real ones round the hole, then laid in through a soft, wandering
edge. Scores, all from the put-back:
  drift   how far the model strayed from the good ground it was asked to keep (0-255, lower is better)
  edge    how busy the new edge is against the ground round it (about 1 is invisible)
  detail  the new ground's texture against the ground round it (about 1 matches; well under 1 is still flat)

The key: OPENAI_API_KEY, or a line of it in the repo's .env (gitignored).

  cd tools; ../.venv/bin/python ai_fix.py local "/Applications/World of Warcraft" wow_classic_beta --map 0 --box 38.3,23.8,43.8,27.1 --dry-run
"""
from __future__ import annotations

import argparse
import base64
import io
import json
import os
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import maplint
from mmtools.mapgrid import blp_rgba, components, grow, places
from mmtools.sources import add_source_args, source_from_args

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TILE = 512            # the game's px a tile
CHUNK = TILE // 16
URL = "https://api.openai.com/v1/images/edits"
SHEET_W = 900         # px a picture on the sheet
TOKENS = (8e-6, 30e-6)  # $ an image input, output token (gpt-image-2.5's)
# The API's limits on a size. Over MAX_PIXELS is "experimental", so asked for only by --max-pixels.
EDGE, MIN_PIXELS, LIMIT_PIXELS, MAX_PIXELS, RATIO = 3840, 655_360, 8_294_400, 2560 * 1440, 3

FLAT = 3.5            # a chunk with less detail than this (px-to-px step, 0-255, across and down) is flat...
FLAT_LEAST = 6        # ...if this many chunks of it touch: a lone chunk can be a calm bit of real ground
DARK = 22             # ...and not this dark: open sea and the black of a hole aren't ours to paint

DESCRIBE = ("This is part of a top-down, hand-painted fantasy game minimap: terrain seen from directly above, with painted relief, "
            "dark shading and fine texture.")
CHANGE = ("Parts of it were never finished: flat, single-colour blocks with straight, stepped edges, and squares of mismatched art. "
          "{where} Change only those parts: paint them as the finished terrain that belongs there, continuing the ground around "
          "them across the gap, so that no block, straight edge or join can be seen.")
PRESERVE = ("Keep everything else exactly as it is: the position, shape, scale and colour of every feature, the framing and the "
            "lighting. Do not move, redraw, sharpen or restyle the finished terrain.")
EXCLUDE = ("Do not add text, labels, icons, roads, paths, bridges, buildings, ruins, camps, grids or borders, and no new landmarks: "
           "only plain natural ground, of the kinds already in the picture.")
INTEGRATE = ("Match the surrounding terrain's texture scale, brush detail, relief, shading direction, colour and saturation, so the "
             "new ground reads as painted by the same hand at the same zoom.")
# What the flat block should become, for the prompts that say. The first image's own colours are a guide to what belongs there.
KEEP_GROUND = ("Treat each block's colour as the truth about that ground: a brown block is low, bare, muddy earth and stays brown earth; "
               "paint it with the fine painted relief, cracks, damp patches and soft colour variation of finished terrain. Let the "
               "neighbouring terrain's edge break up and spill a little way in, irregularly. Keep it quiet and low: no rocks, cliffs, "
               "hills or dark masses in the middle of a block.")
GROW_IN = ("Work inward from each edge: extend exactly the terrain that touches that edge, and where two kinds of terrain meet let them "
           "mix in a natural, irregular transition. Every kind of ground you paint must already touch the area. Do not start any new "
           "rocky mass, ridge, cliff or feature.")
PLAIN = "This map has unfinished areas: flat colour blocks with hard edges. Fix them so that it looks like a seamless finished map. Leave the rest as it is."
BLEND = ("Work inward from each edge, extending exactly the terrain that touches that edge, its edge breaking up irregularly, and mix the kinds "
         "of ground where they meet. Where a block is brown, let bare earth show through as low damp patches among them; keep the middle of "
         "an area quiet. Paint at the very same fine scale and crisp detail as the terrain beside it. No rocks or cliffs that don't "
         "already touch the area, no black pools or water, no dark holes, no trails.")
REFINE = ("The masked area has been painted in as a draft, and is too soft and too smooth beside the crisp terrain around it. Keep the draft's "
          "composition exactly: every patch of ground, rock and earth stays where it is, the same shape and colour. Change only its finish: repaint "
          "it at the very same fine scale and sharp, crisp, slightly dithered pixel detail as the original terrain around it, with the same "
          "hard small shadows. Add no new features.")
PROMPTS = {"full": [DESCRIBE, CHANGE, PRESERVE, EXCLUDE, INTEGRATE],
           "ground": [DESCRIBE, CHANGE, KEEP_GROUND, PRESERVE, EXCLUDE, INTEGRATE],
           "grow": [DESCRIBE, CHANGE, GROW_IN, PRESERVE, EXCLUDE, INTEGRATE],
           "blend": [DESCRIBE, CHANGE, BLEND, PRESERVE, EXCLUDE, INTEGRATE],
           "refine": [DESCRIBE, REFINE, PRESERVE, EXCLUDE],
           "plain": [PLAIN]}
S, F = "gpt-image-2.5-sunburst", "gpt-image-2.5-flare"
RECIPES = {  # what we're comparing: model; how we point at the broken ground; references; the prompt
    "mask": dict(model=S, point="mask", refs="none", prompt="full"),
    "refs": dict(model=S, point="mask", refs="sheet", prompt="full"),
    "markup": dict(model=S, point="markup", refs="none", prompt="full"),
    "flare": dict(model=F, point="mask", refs="none", prompt="full"),
    "flare-refs": dict(model=F, point="mask", refs="sheet", prompt="full"),
    "no-mask": dict(model=S, point="words", refs="none", prompt="full"),
    "plain": dict(model=S, point="words", refs="none", prompt="plain"),
    "plain-mask": dict(model=S, point="mask", refs="none", prompt="plain"),
    "ground": dict(model=S, point="mask", refs="none", prompt="ground"),
    "grow": dict(model=S, point="mask", refs="none", prompt="grow"),
    "ground-nomask": dict(model=S, point="words", refs="none", prompt="ground"),
    "ground-wide": dict(model=S, point="mask", refs="wide", prompt="ground"),
    "ground-sheet": dict(model=S, point="mask", refs="sheet", prompt="ground"),
    "ground-near": dict(model=S, point="mask", refs="near", prompt="ground"),
    "ground-many": dict(model=S, point="mask", refs="many", prompt="ground"),
    "blend": dict(model=S, point="mask", refs="none", prompt="blend"),
    "blend-wide": dict(model=S, point="mask", refs="wide", prompt="blend"),
    "blend-sheet": dict(model=S, point="mask", refs="sheet", prompt="blend"),
    "refine": dict(model=S, point="mask", refs="none", prompt="refine"),
    "grow-near": dict(model=S, point="mask", refs="near", prompt="grow"),
}
REFS_SAID = {
    "wide": "Image 2 is a wider view of the country around image 1, for what kind of ground belongs where: do not copy its framing. ",
    "sheet": "Image 2 is a wider view of the country around image 1, for what kind of ground belongs where: do not copy its framing. "
             "Image 3 is four squares of finished terrain from nearby, at the same zoom: match their texture and brushwork exactly. ",
    "near": "Images 2 and up are squares of finished terrain from right beside the area, at the same zoom, chosen for their colour: match "
            "their texture, scale and brushwork exactly, but do not copy their features. ",
    "many": "Image 2 is a wider view of the country around image 1, for what kind of ground belongs where: do not copy its framing. Images 3 and "
            "up are squares of finished terrain from right beside the area, at the same zoom: match their texture, scale and brushwork "
            "exactly, but do not copy their features. ",
}


def window_of(box, context: float) -> tuple[int, int, int, int]:
    """The range and context round it, in chunks (c0, r0, c1, r1), inside the map, the shape and size the API takes."""
    c0, r0, c1, r1 = (int(round(v * 16)) for v in (box[0] - context, box[1] - context, box[2] + context, box[3] + context))
    while True:
        w, h = c1 - c0, r1 - r0
        short = (w < h and w * RATIO < h) or (h <= w and h * RATIO < w)
        if not short and w * h * CHUNK * CHUNK >= MIN_PIXELS:
            break
        if w < h or not short:
            c0, c1 = c0 - 1, c1 + 1
        if h <= w or not short:
            r0, r1 = r0 - 1, r1 + 1
    return max(0, c0), max(0, r0), min(1024, c1), min(1024, r1)


def api_size(w: int, h: int, max_pixels: int) -> tuple[int, int]:
    """The size to send a w x h picture at: never bigger than it is; multiples of 16."""
    s = min(1.0, EDGE / max(w, h), (min(max_pixels, LIMIT_PIXELS) / (w * h)) ** .5)
    return int(w * s) // 16 * 16, int(h * s) // 16 * 16


def smooth(a: np.ndarray, sigma: float) -> np.ndarray:
    """A float picture, blurred (worked small: the sigmas here are tens of px)."""
    f = max(1, int(sigma / 4))
    h, w = a.shape
    s = np.asarray(Image.fromarray(a.astype(np.float32)).resize((max(1, w // f), max(1, h // f)), Image.BOX))
    r = max(1, int(3 * sigma / f))
    k = np.exp(-.5 * (np.arange(-r, r + 1) * f / sigma) ** 2)
    k /= k.sum()
    s = np.apply_along_axis(lambda v: np.convolve(np.pad(v, r, mode="edge"), k, "valid"), 0, s)
    s = np.apply_along_axis(lambda v: np.convolve(np.pad(v, r, mode="edge"), k, "valid"), 1, s)
    return np.asarray(Image.fromarray(s.astype(np.float32)).resize((w, h), Image.BILINEAR))


def edge_alpha(edit: np.ndarray, seed: int = 1) -> np.ndarray:
    """How much of the new picture shows, 0..1: 1 over the broken ground, fading through the chunk it was grown by, the fade
    wandering; exactly 0 outside what the model was asked to repaint."""
    rng = np.random.default_rng(seed)
    h, w = edit.shape
    noise = np.asarray(Image.fromarray(rng.random((h // CHUNK + 2, w // CHUNK + 2), np.float32)).resize((w, h), Image.BICUBIC))
    b = smooth(edit.astype(np.float32), CHUNK * .4)
    a = np.clip((b + (noise - .5) * .35 - .3) / .4, 0, 1)
    a = a * a * (3 - 2 * a)
    a[~edit] = 0
    return a


def put_back(window: np.ndarray, picture: np.ndarray, edit: np.ndarray, seed: int = 1) -> tuple[np.ndarray, dict]:
    """The model's picture (window's size) into the window through the broken ground; its scores."""
    good = ~edit
    a0, p0 = window.astype(np.float32), picture.astype(np.float32)
    ring = grow_px(edit, CHUNK * 2) & good  # what the hole is judged against
    drift = float(np.abs(a0[good] - p0[good]).mean()) if good.any() else 0.
    w = good.astype(np.float32)
    weight = smooth(w, CHUNK * 3)
    fixed_colour = np.empty_like(p0)
    for c in range(3):  # its colours pulled to the real ones round the hole, a slow correction: its own detail stays
        shift = smooth((a0[..., c] - p0[..., c]) * w, CHUNK * 3) / np.maximum(weight, 1e-3)
        shift[weight < 1e-3] = float((a0[..., c] - p0[..., c])[good].mean()) if good.any() else 0.
        fixed_colour[..., c] = p0[..., c] + np.clip(shift, -60, 60)
    alpha = edge_alpha(edit, seed)[..., None]
    out = np.where(alpha > 0, a0 * (1 - alpha) + np.clip(fixed_colour, 0, 255) * alpha + .5, a0).astype(np.uint8)
    out[good] = window[good]
    return out, {"drift": round(drift, 1), **judge(out, edit, alpha[..., 0], ring)}


def grow_px(t: np.ndarray, n: int) -> np.ndarray:
    return smooth(t.astype(np.float32), n / 2) > .02


def judge(img: np.ndarray, edit: np.ndarray, alpha: np.ndarray, ring: np.ndarray) -> dict:
    grey = img.astype(np.float32).mean(-1)
    grad = np.zeros_like(grey)
    grad[1:] += np.abs(grey[1:] - grey[:-1])
    grad[:, 1:] += np.abs(grey[:, 1:] - grey[:, :-1])
    band = (alpha > .02) & (alpha < .98)
    base = float(grad[ring].mean()) if ring.any() else 1.
    inside = (alpha >= .98)
    return {"edge": round(float(grad[band].mean()) / max(base, 1e-3), 2) if band.any() else None,
            "detail": round(float(grad[inside].mean()) / max(base, 1e-3), 2) if inside.any() else None}


def key() -> str | None:
    k = os.environ.get("OPENAI_API_KEY")
    path = os.path.join(ROOT, ".env")
    if not k and os.path.exists(path):
        for line in open(path):
            if line.startswith("OPENAI_API_KEY="):
                k = line.split("=", 1)[1].strip().strip("\"'")
    return k


def png(im: Image.Image) -> bytes:
    b = io.BytesIO()
    im.save(b, "PNG")
    return b.getvalue()


def data_url(b: bytes) -> str:
    return "data:image/png;base64," + base64.b64encode(b).decode()


def references(tile, tiles: dict, sea, win: tuple, broken: np.ndarray) -> dict:
    """The kinds of reference: "wide", the country round the window, small; "sheet", it and four squares of good ground nearest the hole on
    one picture; "near", squares of good ground beside the hole, closest to its surroundings' colour; "many", the wide view and more of those."""
    c0, r0, c1, r1 = win
    m = 16 * 4  # chunks of country beyond the window
    C0, R0, C1, R1 = max(0, c0 - m), max(0, r0 - m), min(1024, c1 + m), min(1024, r1 + m)
    wide, _ = compose(tile, tiles, sea, (C0, R0, C1, R1))
    side = 1024 / max(wide.shape[:2])
    view = Image.fromarray(wide).resize((max(16, int(wide.shape[1] * side)) // 16 * 16, max(16, int(wide.shape[0] * side)) // 16 * 16), Image.LANCZOS)
    S_ = 16  # a square's chunks (one tile)
    hole = broken[R0:R1, C0:C1]
    cy, cx = np.argwhere(hole).mean(0)
    around = grow(hole, 4) & ~grow(hole, 1)  # the ground that touches it, its colour
    tone = wide[around.repeat(CHUNK, 0).repeat(CHUNK, 1)].mean(0)
    cands = []
    for y in range(0, R1 - R0 - S_, 4):
        for x in range(0, C1 - C0 - S_, 4):
            if hole[y:y + S_, x:x + S_].any():
                continue
            p = wide[y * CHUNK:(y + S_) * CHUNK, x * CHUNK:(x + S_) * CHUNK]
            if p.mean() < 25 or (p.max(-1) < 12).mean() > .05 or flat_chunks(p).any():  # sea, a hole in the tiles, ground the review didn't get to
                continue
            cands.append((float(((y - cy) ** 2 + (x - cx) ** 2) ** .5), float(np.abs(p.mean((0, 1)) - tone).sum()), y, x))
    def pick(score, n):
        chosen = []
        for c in sorted(cands, key=score):
            if all(abs(c[2] - a) >= S_ or abs(c[3] - b) >= S_ for a, b in chosen):
                chosen.append((c[2], c[3]))
            if len(chosen) == n:
                break
        return [Image.fromarray(wide[y * CHUNK:(y + S_) * CHUNK, x * CHUNK:(x + S_) * CHUNK]) for y, x in chosen]
    sheet = Image.new("RGB", (TILE * 2, TILE * 2))
    for i, p in enumerate(pick(lambda c: c[0], 4)):
        sheet.paste(p, (i % 2 * TILE, i // 2 * TILE))
    alike = lambda c: c[1] + c[0] * 1.5  # the right colour, near
    return {"none": [], "wide": [view], "sheet": [view, sheet], "near": pick(alike, 4), "many": [view] + pick(alike, 8)}


def flat_chunks(img: np.ndarray) -> np.ndarray:
    """What the review didn't get to: the chunks of a chunk-aligned picture with no detail in them."""
    g = img.astype(np.float32).mean(-1)
    d = np.abs(g[1:, :-1] - g[:-1, :-1]) + np.abs(g[:-1, 1:] - g[:-1, :-1])
    d = np.pad(d, ((0, 1), (0, 1)), mode="edge")
    h, w = g.shape[0] // CHUNK, g.shape[1] // CHUNK
    detail = d.reshape(h, CHUNK, w, CHUNK).mean((1, 3))
    tone = g.reshape(h, CHUNK, w, CHUNK).mean((1, 3))
    t = (detail < FLAT) & (tone > DARK)
    for ys, xs in components(t):
        if t[ys, xs].sum() < FLAT_LEAST:
            t[ys, xs] = False
    return t


def compose(tile, tiles: dict, sea, win: tuple) -> tuple[np.ndarray, np.ndarray]:
    """The game's tiles over a rect of chunks, open sea left black; and which chunks have art."""
    c0, r0, c1, r1 = win
    img = np.zeros(((r1 - r0) * CHUNK, (c1 - c0) * CHUNK, 3), np.uint8)
    for col in range(c0 // 16, (c1 + 15) // 16):
        for row in range(r0 // 16, (r1 + 15) // 16):
            k = col * 64 + row
            if k not in tiles or k in sea:
                continue
            a = tile(k)
            x, y = col * TILE - c0 * CHUNK, row * TILE - r0 * CHUNK
            X0, Y0, X1, Y1 = max(x, 0), max(y, 0), min(x + TILE, img.shape[1]), min(y + TILE, img.shape[0])
            img[Y0:Y1, X0:X1] = a[Y0 - y:Y1 - y, X0 - x:X1 - x]
    return img, img.any(-1)


def prompt_of(recipe: dict, extra: str) -> str:
    where = {"mask": "They are the masked (transparent) area of the first image.",
             "markup": "They are the areas outlined in bright magenta on the first image; the outline itself must not appear in the result.",
             "words": "Look for them: they are obvious against the finished terrain."}[recipe["point"]]
    parts = [p.format(where=where) if p is CHANGE else p for p in PROMPTS[recipe["prompt"]]]
    if recipe["refs"] != "none":
        parts.append("Image 1 is the picture to edit. " + REFS_SAID[recipe["refs"]] + "Return only the edit of image 1, at its framing.")
    if extra:
        parts.append(extra)
    return "\n\n".join(parts)


def inputs(recipe: dict, name: str, small: Image.Image, edit_small: np.ndarray, refs: list, out: str) -> dict:
    """What the recipe sends: {images, mask?, markup?}, as bytes, saved as sent."""
    d = os.path.join(out, "input")
    os.makedirs(d, exist_ok=True)
    got = {"images": [png(small)] + [png(r) for r in refs[recipe["refs"]]]}
    if recipe["point"] == "mask":  # transparent: what may change
        rgba = np.full(edit_small.shape + (4,), 255, np.uint8)
        rgba[..., 3] = np.where(edit_small, 0, 255)
        got["mask"] = png(Image.fromarray(rgba))
    elif recipe["point"] == "markup":
        h, w = edit_small.shape
        e = Image.fromarray(edit_small.astype(np.uint8) * 255)
        wide = np.asarray(e.resize((w, h))) > 0
        rim = grow_px(wide, 6) & ~wide
        rgba = np.zeros((h, w, 4), np.uint8)
        rgba[rim] = (255, 0, 255, 255)
        got["markup"] = png(Image.fromarray(rgba))
    for k, v in got.items():
        for i, b in enumerate(v if isinstance(v, list) else [v]):
            with open(os.path.join(d, f"{name}.{k}{i}.png"), "wb") as f:
                f.write(b)
    return got


def call(api_key: str, recipe: dict, sent: dict, prompt: str, size: tuple, quality: str, n: int) -> tuple[list[bytes], dict]:
    body = {"model": recipe["model"], "prompt": prompt, "images": [{"image_url": data_url(b)} for b in sent["images"]], "n": n,
            "size": f"{size[0]}x{size[1]}", "quality": quality, "output_format": "png", "background": "opaque", "moderation": "low"}
    for k in ("mask", "markup"):
        if k in sent:
            body[k] = {"image_url": data_url(sent[k])}
    req = urllib.request.Request(URL, json.dumps(body).encode(), {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=900) as r:
            d = json.load(r)
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"{e.code}: {e.read().decode(errors='replace')[:1500]}") from None
    return [base64.b64decode(x["b64_json"]) for x in d["data"]], d.get("usage") or {}


def cost(usage: dict) -> float | None:
    if not usage:
        return None
    return round(usage.get("input_tokens", 0) * TOKENS[0] + usage.get("output_tokens", 0) * TOKENS[1], 3)


def write_sheet(path: str, shots: list[tuple[str, np.ndarray]]) -> None:
    n = len(shots)
    cols = min(n, 3)
    rows = (n + cols - 1) // cols
    h0, w0 = shots[0][1].shape[:2]
    H = int(h0 * SHEET_W / w0)
    sheet = Image.new("RGB", (cols * SHEET_W + (cols - 1) * 8, rows * (H + 26)), (24, 24, 24))
    d = ImageDraw.Draw(sheet)
    for i, (label, a) in enumerate(shots):
        x, y = i % cols * (SHEET_W + 8), i // cols * (H + 26)
        d.text((x + 4, y + 7), label, fill=(240, 240, 240))
        sheet.paste(Image.fromarray(a).resize((SHEET_W, H), Image.LANCZOS), (x, y + 26))
    sheet.save(path)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    add_source_args(ap)
    ap.add_argument("--map", type=int, required=True, help="the instance: 0 Eastern Kingdoms, 1 Kalimdor")
    ap.add_argument("--box", required=True, help="col0,row0,col1,row1, in tiles")
    ap.add_argument("--name", help="its folder under demo/aifix (default: from the box)")
    ap.add_argument("--whole-box", action="store_true", help="repaint the whole box, not the review's broken ground in it")
    ap.add_argument("--add", action="append", default=[], help="col0,row0,col1,row1: more to repaint, by hand; can repeat")
    ap.add_argument("--keep", action="append", default=[], help="col,row,radius (tiles): a real feature the repaint mustn't touch; can repeat")
    ap.add_argument("--review-only", action="store_true", help="only the review's broken ground, not the flat ground found in the box too")
    ap.add_argument("--grow", type=int, default=1, help="chunks the repaint reaches past the broken ground (default 1)")
    ap.add_argument("--context", type=float, default=.75, help="tiles of good ground round the box (default .75)")
    ap.add_argument("--recipes", default="refs", help=f"which, by comma (default refs): {', '.join(RECIPES)}")
    ap.add_argument("--quality", default="high", choices=("low", "medium", "high", "xhigh", "max", "auto"))
    ap.add_argument("-n", type=int, default=2, help="pictures a recipe")
    ap.add_argument("--max-pixels", type=int, default=MAX_PIXELS, help=f"of what's sent (default {MAX_PIXELS}; to {LIMIT_PIXELS}, experimental)")
    ap.add_argument("--prompt-extra", default="", help="more words for the prompt, for this place")
    ap.add_argument("--start", help="<name>:<recipe_i>: a second pass, from that earlier result (its repaint in the picture sent)")
    ap.add_argument("--parallel", type=int, default=4, help="calls at once")
    ap.add_argument("--dry-run", action="store_true", help="prepare and save what would be sent; no call")
    ap.add_argument("--force", action="store_true", help="call again, though there are pictures")
    ns = ap.parse_args()
    box = tuple(float(v) for v in ns.box.split(","))
    if len(box) != 4 or box[2] <= box[0] or box[3] <= box[1]:
        ap.error("--box is col0,row0,col1,row1")
    recipes = ns.recipes.split(",")
    for r in recipes:
        if r not in RECIPES:
            ap.error(f"no recipe {r}")
    src = source_from_args(ap, ns)
    data = maplint.Data(os.path.join(ROOT, "Data"))
    tiles, sea = data.tiles[ns.map], data.sea.get(ns.map, set())
    cache = {}

    def tile(k):
        if k not in cache:
            cache[k] = np.asarray(blp_rgba(src.read(tiles[k])).convert("RGB").resize((TILE, TILE), Image.LANCZOS))
        return cache[k]

    bc = tuple(int(round(v * 16)) for v in box)
    grid = np.zeros((1024, 1024), bool)
    if ns.whole_box:
        grid[bc[1]:bc[3], bc[0]:bc[2]] = True
    else:
        issues = json.load(open(os.path.join(ROOT, "demo", "lint", "issues.json")))["issues"]
        d = json.load(open(os.path.join(ROOT, "docs", "map-review.json")))
        all_broken = places(issues, d.get("decisions", d), ns.map)
        grid[bc[1]:bc[3], bc[0]:bc[2]] = all_broken[bc[1]:bc[3], bc[0]:bc[2]]
    win = window_of(box, ns.context)
    if not ns.whole_box and not ns.review_only:
        c0, r0, c1, r1 = win
        found = np.zeros_like(grid)
        found[r0:r1, c0:c1] = flat_chunks(compose(tile, tiles, sea, win)[0])
        grid[bc[1]:bc[3], bc[0]:bc[2]] |= found[bc[1]:bc[3], bc[0]:bc[2]]
    for rect in ns.add:
        a0, b0, a1, b1 = (int(round(float(v) * 16)) for v in rect.split(","))
        grid[b0:b1, a0:a1] = True
    if not grid.any():
        ap.error("no broken ground in that box; --whole-box to repaint all of it")
    edit_grid = grow(grid, ns.grow)
    name = ns.name or f"{ns.map}_" + "_".join(f"{v:g}" for v in box)
    out = os.path.join(ROOT, "demo", "aifix", name)
    os.makedirs(out, exist_ok=True)

    window, _ = compose(tile, tiles, sea, win)
    c0, r0, c1, r1 = win
    edit = edit_grid[r0:r1, c0:c1].repeat(CHUNK, 0).repeat(CHUNK, 1)
    H, W = window.shape[:2]
    yy, xx = np.mgrid[0:H, 0:W]
    for k in ns.keep:
        kc, kr, rad = (float(v) * TILE for v in k.split(","))
        edit &= (xx + c0 * CHUNK - kc) ** 2 + (yy + r0 * CHUNK - kr) ** 2 > rad ** 2
    size = api_size(W, H, ns.max_pixels)
    start = window
    if ns.start:  # the draft over the real ground, whatever window it was painted in
        d, n = ns.start.split(":")
        base = os.path.join(ROOT, "demo", "aifix", d)
        w0 = json.load(open(os.path.join(base, "results.json")))["_window"]
        draft = Image.open(os.path.join(base, n + ".fixed.png")).convert("RGB")
        canvas = Image.fromarray(window)
        canvas.paste(draft, (int(round((w0[0] * 16 - c0) * CHUNK)), int(round((w0[1] * 16 - r0) * CHUNK))))
        start = np.where(edit[..., None], np.asarray(canvas), window)
    small = Image.fromarray(start).resize(size, Image.LANCZOS)
    edit_small = np.asarray(Image.fromarray(edit.astype(np.uint8) * 255).resize(size, Image.BILINEAR)) > 127
    Image.fromarray(window).save(os.path.join(out, "window.png"))
    Image.fromarray(edit.astype(np.uint8) * 255).save(os.path.join(out, "broken.png"))
    print(f"{out}\n  window {c0 / 16:g},{r0 / 16:g} to {c1 / 16:g},{r1 / 16:g}: {W}x{H}; sent at {size[0]}x{size[1]} ({size[0] / W:.2f} of full size); "
          f"repainting {edit.mean():.0%} of it, {edit.sum() / TILE ** 2:.1f} tiles' worth")

    refs = references(tile, tiles, sea, win, edit_grid) if any(RECIPES[r]["refs"] != "none" for r in recipes) else {"none": []}
    api_key = None if ns.dry_run else key()
    if not ns.dry_run and not api_key and any(ns.force or not os.path.exists(os.path.join(out, f"{r}_0.raw.png")) for r in recipes):
        raise SystemExit("no key: OPENAI_API_KEY, or a line of it in the repo's .env. --dry-run prepares without one.")
    results_path = os.path.join(out, "results.json")
    results = json.load(open(results_path)) if os.path.exists(results_path) else {}
    shots = [("original", window)]
    prepared = {}
    for r in recipes:
        recipe, prompt = RECIPES[r], prompt_of(RECIPES[r], ns.prompt_extra)
        sent = inputs(recipe, r, small, edit_small, refs, out)
        with open(os.path.join(out, "input", f"{r}.prompt.txt"), "w") as f:
            f.write(prompt)
        prepared[r] = (recipe, prompt, sent)
        if ns.dry_run:
            print(f"  {r}: {recipe['model']} {ns.quality}, n={ns.n}, {len(sent['images'])} image(s), {sum(map(len, sent['images'])) / 1e6:.1f} MB: would call")

    def have(r):
        return [i for i in range(10) if os.path.exists(os.path.join(out, f"{r}_{i}.raw.png"))]

    def fetch(r):
        recipe, prompt, sent = prepared[r]
        t = time.time()
        try:
            pics, usage = call(api_key, recipe, sent, prompt, size, ns.quality, ns.n)
        except (RuntimeError, urllib.error.URLError, TimeoutError) as e:
            print(f"  {r}: FAILED: {e}", flush=True)
            return
        for f in have(r):
            os.remove(os.path.join(out, f"{r}_{f}.raw.png"))
        for i, b in enumerate(pics):
            with open(os.path.join(out, f"{r}_{i}.raw.png"), "wb") as f:
                f.write(b)
        results[r] = {"model": recipe["model"], "quality": ns.quality, "size": size, "seconds": round(time.time() - t), "usage": usage, "cost": cost(usage)}
        print(f"  {r}: {len(pics)} in {results[r]['seconds']} s, ${results[r]['cost']}", flush=True)
    if not ns.dry_run:
        with ThreadPoolExecutor(ns.parallel) as pool:
            list(pool.map(fetch, [r for r in recipes if ns.force or not have(r)]))
        for r in recipes:
            info = results.get(r)
            if not info or not have(r):
                continue
            info["pictures"] = {}
            for i in have(r):
                p = Image.open(os.path.join(out, f"{r}_{i}.raw.png")).convert("RGB").resize((W, H), Image.LANCZOS)
                fixed, score = put_back(window, np.asarray(p), edit, seed=i + 1)
                Image.fromarray(fixed).save(os.path.join(out, f"{r}_{i}.fixed.png"))
                info["pictures"][str(i)] = score
                shots.append((f"{r} {i}: drift {score['drift']}, edge {score['edge']}, detail {score['detail']}", fixed))
                print(f"    {r}_{i}: {score}")
        results["_window"] = [c0 / 16, r0 / 16, c1 / 16, r1 / 16]
    if not ns.dry_run:
        with open(results_path, "w") as f:
            json.dump(results, f, indent=1)
        write_sheet(os.path.join(out, "sheet.png"), shots)
        print(f"  {os.path.join(out, 'sheet.png')}")


if __name__ == "__main__":
    main()
