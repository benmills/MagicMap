"""Model alone (plain Lua, tools/tests/replay.lua) on the fixture streams: Known("places"), Known("group") and
the blips our other kinds stand for (docs/v1-plan.md M4.3). Known("rares") and Known("vignettes"): R-D4, R-S1;
Known("services"): test_services.

  test_places_model: the places stream (Elwynn's live places) over Atlas's (Data/Places.lua): Atlas's until the
    game marks a kind on the instance, then the game's; a place the game marks on two maps, once; another
    instance shown, its own Atlas places.
  test_group_model: the group stream (two members at ~20 Hz): an entry a member kept as it moves, dead, one
    withheld not listed, none.
  test_blips_ours_model: a quest giver's "!" and a quest ender's "?" (made-up Data.BlipServices); no blip under
    one of our pins (an offer's, a flight point's) while its layer is on; the remembered shown and forgotten only
    while tracking shows them; one seen again within the hour left as it is.
"""
from lupa import lua51

from test_blips import ROOT, lua_tools

SAVED = "{ _v = 1, rares = {}, blips = {} }"
PLACES = "local ns = { Data = {} }; assert(loadfile(...))('MagicMapAtlas', ns); return ns.Data"


def setup(data=None):
    L = lua51.LuaRuntime(unpack_returned_tuples=True)
    tools = lua_tools(L)
    places = L.execute(PLACES, ROOT + "/Data/Places.lua")
    if data:
        L.eval("""function(d, more) for k, v in pairs(more) do d[k] = v end
            d.formats.Places = 1 end""")(places, L.execute(data))
    model = tools.Model(ROOT, places)
    model.Load(L.eval(SAVED))
    return L, tools, model


def known(model, kind):
    entries, rev = model.Known(kind)
    return list(entries.values()), rev


def test_places_model():
    L, tools, model = setup()
    stream = tools.Stream(ROOT, "places")
    model.Focus(L.table_from({"inst": 0, "shown": True}))
    got, _ = known(model, "places")  # Atlas's alone: none marked yet
    assert got and not any(e.live for e in got) and {e.place for e in got} == {"flight", "poi", "dungeon"}
    assert [e.name for e in got if e.key == "dungeon:36"] == ["Deadmines"]
    oracles = tools.Oracles(stream)
    model.Observe(stream[1], oracles)
    got, rev = known(model, "places")
    assert sorted(e.key for e in got) == ["dungeon:63", "flight:2", "flight:4", "flight:5", "graveyard:1", "poi:7"]
    assert all(e.live and e.kind == "places" for e in got) and [e.name for e in got].count("Deadmines") == 1
    flight = {e.key: e for e in got}
    assert (flight["flight:2"].known, flight["flight:4"].known, flight["flight:5"].known) == (True, False, None)
    assert flight["flight:2"].faction == "A" and flight["dungeon:63"].text == "A dungeon"
    model.Observe(stream[2], oracles)  # nothing new: the same list
    assert known(model, "places")[1] == rev
    for i in (3, 4, 5):
        model.Observe(stream[i], oracles)
    got, _ = known(model, "places")
    assert {e.key: e.known for e in got if e.place == "flight"}["flight:4"] is True and len(got) == 7
    # The same place from its continent's map and its zone's: once.
    twice = L.eval("""function(obs) local o = {} for k, v in pairs(obs) do o[k] = v end
        local p = {} for i, x in ipairs(obs.places) do p[i] = x end
        local copy = {} for k, v in pairs(obs.places[1]) do copy[k] = v end
        p[#p + 1] = copy; o.places = p; return o end""")(stream[5])
    model.Observe(twice, oracles)
    got, _ = known(model, "places")
    assert [e.key for e in got].count("flight:2") == 1 and len(got) == 7
    # Kalimdor shown: its Atlas places too (the game's are Eastern Kingdoms').
    model.Focus(L.table_from({"inst": 1, "shown": True}))
    got, _ = known(model, "places")
    assert {e.pos.inst for e in got if e.live} == {0} and any(e.pos.inst == 1 and not e.live for e in got)


