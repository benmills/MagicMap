"""tools/seamcheck.py on a synthetic mini map, no game files: a straight painted join is found, a wandering one isn't, a layer's hard alpha edge fails the gate."""
import numpy as np

from seamcheck import account, failures, seams_of

CHUNKS = 48
PX = 8
ALLOW = {"allow": {"*": {"hard_visible": 0, "hard_chunks": 0, "added_in_footprint": 0}}}


def ground():
    r = np.random.RandomState(1)
    return (np.full((CHUNKS * PX, CHUNKS * PX, 3), 90) + r.randint(-1, 2, (CHUNKS * PX, CHUNKS * PX, 3))).astype(np.uint8)


def painted(edge):
    """The ground with everything right of edge[row] (px) a different painting."""
    img = ground()
    for y, x in enumerate(edge):
        img[y, x:] = np.clip(img[y, x:].astype(int) + 40, 0, 255)
    return img


def test_a_straight_join_is_found():
    s = seams_of(painted(np.full(CHUNKS * PX, 24 * PX)))
    assert s["v"][:, 24].all() and s["off"] == 0


def test_a_wandering_join_is_not():
    walk = np.cumsum(np.random.RandomState(2).randint(-3, 4, CHUNKS * PX))
    edge = 24 * PX + 3 + np.round(14 * np.sin(np.arange(CHUNKS * PX) / 9)).astype(int) + np.clip(walk, -6, 6)
    assert seams_of(painted(edge))["v"].sum() == 0


def layer(alpha):
    rgba = np.zeros((16 * 16, 16 * 16, 4), np.uint8)  # a tile's picture, 16 px a chunk
    rgba[..., :3] = 200
    rgba[..., 3] = alpha
    return {"name": "test", "pics": [{"rgba": rgba, "col": 1, "row": 1, "w": 1, "h": 1}]}


def test_a_hard_alpha_edge_fails_the_gate():
    size = 16 * 16
    r = account(ground(), [layer(255)])
    assert failures(r["stages"], ALLOW)
    assert any(e["box"] and e["visible"] for e in r["edges"])
    d = np.minimum.outer(np.minimum(np.arange(size), size - 1 - np.arange(size)), np.minimum(np.arange(size), size - 1 - np.arange(size)))
    soft = (np.clip(d / 64, 0, 1) * 255).astype(np.uint8)  # faded on all four sides
    assert not failures(account(ground(), [layer(soft)])["stages"], ALLOW)
    twosided = soft.copy()
    twosided[:size // 2] = soft[size // 2:size // 2 + 1]  # faded on two: the bug this tool is for
    assert failures(account(ground(), [layer(twosided)])["stages"], ALLOW)
