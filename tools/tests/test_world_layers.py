"""UI's remaining layers on the simulated client (docs/v1-plan.md M4.4): Model's kinds and parts stubbed as
M4.1 and M4.3 hand them over (types/model.lua, types/observation.lua), drawn as the spike's:

  test_places: Known("places") and Known("vignettes") as pins on the store, each kind its look (S48: its art,
    else a dot of its colour; 18, 20, 16, 18, 20) and tooltip line; on by default but the graveyards; each
    gear row's toggle hides its kind alone (F39, F44).
  test_group: Known("group") as the Minimap's party blips (S52): PartyRaidBlipsV2's left half, 12 px, the class's
    colour, dead grey; moved as Model's list changes; the member's tooltip, Game's, on hover; the toggle (F41).
  test_view: View small, big, indoors (Blizzard's floor plan; the art) and hidden: renderer, chrome, the layers
    Game acts on and the sockets (the minimap one beside the world one).
  test_indoor_art: the art of the map you're on over a dark backdrop (S40), at the camera's zoom, outlined under
    /mm indoor; none off its map.
  test_inspector_lines: the right-click menu's place line from the spot's cell and the explored areas (Unexplored,
    near ...: by the cell; a city's coordinates alone) and at most 2 landmarks within 900 yd, its layer on or off (F38, S62).
"""
from test_addon import boot, errors

SETUP = """
local Sim, ns = ...
local Atlas = ns.Atlas
NS = ns -- (the test's own chunks)
-- Model's kinds as M4.3 hands them on: Put(kind, list) a new list, its rev moved (past the real kind's).
local kinds = {}
function Put(kind, list)
	local k = kinds[kind]
	if not k then
		k = { rev = select(2, ns.Model.Known(kind)) }
		kinds[kind] = k
		ns.Model.Kind(kind, function() return k.list, k.rev end)
	end
	k.list, k.rev = list, k.rev + 1
end
-- Game's parts as M4.1 and M4.2 hand them over: obs.explored, obs.exploredCells, obs.indoorArt; obs.minimap's
-- indoors and indoorDebug (the last registered part's value wins).
Parts = { minimap = {} }
ns.Game.Part("explored", function() return Parts.explored end)
ns.Game.Part("exploredCells", function() return Parts.cells end)
-- Every cell of every continent lit (true) or dark (false), as obs.exploredCells.
function Every(v)
	local row = setmetatable({}, { __index = function() return v end })
	local rows = setmetatable({}, { __index = function() return row end })
	return setmetatable({}, { __index = function() return rows end })
end
ns.Game.Part("indoorArt", function() return Parts.art end)
ns.Game.Part("minimap", function(obs)
	local m = obs.minimap
	m.indoors, m.indoorDebug = Parts.minimap.indoors, Parts.minimap.indoorDebug
	return m
end)
function Place(key, place, name, col, row, more)
	local e = more or {}
	e.key, e.kind, e.place, e.name, e.live, e.pos = key, "places", place, name, true, { inst = 0, col = col, row = row }
	return e
end
-- The cursor over tile (col, row) of the map shown.
function Over(col, row)
	local view, cam = ns.UI.Window.view, ns.UI.Camera.cam
	local w, h = ns.UI.Window.Size()
	local x, y = Atlas.Camera.TileToScreen(cam, w, h, col, row)
	local s = view:GetEffectiveScale()
	Sim.cursorX, Sim.cursorY = (view:GetLeft() + x) * s, (view:GetTop() - y) * s
end
function PinOf(layer, key)
	local p = layer.front.pools.pin
	return p and p.at[key] and p.at[key] <= p.n and p[p.at[key]] or nil
end
"""

CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"


def client(big=False, zoom=None):
    L, sim, ns = boot()
    L.execute(SETUP, sim, ns)
    sim.Slash("/mm toggle")
    sim.Run(1.5)
    if big:
        sim.Press("M")
        sim.Run(1)
    if zoom:
        ns.UI.Motion.SetZoom(zoom)
        sim.Run(1)
    return L, sim, ns, L.globals()


def rgb(sim, region):
    return [round(v, 3) for v in list(sim.state[region].vertex.values())[:3]]