def test_group_model():
    L, tools, model = setup()
    stream = tools.Stream(ROOT, "group")
    oracles = tools.Oracles(stream)
    revs, first, same = [], None, L.eval("function(a, b) return a == b end")
    for i in range(1, len(stream) + 1):
        model.Observe(stream[i], oracles)
        got, rev = known(model, "group")
        revs.append(rev)
        by = {e.name: e for e in got}
        if i == 1:
            first = by["Brannock"]
            assert (first.key, first.kind, first["class"], first.level, first.live, first.dead) == \
                ("Player-4395-0A1B2C3D", "group", "WARRIOR", 9, True, False)
        if i <= 11:
            assert sorted(by) == ["Brannock", "Elandra"] and same(by["Brannock"], first)  # (kept, moved in place)
            assert abs(first.pos.col - stream[i].group[1].pos.col) < 1e-12
        if i == 12:
            assert by["Brannock"].dead is True
        if i in (13, 14, 15):
            assert sorted(by) == ["Brannock"]  # Elandra withheld, then gone
    assert revs[-1] > revs[-2] and known(model, "group")[0] == [] and len(set(revs[:11])) == 11


def test_blips_ours_model():
    L, tools, model = setup("""return { formats = { BlipServices = 2 },
        BlipServices = { ["Marshal Dughan"] = { "questgiver" }, ["Remy"] = { "questender", "Fishing Supplies" },
            ["Stormwind City Guard"] = { nil, "Guard" } } }""")
    saved = L.eval(SAVED)
    model.Load(saved)
    model.Focus(L.table_from({"inst": 0, "shown": True}))
    obs = L.eval("""function(frame, epoch, list, extra)
        local o = { frame = frame, t = frame / 60, epoch = epoch, hooked = {},
            you = { inst = 0, col = 31.95, row = 49.75, facing = 0 },
            blips = { list = list, sweep = frame, center = { inst = 0, col = 31.95, row = 49.75 }, reach = 200 * 3 / 1600 } }
        for k, v in pairs(extra or {}) do o[k] = v end
        return o end""")
    blip = L.eval("""function(name, east, north, icon) return { name = name, rough = false, icon = icon,
        pos = { inst = 0, col = 31.95 + east * 3 / 1600, row = 49.75 - north * 3 / 1600 } } end""")
    dughan, remy, guard = blip("Marshal Dughan", 30, 0), blip("Remy", -30, 0), blip("Stormwind City Guard", 0, 40)
    mail = blip("Mailbox", 40, 20, 136459)
    four = L.table_from([dughan, remy, guard, mail])
    model.Observe(obs(1, 1000, four), L.table())
    icons = {e.name: e.icon and e.icon.texture for e in known(model, "blips")[0]}
    assert icons == {"Marshal Dughan": 132049, "Remy": 132048, "Stormwind City Guard": None, "Mailbox": 136459}
    titles = {e.name: e.text for e in known(model, "blips")[0]}  # the NPC's title (Blips.lua:436)
    assert titles == {"Marshal Dughan": None, "Remy": "Fishing Supplies", "Stormwind City Guard": "Guard", "Mailbox": None}
    (mailbox,) = saved.blips[0].values()
    assert mailbox.t == 1000
    # An offer's pin 5 yd from Dughan: its blip is that pin's; the offers layer off, it's back.
    offer = L.eval("function(b) return { { questID = 1, name = 'Report to Goldshire', pos = { inst = 0, col = b.pos.col, "
                   "row = b.pos.row + 5 * 3 / 1600 } } } end")(dughan)
    model.Observe(obs(2, 1600, L.table_from([remy, guard, mail, dughan]), L.table_from({"offers": offer})), L.table())
    assert sorted(e.name for e in known(model, "blips")[0]) == ["Mailbox", "Remy", "Stormwind City Guard"]
    assert mailbox.t == 1000  # seen again within the hour: left as it is
    model.Focus(L.table_from({"inst": 0, "shown": True, "off": L.table_from({"offers": True})}))
    assert "Marshal Dughan" in [e.name for e in known(model, "blips")[0]]
    # Tracking: mailboxes off, the remembered one isn't shown, and a sweep that doesn't see it keeps it.
    track = L.eval("function(on) return { { id = 64, name = 'Mailbox', texture = 136459, active = on } } end")
    model.Observe(obs(3, 5000, L.table_from([remy]), L.table_from({"tracking": track(False)})), L.table())
    assert known(model, "remembered")[0] == [] and len(list(saved.blips[0].keys())) == 1
    model.Observe(obs(4, 5000, L.table_from([remy]), L.table_from({"tracking": track(True)})), L.table())
    assert known(model, "remembered")[0] == [] and len(list(saved.blips[0].keys())) == 0  # tracked: forgotten
