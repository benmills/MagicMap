"""tools/ai_fix.py: only the broken ground changes, whatever the model did to the rest; a good repaint blends; sizes the API takes."""
import numpy as np

import ai_fix as af


def test_put_back():
    rng = np.random.default_rng(3)
    window = rng.integers(60, 120, (512, 512, 3), np.uint8)
    window[192:320, 192:320] = (90, 70, 30)  # the flat block
    edit = np.zeros((512, 512), bool)
    edit[160:352, 160:352] = True
    picture = np.clip(rng.integers(60, 120, (512, 512, 3)) + 25, 0, 255).astype(np.uint8)  # good, but it's redrawn everything brighter
    out, score = af.put_back(window, picture, edit)
    assert (out[~edit] == window[~edit]).all(), "the game's pixels, exactly, outside"
    assert (out[250, 250] != window[250, 250]).any()
    assert score["drift"] > 10 and .7 < score["detail"] < 1.3
    assert abs(float(out[230:280, 230:280].mean()) - float(window[:100].mean())) < 8, "its colours pulled to the ground's"


def test_sizes():
    w, h = af.api_size(3552, 2432, af.LIMIT_PIXELS)
    assert w % 16 == h % 16 == 0 and w * h <= af.LIMIT_PIXELS and abs(w / h - 3552 / 2432) < .02
    assert af.api_size(1024, 1024, af.LIMIT_PIXELS) == (1024, 1024)
    c0, r0, c1, r1 = af.window_of((30, 30, 30.2, 34), .1)
    w, h = (c1 - c0), (r1 - r0)
    assert max(w, h) <= 3 * min(w, h) and w * h * af.CHUNK ** 2 >= af.MIN_PIXELS
