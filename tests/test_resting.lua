-- tests/test_resting.lua
-- EllesmereMetrics_Resting: initial state, entering and leaving resting areas,
-- and the line between resting areas and rested XP.

local testing = require("testing")
local wow = require("wow")

local test, equal, truthy = testing.test, testing.equal, testing.truthy
local contains = testing.contains

local NAME = "EllesmereMetrics_Resting"

-- A loaded client whose broker has read `resting` at login.
local function LoadWithStatus(resting)
	local client = wow.Load()
	client.resting = resting
	client:Fire("PLAYER_ENTERING_WORLD", true, false)
	return client, client:Broker(NAME)
end

local function Shade(broker)
	return broker.iconR .. "," .. broker.iconG .. "," .. broker.iconB
end

test("shows the placeholder with a dimmed icon before login", function()
	local client = wow.Load()
	local broker = client:Broker(NAME)
	equal(broker.text, "--")
	equal(Shade(broker), "0.5,0.5,0.5", "icon tint")
	equal(client.calls.IsResting, nil, "IsResting calls")
	contains(client:TooltipText(NAME), "Status\t--")
end)

test("reads the initial status at PLAYER_ENTERING_WORLD", function()
	local _, resting = LoadWithStatus(true)
	equal(resting.text, "Resting")
	equal(Shade(resting), "1,1,1", "icon tint while resting")

	local _, outside = LoadWithStatus(false)
	equal(outside.text, "Not Resting")
	equal(Shade(outside), "0.5,0.5,0.5", "icon tint while not resting")
end)

test("switches to Resting on entering a resting area", function()
	local client, broker = LoadWithStatus(false)
	client.resting = true
	client:Fire("PLAYER_UPDATE_RESTING")
	equal(broker.text, "Resting", "updated during the event, no timer")
	equal(Shade(broker), "1,1,1", "icon tint")
	contains(client:TooltipText(NAME), "Status\tResting")
end)

test("switches to Not Resting on leaving a resting area", function()
	local client, broker = LoadWithStatus(true)
	client.resting = false
	client:Fire("PLAYER_UPDATE_RESTING")
	equal(broker.text, "Not Resting")
	equal(Shade(broker), "0.5,0.5,0.5", "icon tint")
	contains(client:TooltipText(NAME), "Status\tNot Resting")
end)

test("uses no timers", function()
	local client = LoadWithStatus(false)
	client:NextFrame() -- the mana broker's login read
	client.resting = true
	client:Fire("PLAYER_UPDATE_RESTING")
	equal(#client.timers, 0, "queued timers")
end)

test("does not republish an unchanged status", function()
	local client = LoadWithStatus(true)
	local watcher = client:WatchLikeDataBars(NAME)
	local writes = #client:Writes(NAME)
	client:Fire("PLAYER_UPDATE_RESTING")
	client:Fire("PLAYER_ENTERING_WORLD", false, false)
	equal(#client:Writes(NAME), writes, "attribute assignments")
	equal(watcher.repaints, 0, "DataBars repaints")
end)

test("repaints a DataBars block when the status changes", function()
	local client = LoadWithStatus(false)
	local watcher = client:WatchLikeDataBars(NAME)
	client.resting = true
	client:Fire("PLAYER_UPDATE_RESTING")
	truthy(watcher.repaints > 0, "DataBars repaints")
end)

test("accepts the legacy 1/nil return values", function()
	local _, legacyTrue = LoadWithStatus(1)
	equal(legacyTrue.text, "Resting")
	local _, legacyNil = LoadWithStatus(nil)
	equal(legacyNil.text, "Not Resting")
end)

test("follows IsResting, not the rested XP the character has", function()
	local client = wow.Load()
	client.resting = false
	client.restedXP = 5000
	client.restState = 1
	client:Fire("PLAYER_ENTERING_WORLD", true, false)
	equal(client:Broker(NAME).text, "Not Resting")
	equal(client.calls.GetXPExhaustion, nil, "GetXPExhaustion calls")
	equal(client.calls.GetRestState, nil, "GetRestState calls")
end)

test("says in the tooltip what the indicator does not show", function()
	local client = LoadWithStatus(true)
	local text, rows = client:TooltipText(NAME)
	equal(rows[1], "Resting Area", "title")
	contains(text, "Inns and major cities")
	contains(text, "not how much rested XP you already have")
end)

test("leaves the mana broker alone", function()
	local client = LoadWithStatus(false)
	client:NextFrame()
	local manaReads = client.calls.GetManaRegen
	client.resting = true
	client:Fire("PLAYER_UPDATE_RESTING")
	client:NextFrame()
	equal(client.calls.GetManaRegen, manaReads, "GetManaRegen calls")
end)