def tooltip(sim, G):
    tip = G.GameTooltip
    return [sim.state[tip.GetLeftLine(tip, i)].text for i in range(1, tip.NumLines(tip) + 1)] if sim.state[tip].shown else []


def test_places():
    L, sim, ns, G = client(big=True, zoom=100)
    S, UI, E = sim.state, ns.UI, ns.UI.Engine
    for atlas in ("TaxiNode_Alliance", "poi-graveyard-neutral"):  # (the rest the client lacks: their dots)
        sim.atlases[atlas] = True
    L.execute("""Put("places", {
        Place("flight:2", "flight", "Stormwind, Elwynn", 31.103, 48.561, { faction = "A", known = true, icon = { atlas = "TaxiNode_Alliance" } }),
        Place("flight:5", "flight", "Lakeshire, Redridge", 32.6, 49.4, { icon = { atlas = "TaxiNode_Neutral" } }),
        Place("flight:9", "flight", "Horde Camp", 32.8, 50.3, { faction = "H", icon = { atlas = "TaxiNode_Horde" } }),
        Place("poi:7", "poi", "Goldshire", 31.881, 49.775, { text = "A town", icon = { atlas = "poi-town" } }),
        Place("graveyard:1", "graveyard", "Goldshire", 32.52, 49.88, { icon = { atlas = "poi-graveyard-neutral" } }),
        Place("dungeon:63", "dungeon", "Deadmines", 31.2, 50.4, { text = "A dungeon", icon = { atlas = "Dungeon" } }),
    })
    local inst, col, row = NS.Atlas.MapToTile(1429, 0.38, 0.79)
    Put("vignettes", { { key = "Vignette-0-1", kind = "vignettes", name = "Mother Fang", live = true, rare = true,
        icon = { atlas = "VignetteKill" }, pos = { inst = inst, col = col, row = row } } })""")
    sim.Run(1)
    lay = UI.Places

    def pin(key):
        return G.PinOf(lay, key)

    # Each kind's look (Layers.lua:459-534, Landmarks.lua:95, 135): its art at its size, else a dot of its colour.
    p = pin("flight:2")
    assert S[p].width == 18 and S[p.icon].atlas == "TaxiNode_Alliance" and S[p.icon].width == 18
    dots = {"flight:5": (18, [1, 0.82, 0]), "flight:9": (18, [0.9, 0.2, 0.2]), "poi:7": (18, [0.6, 0.85, 1]),
            "dungeon:63": (20, [0.7, 0.4, 1]), "Vignette-0-1": (20, [1, 0.4, 0.3])}
    for key, (size, color) in dots.items():
        p = pin(key)
        assert S[p].width == size and S[p.icon].texture == CIRCLE and rgb(sim, p.icon) == color, key
        assert abs(S[p.icon].width - size * 0.6) < 1e-9 and rgb(sim, p.ring) == [0, 0, 0], key
    # On by default, the graveyards off (Layers.lua:48-53; Landmarks.lua:110, 142).
    assert [E.LayerOn(k) for k in ("flight", "dungeons", "graveyards", "areaPOIs", "vignettes")] == [True] * 2 + [False] + [True] * 2
    assert pin("graveyard:1") is None
    # The tooltips: the name, then what it is, its description, "Nearby now" (Layers.lua:470-534; Landmarks.lua:94).
    G.Over(31.103, 48.561)
    sim.FireScript(UI.Window.view, "OnEnter", False)
    sim.Step()
    assert tooltip(sim, G) == ["Stormwind, Elwynn", "Flight point"]
    for at, lines in (((31.2, 50.4), ["Deadmines", "A dungeon"]), ((31.881, 49.775), ["Goldshire", "A town"])):
        G.Over(*at)
        sim.Step()
        assert tooltip(sim, G) == lines, lines
    v = ns.Model.Known("vignettes")[0][1]
    G.Over(v.pos.col, v.pos.row)
    sim.Step()
    assert tooltip(sim, G) == ["Mother Fang", "|cff808080Nearby now|r"]

    # Each toggle hides its kind alone; the graveyards turned on: their art at 16.
    E.SetLayer("graveyards", True)
    sim.Run(0.5)
    p = pin("graveyard:1")
    assert S[p].width == 16 and S[p.icon].atlas == "poi-graveyard-neutral"
    every = ["flight:2", "flight:5", "flight:9", "poi:7", "graveyard:1", "dungeon:63", "Vignette-0-1"]
    for key, gone in (("flight", ["flight:2", "flight:5", "flight:9"]), ("dungeons", ["dungeon:63"]),
                      ("graveyards", ["graveyard:1"]), ("areaPOIs", ["poi:7"]), ("vignettes", ["Vignette-0-1"])):
        E.SetLayer(key, False)
        sim.Run(0.5)
        assert [k for k in every if pin(k) is not None] == [k for k in every if k not in gone], key
        E.SetLayer(key, True)
        sim.Run(0.5)
        assert all(pin(k) is not None for k in every), key
    # Game's tracking of what ours draw (flight points, points of interest) goes by these toggles: View.layers.
    view = UI.View()
    assert view.layers.flight is True and view.layers.pois is True
    E.SetLayer("areaPOIs", False)
    sim.Step()
    assert view.layers.pois is None and view.layers.flight is True
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_group():
    L, sim, ns, G = client()
    S, UI = sim.state, ns.UI
    G.RAID_CLASS_COLORS.MAGE = L.table_from({"r": 0.41, "g": 0.8, "b": 0.94})
    L.execute("""
    function Member(id, name, class, col, row, dead)
        return { key = id, kind = "group", name = name, class = class, level = 12, dead = dead, live = true,
            pos = { inst = 0, col = col, row = row } }
    end
    Put("group", { Member("Player-1-00000002", "Ally", "MAGE", 32.0, 49.8), Member("Player-1-00000003", "Fallen", "MAGE", 31.9, 49.7, true),
        { key = "Player-1-00000004", kind = "group", name = "Away", class = "MAGE", live = true, pos = { inst = 1, col = 40, row = 30 } } })""")
    sim.Step()
    dots = UI.Group.dots
    shown = [d for d in dots.values() if S[d].shown]
    assert len(shown) == 2  # (one on another continent: not on the map shown)
    w, h = UI.Window.Size()
    for d, (col, row, color) in zip(shown, ((32.0, 49.8, [0.41, 0.8, 0.94]), (31.9, 49.7, [0.5, 0.5, 0.5]))):
        assert S[d].texture == "Interface\\Minimap\\PartyRaidBlipsV2" and list(S[d].texCoord.values()) == [0, 0.5, 0, 1]
        assert S[d].width == 12 and S[d].height == 12 and rgb(sim, d) == color
        x, y = ns.Atlas.Camera.TileToScreen(UI.Camera.cam, w, h, col, row)
        point = S[d].points[1]
        assert point.point == "CENTER" and abs(point.x - x) < 1e-9 and abs(point.y + y) < 1e-9
    # They walk: placed again as Model's list changes (Game reads them 20 times a second); alive again, its colour.
    L.execute("""Put("group", { Member("Player-1-00000002", "Ally", "MAGE", 32.02, 49.8), Member("Player-1-00000003", "Fallen", "MAGE", 31.9, 49.7) })""")
    sim.Step()
    x, _ = ns.Atlas.Camera.TileToScreen(UI.Camera.cam, w, h, 32.02, 49.8)
    assert abs(S[shown[0]].points[1].x - x) < 1e-9 and rgb(sim, shown[1]) == [0.41, 0.8, 0.94]
    assert len(dots) == 2  # (a dot each on the map shown)

    # Hovered: the member's tooltip, Game's (its name in its class's colour, level and class: the tooltip Command).
    sim.group = L.table_from(["party1"])
    sim.units.party1 = L.table_from({"name": "Ally", "class": "MAGE", "level": 12, "guid": "Player-1-00000002"})
    G.Over(32.02, 49.8)
    sim.FireScript(UI.Window.view, "OnEnter", False)
    sim.Step()
    tip = G.GameTooltip
    assert tooltip(sim, G) == ["Ally", "Level 12 MAGE"] and L.eval("rawequal")(S[tip].owner, UI.Group.tip)
    G.Over(31.5, 49.0)
    sim.Step()
    assert tooltip(sim, G) == []
    # The gear's "Party & raid" off: none.
    ns.UI.Engine.SetLayer("group", False)
    sim.Step()
    assert not any(S[d].shown for d in dots.values())
    ns.UI.Engine.SetLayer("group", True)
    sim.Step()
    assert sum(1 for d in dots.values() if S[d].shown) == 2
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def sockets(view):
    s = view.sockets
    return s.world is not None, s.minimap is not None


