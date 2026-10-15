
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
["zones"] = {
"Elwynn Forest", -- [1]
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
{ ["f"] = 9101, ["ms"] = 402110, ["k"] = "cam", ["d"] = "drag start" }, -- [1]
{ ["f"] = 9108, ["ms"] = 402231, ["k"] = "cam", ["d"] = "drag end" }, -- [2]
{ ["f"] = 9109, ["ms"] = 402250, ["k"] = "layout", ["d"] = { "tiles", "start", ["region"] = "30,46-35,51" } }, -- [3]
{ ["f"] = 9118, ["ms"] = 402398, ["k"] = "layout", ["d"] = { "tiles", "end", ["ms"] = 11.4, ["regions"] = 36 } }, -- [4]
{ ["f"] = 9119, ["ms"] = 402415, ["k"] = "swap", ["d"] = { "tiles", ["x"] = -12, ["y"] = 40 } }, -- [5]
{ ["f"] = 9120, ["ms"] = 402431, ["k"] = "error", ["d"] = "ui.tiles.step" }, -- [6]
},
}, -- [1]
{
["kind"] = "shot",
["note"] = "seam at sentinel hill",
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
{ ["f"] = 14990, ["ms"] = 1101002, ["k"] = "cam", ["d"] = "follow on" }, -- [1]
{ ["f"] = 15002, ["ms"] = 1101200, ["k"] = "shot", ["d"] = "seam at sentinel hill" }, -- [2]
},
}, -- [2]
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
