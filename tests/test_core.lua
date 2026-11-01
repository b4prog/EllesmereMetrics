-- tests/test_core.lua
-- Addon metadata, LibDataBroker registration and the sandbox rules every
-- broker shares.

local testing = require("testing")
local wow = require("wow")

local test, equal, truthy, contains = testing.test, testing.equal, testing.truthy, testing.contains

local MANA = "EllesmereMetrics_ManaRegen"
local RESTING = "EllesmereMetrics_Resting"

local function ReadFile(path)
	local handle = assert(io.open(path, "rb"))
	local content = handle:read("*a")
	handle:close()
	return content
end

test("the TOC targets WoW Forever 1.60.1 and requires EllesmereUI", function()
	local metadata, files = wow.ReadToc(wow.TOC_PATH)
	equal(metadata.Interface, "16001", "Interface")
	equal(metadata.Dependencies, "EllesmereUI", "Dependencies")
	equal(metadata.Title, "EllesmereMetrics", "Title")
	truthy((metadata.Version or ""):match("^%d+%.%d+%.%d+$"), "Version is MAJOR.MINOR.PATCH")
	equal(files[1], "Core.lua", "Core.lua loads first")
	equal(#files, 3, "TOC file count")
end)

test("runtime files are ASCII, LF-terminated and tab-indented", function()
	local _, files = wow.ReadToc(wow.TOC_PATH)
	files[#files + 1] = wow.TOC_PATH
	for _, path in ipairs(files) do
		local content = ReadFile(path)
		truthy(not content:find("[\128-\255]"), path .. " is ASCII")
		truthy(not content:find("\r", 1, true), path .. " uses LF line endings")
		truthy(not content:find("\n +%S"), path .. " indents with tabs")
		truthy(not content:find("[ \t]\n"), path .. " has no trailing whitespace")
		equal(content:sub(-1), "\n", path .. " ends with a newline")
	end
end)

test("registers both brokers under the names DataBars lists", function()
	local client = wow.Load()
	local names = {}
	for name in client.ldb:DataObjectIterator() do
		names[#names + 1] = name
	end
	table.sort(names)
	equal(table.concat(names, ", "), MANA .. ", " .. RESTING)

	for _, name in ipairs(names) do
		local broker = client:Broker(name)
		equal(broker.type, "data source", name .. " type")
		truthy(broker.icon:match("^Interface\\Icons\\"), name .. " uses stock icon art")
		equal(#broker.iconCoords, 4, name .. " icon crop")
		equal(type(broker.OnTooltipShow), "function", name .. " tooltip")
		equal(broker.text, "--", name .. " starts with the placeholder")
	end
	equal(client:Broker(MANA).label, "Mana Regen")
	equal(client:Broker(RESTING).label, "Resting Area")
	equal(#client.printed, 0, "nothing printed")
end)

test("defines no globals and reads only known APIs", function()
	-- The sandbox raises on any global write or unknown global read, so driving
	-- every event and tooltip without an error is the check.
	local client = wow.Load()
	client.normalRegen, client.castingRegen = 10, 2
	client:Fire("PLAYER_ENTERING_WORLD", true, false)
	client:Fire("PLAYER_UPDATE_RESTING")
	client:Fire("UNIT_AURA", "player", {})
	client:Fire("UNIT_STATS", "player")
	client:Fire("PLAYER_EQUIPMENT_CHANGED", 16, true)
	client:Fire("SPELLS_CHANGED")
	client:Fire("ADDON_RESTRICTION_STATE_CHANGED", wow.Restriction.Combat, wow.RestrictionState.Inactive)
	client:NextFrame()
	client:TooltipText(MANA)
	client:TooltipText(RESTING)
	equal(client:Broker(MANA).text, "10.0/s | 2.0/s")
	equal(client:Broker(RESTING).text, "Not Resting")
end)

test("warns once and sets nothing up without LibDataBroker-1.1", function()
	local client = wow.Load({ withoutLibDataBroker = true })
	equal(#client.printed, 1, "one message")
	contains(client.printed[1], "LibDataBroker-1.1")
	contains(client.printed[1], "EllesmereUI")
	equal(#client.frames, 0, "no event frames")
	equal(#client.timers, 0, "no timers")
end)

test("warns and leaves a broker name another addon took alone", function()
	local client = wow.Load({ takenBrokerNames = { RESTING } })
	equal(#client.printed, 1, "one message")
	contains(client.printed[1], RESTING)
	equal(client:Broker(RESTING).text, "taken", "the other addon's object is untouched")
	client:Fire("PLAYER_ENTERING_WORLD", true, false)
	client:Fire("PLAYER_UPDATE_RESTING")
	equal(client:Broker(RESTING).text, "taken", "and stays untouched")
	equal(#client.frames, 1, "only the mana broker listens for events")
end)

test("treats every value as readable on an engine without secrets", function()
	local client = wow.Load({ without = { "issecretvalue" } })
	client.normalRegen, client.castingRegen = 12, 3
	client:Fire("PLAYER_ENTERING_WORLD", true, false)
	client:NextFrame()
	equal(client:Broker(MANA).text, "12.0/s | 3.0/s")
end)