def test_view():
    L, sim, ns, G = client()
    UI, view = ns.UI, ns.UI.View()
    world, mini = UI.Sockets.world, UI.Sockets.minimap
    same = L.eval("rawequal")

    def chrome():
        c = view.chrome
        return c and (c.rimArrows, c.questRing)

    # Small, outdoors: our renderer; Blizzard's rim stands down; the layers Game acts on; both sockets: the minimap
    # one at the camera's zoom every frame (tile (col, row) at (col * zoom, -row * zoom) from its TOPLEFT).
    assert view.renderer == "ours" and chrome() == (False, False) and not view.window.big
    assert [view.layers[k] for k in ("blips", "flight", "quests", "pois")] == [True] * 4
    assert same(view.sockets.world, world) and same(view.sockets.minimap, mini) and not same(mini.frame, world.frame)
    assert mini.level == UI.Window.view.GetFrameLevel(UI.Window.view) + 17  # under your arrow's overlay (18)

    def at_camera():
        cam, (w, h) = UI.Camera.cam, UI.Window.Size()
        p = sim.state[mini.frame].points[1]
        return mini.inst == 0 and mini.zoom == cam.zoom and abs(p.x - (w / 2 - cam.cx * cam.zoom)) < 1e-6 \
            and abs(p.y - (cam.cy * cam.zoom - h / 2)) < 1e-6
    assert at_camera()
    sim.Wheel(UI.Window.view, 1)
    for _ in range(5):
        sim.Step()
        assert at_camera() and world.zoom != UI.Camera.cam.zoom  # (the world socket's waits for the view to rest)
    sim.Run(1)
    # Big: the same.
    sim.Press("M")
    sim.Run(1)
    assert view.window.big and view.renderer == "ours" and chrome() == (False, False) and sockets(view) == (True, True)
    # Indoors with no art: big, our terrain; small, Blizzard's whole Minimap: its rim, no sockets.
    G.Parts.minimap.indoors = True
    sim.Step()
    assert view.renderer == "ours" and sockets(view) == (True, True)
    sim.Press("M")
    sim.Run(1)
    frame = view.frame
    assert view.renderer == "blizzard" and view.chrome is None and sockets(view) == (False, False)
    # The art of the map you're on: ours over it; on another map's, Blizzard's floor plan.
    L.execute("Parts.art = { uiMap = 1453, pieces = { { file = 900001, rect = { inst = 0, c0 = 31.8, r0 = 49.6, c1 = 32.1, r1 = 49.9 } } } }")
    sim.Step()
    assert view.renderer == "ours+art" and view.frame > frame and chrome() == (False, False) and sockets(view) == (True, True)
    G.Parts.art.pieces[1].rect.inst = 1
    sim.Step()
    assert view.renderer == "blizzard"
    # Outdoors again; then hidden: ours, nothing borrowed, the rim as Blizzard has it; the layers still said.
    G.Parts.minimap.indoors = False
    sim.Step()
    assert view.renderer == "ours" and sockets(view) == (True, True)
    sim.Slash("/mm toggle")
    sim.Step()
    assert not view.window.shown and view.renderer == "ours" and view.chrome is None and sockets(view) == (False, False)
    assert view.layers.flight is True and view.layers.quests is True
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


