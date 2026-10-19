
MagicMapAtlasDB = {
["telemetry"] = {
["sessions"] = {
{
["id"] = 1,
["version"] = "7aa8b30",
["build"] = "1.60.1.70374",
["started"] = 1791990000,
["boot"] = {
["loadMs"] = 412.6,
["loadKB"] = 38211,
["loginMs"] = 1630.2,
},
["frames"] = 5210,
["perf"] = {
["frames"] = 5100, ["p50"] = 0.2, ["p95"] = 0.35, ["p99"] = 4.5, ["max"] = 27.2, ["overruns"] = 3,
["kbMin"] = 52100, ["kbMax"] = 72500, ["ourKB"] = 72500, ["loadMs"] = 412.6, ["errors"] = 0, ["errorsPerHour"] = 0,
["kbPerSec"] = 274, ["kbFrameP95"] = 6.2,
["grace"] = { ["login"] = 155, ["map"] = 67.5 },
["slow"] = { { ["name"] = "map: borders", ["n"] = 12, ["max"] = 20.1 } },
},
["zones"] = {
"Dun Morogh", -- [1]
},
}, -- [1]
{
["id"] = 2,
["version"] = "7aa8b30-dirty",
["build"] = "1.60.1.70374",
["started"] = 1791993600,
["boot"] = {
["loadMs"] = 398.1,
["loadKB"] = 38240,
["loginMs"] = 1588.4,
},
["frames"] = 18342,
["perf"] = {
["frames"] = 17890, ["p50"] = 0.25, ["p95"] = 0.8, ["p99"] = 5.4, ["max"] = 11.2, ["overruns"] = 2,
["kbMin"] = 47100, ["kbMax"] = 61800, ["ourKBLoad"] = 40100, ["ourKB"] = 72500, ["loadMs"] = 398.1,
["errors"] = 37, ["errorsPerHour"] = 148, ["kbPerSec"] = 274.3, ["kbFrameP95"] = 4.1, ["kbFrameMax"] = 850.2, ["kbFrames"] = 17600,
["grace"] = { ["login"] = 96.4, ["map"] = 31.5, ["gc"] = 88.2 },
["graceTop"] = { ["login"] = { ["top"] = "game.loaded", ["topMs"] = 60.2 }, ["map"] = { ["top"] = "map: labels", ["topMs"] = 16.3 },
["gc"] = { ["top"] = "game.telemetry", ["topMs"] = 87.9 } },
["slow"] = { { ["name"] = "map: labels", ["n"] = 3, ["max"] = 11.0 }, { ["name"] = "bench: regions", ["n"] = 2, ["max"] = 9.5 } },
["alloc"] = {
{ ["name"] = "game.observe", ["kbPerSec"] = 180.2, ["kbMax"] = 12.4, ["calls"] = 5400 }, -- [1]
{ ["name"] = "map: borders", ["kbPerSec"] = 60.1, ["kbMax"] = 850.2, ["calls"] = 40 }, -- [2]
{ ["name"] = "ui: view", ["kbPerSec"] = 2.5, ["kbMax"] = 0.3, ["calls"] = 18342 }, -- [3]
},
["gaps"] = {
{ ["job"] = "bench: regions", ["ms"] = 15.1, ["n"] = 1, ["stack"] = "(ran to the job's end)" }, -- bench: ignored by the gate
{ ["job"] = "map: borders", ["ms"] = 14.2, ["n"] = 3, ["stack"] = "[string \"@Interface/AddOns/MagicMapAtlas/ui/Borders.lua\"]:88: in function <Interface/AddOns/MagicMapAtlas/ui/Borders.lua:60>" }, -- [1]
},
["ledger"] = {
{ ["frame"] = 9300, ["ms"] = 9.1, ["top"] = "game.observe", ["topMs"] = 8.2, ["events"] = {
{ ["f"] = 9300, ["ms"] = 405010, ["k"] = "spike", ["d"] = { ["ms"] = 9.1, ["top"] = "game.observe", ["topMs"] = 8.2, ["alloc"] = "game.observe", ["allocKb"] = 12.4 } }, -- [1]
} }, -- [1]
{ ["frame"] = 9118, ["ms"] = 11.2, ["top"] = "map: borders", ["topMs"] = 10.4, ["events"] = {
{ ["f"] = 9109, ["ms"] = 402250, ["k"] = "layout", ["d"] = { ["e"] = "start", ["layer"] = "borders", ["inst"] = 0, ["zoom"] = 384 } }, -- [1]
{ ["f"] = 9118, ["ms"] = 402398, ["k"] = "layout", ["d"] = { ["e"] = "end", ["layer"] = "borders", ["ms"] = 22.3, ["regions"] = 1012 } }, -- [2]
{ ["f"] = 9118, ["ms"] = 402398, ["k"] = "swap", ["d"] = { ["layer"] = "borders", ["ms"] = 6.2, ["live"] = 1012, ["parked"] = 0, ["x"] = -12, ["y"] = 40, ["scale"] = 1 } }, -- [3]
{ ["f"] = 9118, ["ms"] = 402399, ["k"] = "gap", ["d"] = { ["job"] = "map: borders", ["ms"] = 14.2, ["n"] = 1 } }, -- [4]
{ ["f"] = 9118, ["ms"] = 402399, ["k"] = "spike", ["d"] = { ["ms"] = 11.2, ["top"] = "map: borders", ["topMs"] = 10.4, ["alloc"] = "map: borders", ["allocKb"] = 850.2 } }, -- [5]
} }, -- [2]
{ ["frame"] = 9120, ["ms"] = 8.4, ["top"] = "map: borders", ["topMs"] = 7.9, ["events"] = {} }, -- [3]
},
["byState"] = {
["small"] = { ["frames"] = 12000, ["p50"] = 0.25, ["p95"] = 0.7, ["p99"] = 3.9, ["max"] = 9.1,
	["client"] = { ["p50"] = 7, ["p95"] = 8.5, ["p99"] = 12, ["max"] = 31.5 } },
["zoom"] = { ["frames"] = 900, ["p50"] = 0.6, ["p95"] = 5.4, ["p99"] = 9.8, ["max"] = 11.2,
	["client"] = { ["p50"] = 7.5, ["p95"] = 16.5, ["p99"] = 24, ["max"] = 40 } },
["closed"] = { ["frames"] = 4990, ["p50"] = 0.05, ["p95"] = 0.1, ["p99"] = 0.2, ["max"] = 0.4 },
["drag"] = { ["frames"] = 610, ["p50"] = 0.3, ["p95"] = 0.9, ["p99"] = 2.4, ["max"] = 6.1 },
["big"] = { ["frames"] = 380, ["p50"] = 0.35, ["p95"] = 0.9, ["p99"] = 3.2, ["max"] = 7.7 },
},
},
["kept"] = {
{ ["f"] = 9200, ["ms"] = 404000, ["k"] = "taint", ["d"] = { ["e"] = "blocked", ["fn"] = "Minimap:Hide()" } }, -- [1]
{ ["f"] = 610, ["ms"] = 10200, ["k"] = "art", ["d"] = "redbutton-expand-c60" }, -- [2]
{ ["f"] = 9410, ["ms"] = 406020, ["k"] = "sensor", ["d"] = { ["e"] = "blind", ["probes"] = 96 } }, -- [3]
},
["stats"] = {
["layout tiles"] = { ["n"] = 40, ["ms"] = 11.4, ["regions"] = 36 },
["layout borders"] = { ["n"] = 38, ["ms"] = 22.3, ["regions"] = 1012 },
["blips"] = { ["n"] = 210, ["sweep"] = 211, ["blips"] = 7, ["yd"] = 233 },
["swap tiles"] = { ["n"] = 40, ["ms"] = 0.4, ["live"] = 36, ["parked"] = 0, ["x"] = 33012, ["y"] = 25510, ["scale"] = 1.3, ["lag"] = 0 },
["swap borders"] = { ["n"] = 38, ["ms"] = 6.2, ["live"] = 1012, ["parked"] = 0, ["x"] = 31990, ["y"] = 25100, ["scale"] = 1.3, ["lag"] = 0 },
},
["bench"] = {
["1.60.1.70374"] = { ["build"] = "1.60.1.70374", ["t"] = 1791993700, ["ops"] = {
["CreateLine"] = { ["n"] = 1000, ["ms"] = 21.0, ["us"] = 21.0 },
["canvas.SetScale@1000live"] = { ["n"] = 100, ["ms"] = 200, ["us"] = 2000 },
["SetParent.park"] = { ["n"] = 1000, ["ms"] = 4.2, ["us"] = 4.2 },
} },
},
["zones"] = {
"Elwynn Forest", -- [1]
"Westfall", -- [2]
},
}, -- [2]
},
["errors"] = {
["ui.tiles.step: Interface/AddOns/MagicMapAtlas/ui/Tiles.lua:88: attempt to index local 'tile' (a nil value)"] = {
["name"] = "ui.tiles.step",
["msg"] = "Interface/AddOns/MagicMapAtlas/ui/Tiles.lua:88: attempt to index local 'tile' (a nil value)",
["stack"] = "[string \"@Interface/AddOns/MagicMapAtlas/ui/Tiles.lua\"]:88: in function <Interface/AddOns/MagicMapAtlas/ui/Tiles.lua:80>\n[C]: in function `xpcall'\n[string \"@Interface/AddOns/MagicMapAtlas/runtime/Runtime.lua\"]:41: in function <Interface/AddOns/MagicMapAtlas/runtime/Runtime.lua:38>\n[string \"@Interface/AddOns/MagicMapAtlas/runtime/Runtime.lua\"]:120: in function <Interface/AddOns/MagicMapAtlas/runtime/Runtime.lua:110>\n[string \"@Interface/AddOns/Blizzard_SharedXMLBase/Mixin.lua\"]:12: in function <...>",
["count"] = 37,
["first"] = 1791994100,
["last"] = 1791995020,
["version"] = "7aa8b30-dirty",
["session"] = 2,
},
},
["marks"] = {
{
["kind"] = "error",
["note"] = "ui.tiles.step: Interface/AddOns/MagicMapAtlas/ui/Tiles.lua:88: attempt to index local 'tile' (a nil value)",
["t"] = 1791994100,
["stamp"] = "101426_110820",
["session"] = 2,
["version"] = "7aa8b30-dirty",
["frame"] = 9120,
["state"] = {
["you"] = { ["inst"] = 0, ["col"] = 32.412, ["row"] = 48.207, ["facing"] = 1.57 },
["zone"] = "Westfall",
["subzone"] = "Sentinel Hill",
["map"] = { ["shown"] = true, ["inst"] = 0, ["cx"] = 32.4, ["cy"] = 48.2, ["zoom"] = 3.5, ["follow"] = false, ["w"] = 900, ["h"] = 640 },
["layers"] = {
{ ["name"] = "tiles", ["busy"] = true, ["zoom"] = 3.5, ["region"] = "30,46-35,51" }, -- [1]
{ ["name"] = "borders", ["busy"] = false, ["zoom"] = 3, ["region"] = "29,45-36,52" }, -- [2]
},
},
["trace"] = {
{ ["f"] = 9101, ["ms"] = 402110, ["k"] = "cam", ["d"] = { ["e"] = "drag start", ["cx"] = 32.3, ["cy"] = 48.2, ["zoom"] = 3.5 } }, -- [1]
{ ["f"] = 9108, ["ms"] = 402231, ["k"] = "cam", ["d"] = { ["e"] = "drag end", ["cx"] = 32.4, ["cy"] = 48.2, ["zoom"] = 3.5 } }, -- [2]
{ ["f"] = 9109, ["ms"] = 402250, ["k"] = "layout", ["d"] = { ["e"] = "start", ["layer"] = "tiles", ["inst"] = 0, ["zoom"] = 3.5, ["c0"] = 30, ["r0"] = 46, ["c1"] = 35, ["r1"] = 51 } }, -- [3]
{ ["f"] = 9118, ["ms"] = 402398, ["k"] = "layout", ["d"] = { ["e"] = "end", ["layer"] = "tiles", ["ms"] = 11.4, ["regions"] = 36 } }, -- [4]
{ ["f"] = 9119, ["ms"] = 402415, ["k"] = "swap", ["d"] = { ["layer"] = "tiles", ["x"] = -12, ["y"] = 40, ["scale"] = 1 } }, -- [5]
{ ["f"] = 9120, ["ms"] = 402431, ["k"] = "error", ["d"] = "ui.tiles.step" }, -- [6]
},
["motion"] = {
{ ["f"] = 9118, ["ms"] = 402398, ["cx"] = 32.4, ["cy"] = 48.2, ["zoom"] = 3.5, ["px"] = 32.412, ["py"] = 48.207, ["w"] = 900, ["h"] = 640 }, -- [1]
{ ["f"] = 9119, ["ms"] = 402415, ["cx"] = 32.4, ["cy"] = 48.2, ["zoom"] = 3.5, ["px"] = 32.412, ["py"] = 48.207, ["w"] = 900, ["h"] = 640 }, -- [2]
{ ["f"] = 9120, ["ms"] = 402431, ["cx"] = 32.4, ["cy"] = 48.2, ["zoom"] = 3.5, ["px"] = 32.412, ["py"] = 48.207, ["w"] = 900, ["h"] = 640 }, -- [3]
},
}, -- [1]
{
["kind"] = "shot",
["note"] = "sentinel-384-small seam at sentinel hill",
["t"] = 1791994800,
["stamp"] = "101426_112000",
["session"] = 2,
["version"] = "7aa8b30-dirty",
["frame"] = 15002,
["state"] = {
["you"] = { ["inst"] = 0, ["col"] = 32.5, ["row"] = 48.3, ["facing"] = 0.2 },
["zone"] = "Westfall",
["subzone"] = "Sentinel Hill",
["map"] = { ["shown"] = true, ["inst"] = 0, ["cx"] = 32.6, ["cy"] = 48.1, ["zoom"] = 4, ["follow"] = true, ["w"] = 900, ["h"] = 640 },
["layers"] = {
{ ["name"] = "tiles", ["busy"] = false, ["zoom"] = 4, ["region"] = "31,47-34,50" }, -- [1]
},
},
["trace"] = {
{ ["f"] = 14990, ["ms"] = 1101002, ["k"] = "cam", ["d"] = { ["e"] = "follow on", ["cx"] = 32.99, ["cy"] = 48.1, ["zoom"] = 384 } }, -- [1]
{ ["f"] = 15002, ["ms"] = 1101200, ["k"] = "shot", ["d"] = "sentinel-384-small seam at sentinel hill" }, -- [2]
},
["motion"] = {
{ ["f"] = 14999, ["ms"] = 1101150, ["cx"] = 32.9990, ["cy"] = 48.1, ["zoom"] = 384, ["px"] = 32.9990, ["py"] = 48.1, ["w"] = 320, ["h"] = 203 }, -- [1]
{ ["f"] = 15000, ["ms"] = 1101166.7, ["cx"] = 32.9996, ["cy"] = 48.1, ["zoom"] = 384, ["px"] = 32.9996, ["py"] = 48.1, ["w"] = 320, ["h"] = 203 }, -- [2]
{ ["f"] = 15001, ["ms"] = 1101200, ["cx"] = 33.0002, ["cy"] = 48.1, ["zoom"] = 384, ["px"] = 33.0002, ["py"] = 48.1, ["w"] = 320, ["h"] = 203 }, -- [3]
{ ["f"] = 15002, ["ms"] = 1101216.7, ["cx"] = 33.0008, ["cy"] = 48.1, ["zoom"] = 384, ["px"] = 33.0010, ["py"] = 48.1, ["w"] = 320, ["h"] = 203 }, -- [4]
},
["shot"] = { ["inst"] = 0, ["cx"] = 33.0002, ["cy"] = 48.1, ["zoom"] = 384, ["w"] = 320, ["h"] = 203, ["left"] = 1588, ["top"] = 1012,
["big"] = false, ["uiScale"] = 0.711, ["screenW"] = 2700, ["screenH"] = 1518.8 },
}, -- [2]
{
["kind"] = "taint",
["note"] = "blocked Minimap:Hide()",
["t"] = 1791994000,
["stamp"] = "101426_110640",
["session"] = 2,
["version"] = "7aa8b30-dirty",
["frame"] = 9200,
["state"] = { ["you"] = { ["inst"] = 0, ["col"] = 32.4, ["row"] = 48.2, ["facing"] = 1.5 }, ["zone"] = "Westfall", ["subzone"] = "Sentinel Hill" },
["trace"] = {
{ ["f"] = 9200, ["ms"] = 404000, ["k"] = "taint", ["d"] = { ["e"] = "blocked", ["fn"] = "Minimap:Hide()" } }, -- [1]
},
}, -- [3]
},
},
["validation"] = {
["on"] = true,
["samples"] = 640,
["dropped"] = 0,
["counts"] = {
["subzone"] = 12,
["walk"] = 3,
},
["log"] = {
{ ["t"] = 1791994200, ["inst"] = 0, ["col"] = 32.412, ["row"] = 48.207, ["kind"] = "subzone", ["atlas"] = "", ["game"] = "Sentinel Hill" }, -- [1]
{ ["t"] = 1791994260, ["inst"] = 0, ["col"] = 32.5, ["row"] = 48.3, ["kind"] = "subzone", ["atlas"] = "", ["game"] = "Sentinel Hill" }, -- [2]
{ ["t"] = 1791994400, ["inst"] = 0, ["col"] = 33.1, ["row"] = 47.9, ["kind"] = "walk", ["atlas"] = "0", ["game"] = "on ground: not blocked (0)" }, -- [3]
},
},
}
