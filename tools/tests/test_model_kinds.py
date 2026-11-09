"""Model alone (plain Lua, tools/tests/replay.lua) on the fixture streams: Known("places") and Known("group")
(docs/v1-plan.md M4.3). Known("rares") and Known("vignettes"): R-D4, R-S1.

  test_places_model: the places stream (Elwynn's live places) over Atlas's (Data/Places.lua): Atlas's until the
    game marks a kind on the instance, then the game's; a place the game marks on two maps, once; another
    instance shown, its own Atlas places.
  test_group_model: the group stream (two members at ~20 Hz): an entry a member kept as it moves, dead, one
    withheld not listed, none.
"""
from lupa import lua51

from fixtures import ROOT, lua_tools

SAVED = "{ _v = 1, rares = {} }"
PLACES = "local ns = { Data = {} }; assert(loadfile(...))('MagicMap', ns); return ns.Data"


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