ART = """Parts.minimap.indoors = true
local pieces = {}
for i = 0, 3 do -- 2 x 2, the last row and column half a tile of art (u, v)
    local c, r = i % 2, math.floor(i / 2)
    local c0, r0 = 31.8 + c * 0.2, 49.6 + r * 0.2
    pieces[i + 1] = { file = 900001 + i, u = c == 1 and 0.5 or nil, v = r == 1 and 0.5 or nil,
        rect = { inst = 0, c0 = c0, r0 = r0, c1 = c0 + (c == 1 and 0.1 or 0.2), r1 = r0 + (r == 1 and 0.1 or 0.2) } }
end
Parts.art = { uiMap = 1458, pieces = pieces }"""


def test_indoor_art():
    L, sim, ns, G = client(zoom=200)
    S, UI, Maths = sim.state, ns.UI, ns.Atlas.Camera
    art = UI.IndoorArt
    assert not S[art.frame].shown
    L.execute(ART)
    sim.Step()
    f, cam = art.frame, UI.Camera.cam

    def placed():
        """Its regions shown: (file or colour, x, y, w, h, texcoords); the frame's top left where the art's is."""
        w, h = UI.Window.Size()
        x, y = Maths.TileToScreen(cam, w, h, 31.8, 49.6)
        p = S[f].points[1]
        assert abs(p.x - x) < 1e-9 and abs(p.y + y) < 1e-9
        out = []
        for r in S[f].regions.values():
            if S[r].shown:
                q, tc = S[r].points[1], S[r].texCoord
                r6 = lambda v: v if v is None else round(v, 6)  # noqa: E731 (an edge: one side's size, two anchors)
                out.append((S[r].texture or tuple(S[r].color.values()), r6(q.x), r6(q.y), r6(S[r].width),
                            r6(S[r].height), tuple(tc.values()) if tc else None))
        return out

    def pieces():
        return {g[0]: g[1:] for g in placed() if isinstance(g[0], int)}

    # The art over the tiles on a dark backdrop (IndoorArt.lua:18), each piece at the camera's zoom.
    z = cam.zoom
    assert S[f].shown and f.GetFrameLevel(f) == UI.Window.view.GetFrameLevel(UI.Window.view) + 2
    back = next(g for g in placed() if g[0] == (0.06, 0.05, 0.04, 1))
    assert back[3:5] == (round(0.3 * z, 6), round(0.3 * z, 6))
    got = pieces()
    assert got[900001] == (0, 0, round(0.2 * z, 6), round(0.2 * z, 6), (0, 1, 0, 1))
    assert got[900004] == (round(0.2 * z, 6), round(-0.2 * z, 6), round(0.1 * z, 6), round(0.1 * z, 6), (0, 0.5, 0, 0.5))
    # Zoomed: placed again at the new zoom; /mm indoor: outlined in pink.
    UI.Motion.SetZoom(400)
    sim.Run(1)
    z = cam.zoom
    assert pieces()[900004][2] == round(0.1 * z, 6)
    G.Parts.minimap.indoorDebug = True
    sim.Step()
    assert sum(1 for g in placed() if g[0] == (1, 0.2, 0.8, 0.9)) == 4
    # Outdoors, or the art on another map: none.
    G.Parts.minimap.indoors = False
    sim.Step()
    assert not S[f].shown
    G.Parts.minimap.indoors = True
    sim.Step()
    assert S[f].shown
    G.Parts.art.pieces[1].rect.inst = 1
    sim.Step()
    assert not S[f].shown
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


SEP = "|cff808080  ·  |r".encode("utf-8").decode("latin-1")  # (the sim's Lua strings: latin-1)
GREY, WHITE, DIM = "|cffa8a8a8", "|cffffffff", "|cff808080"


def test_inspector_lines():
    L, sim, ns, G = client(big=True)
    UI, view = ns.UI, ns.UI.Window.view
    L.execute("""Put("places", {
        Place("flight:2", "flight", "Stormwind, Elwynn", 31.103, 48.561, { faction = "A" }),
        Place("graveyard:1", "graveyard", "Goldshire", 32.52, 49.88),
        Place("dungeon:63", "dungeon", "Deadmines", 28.848, 53.015, { text = "A dungeon" }),
        Place("flight:3", "flight", "Programmer Isle", 1.36, 1.265) })""")

    def menu(col, row):
        G.Over(col, row)
        sim.Click(view, "RightButton", sim.cursorX, sim.cursorY, "screen")
        return [e.text for e in sim.menu["items"].values() if e.kind == "title"]

    lake = ns.Atlas.AreaAt(0, 32.28, 49.65)
    zone = ns.Atlas.Area(lake).zone
    coords = GREY + "48.5, 63.7|r"
    assert ns.Atlas.Area(lake).name == "Crystal Lake" and ns.Atlas.Area(lake).parent == zone
    # Line 2, the place (ZoneInfo.lua:71-109): the spot's cell lit, the areas explored there but the zone; dark
    # (the client names none there, whatever's named elsewhere), "Unexplored, near" the spot's subzone; only the
    # zone's, or Game can't say, the coordinates alone.
    unexplored = DIM + "Unexplored|r" + DIM + ", near|r " + WHITE + "Crystal Lake|r" + SEP + coords
    cases = [({lake: True}, True, WHITE + "Crystal Lake|r" + SEP + coords),
             ({lake: False}, False, unexplored),
             ({lake: True}, False, unexplored),
             ({lake: False, zone: True}, True, coords),
             ({}, None, coords)]
    for explored, lit, line in cases:
        G.Parts.explored, G.Parts.cells = L.table_from(explored), None if lit is None else G.Every(lit)
        sim.Step()
        assert menu(32.28, 49.65)[1] == line, (explored, lit)
    # Near: the nearest subzone label within 350 yd (ZoneInfo.lua:99-106), not the spot's own area: on Fargodeep
    # Mine's ground, The Maclure Vineyards' label 53 yd off.
    G.Parts.explored, G.Parts.cells = L.table_from({}), G.Every(False)
    sim.Step()
    near = menu(31.8, 50.5)[1]
    assert near.startswith(DIM + "Unexplored|r" + DIM + ", near|r " + WHITE + "The Maclure Vineyards|r" + SEP), near
    # Landmarks within 900 yd, the nearest of each kind, the closest first, at most 2, their layer off or on
    # (ZoneInfo.lua:138-157): the graveyards' layer is off.
    G.Parts.explored, G.Parts.cells = L.table_from({lake: True}), G.Every(True)
    sim.Step()
    lines = menu(32.28, 49.65)
    assert not ns.UI.Engine.LayerOn("graveyards")
    assert lines[-2:] == [GREY + "Graveyard|r " + WHITE + "Goldshire|r" + SEP + GREY + "175 yd SE|r",
                          GREY + "Flight point|r " + WHITE + "Stormwind, Elwynn|r" + SEP + GREY + "860 yd NW|r"], lines
    # Here (under 15 yd); a third kind nearer than the flight point: 2 still, the closest; one its kind's name, untitled.
    L.execute("""Put("places", { Place("graveyard:1", "graveyard", "Graveyard", 32.28, 49.651),
        Place("dungeon:9", "dungeon", "Crystal Cave", 32.4, 49.65), Place("flight:2", "flight", "Stormwind, Elwynn", 31.103, 48.561) })""")
    sim.Step()
    lines = menu(32.28, 49.65)
    assert lines[-2:] == [GREY + "Graveyard|r " + GREY + "here|r",
                          GREY + "Dungeon|r " + WHITE + "Crystal Cave|r" + SEP + GREY + "65 yd E|r"], lines
    # A city: no fog of war to lift (C_Map.IsCityMap's): unexplored there, the coordinates alone.
    city = L.eval("""function(ns)
        for c = 29, 32, 0.05 do
            for r = 47.2, 49, 0.05 do
                local z = ns.Atlas.ZoneMapAt(0, c, r)
                if z and z.mapID == 1453 then return { c, r, z.area } end
            end
        end
    end""")(ns)
    G.Parts.explored, G.Parts.cells = L.table_from({city[3]: False}), G.Every(False)
    UI.Motion.SetFollow(False)
    UI.Camera.cam.cx, UI.Camera.cam.cy = city[1], city[2]
    sim.Run(0.5)
    lines = menu(city[1], city[2])
    assert lines[0] == "|cffffd100Stormwind City|r" and lines[1].startswith(GREY) and SEP not in lines[1], lines
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))
