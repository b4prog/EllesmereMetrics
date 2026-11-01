-- tests/test_mana_regen.lua
-- EllesmereMetrics_ManaRegen: formatting, event-driven refreshes, secret and
-- invalid values, and characters without mana.

local testing = require("testing")
local wow = require("wow")

local test, equal, truthy = testing.test, testing.equal, testing.truthy
local contains, excludes = testing.contains, testing.excludes
local unpack = table.unpack or unpack

local NAME = "EllesmereMetrics_ManaRegen"
local COMBAT = wow.Restriction.Combat
local INACTIVE, ACTIVATING = wow.RestrictionState.Inactive, wow.RestrictionState.Activating

-- A loaded client whose broker has read (normal, casting) after login.
local function LoadWithRates(normal, casting)
	local client = wow.Load()
	client.normalRegen, client.castingRegen = normal, casting
	client:Fire("PLAYER_ENTERING_WORLD", true, false)
	client:NextFrame()
	return client, client:Broker(NAME)
end

test("shows the placeholder and reads nothing before login", function()
	local client = wow.Load()
	equal(client:Broker(NAME).text, "--")
	equal(client.calls.GetManaRegen, nil, "GetManaRegen calls")
	contains(client:TooltipText(NAME), "not reported usable regeneration rates")
end)

test("publishes both rates on the frame after PLAYER_ENTERING_WORLD", function()
	local client = wow.Load()
	client.normalRegen, client.castingRegen = 85.24, 34.46
	client:Fire("PLAYER_ENTERING_WORLD", true, false)
	equal(client:Broker(NAME).text, "--", "the read waits for the next frame")
	client:NextFrame()
	equal(client:Broker(NAME).text, "85.2/s | 34.5/s")
end)

test("formats each rate with one decimal", function()
	local cases = {
		{ 0, 0, "0.0/s | 0.0/s" },
		{ 5, 2.5, "5.0/s | 2.5/s" },
		{ 1234.56, 0.04, "1234.6/s | 0.0/s" },
	}
	for _, case in ipairs(cases) do
		local _, broker = LoadWithRates(case[1], case[2])
		equal(broker.text, case[3])
	end
end)

test("explains both rates in the tooltip", function()
	local client = LoadWithRates(85.24, 34.46)
	local text, rows = client:TooltipText(NAME)
	equal(rows[1], "Mana Regeneration", "title")
	contains(text, "Not casting\t85.2 mana/s")
	contains(text, "While casting\t34.5 mana/s")
	contains(text, "five-second rule")
	contains(text, "not a measurement")
end)

local REFRESH_EVENTS = {
	{ "UNIT_STATS", "player" },
	{ "UNIT_AURA", "player", {} },
	{ "PLAYER_EQUIPMENT_CHANGED", 16, true },
	{ "SPELLS_CHANGED" },
	{ "ADDON_RESTRICTION_STATE_CHANGED", COMBAT, INACTIVE },
	{ "PLAYER_ENTERING_WORLD", false, false },
}

for _, event in ipairs(REFRESH_EVENTS) do
	test("reads the rates again on " .. event[1], function()
		local client, broker = LoadWithRates(10, 2)
		client.normalRegen, client.castingRegen = 20, 4
		client:Fire(unpack(event))
		client:NextFrame()
		equal(broker.text, "20.0/s | 4.0/s")
	end)
end

test("ignores unit events about other units", function()
	local client, broker = LoadWithRates(10, 2)
	client.normalRegen = 20
	client:Fire("UNIT_AURA", "target", {})
	client:Fire("UNIT_STATS", "party1")
	equal(#client.timers, 0, "queued reads")
	client:NextFrame()
	equal(broker.text, "10.0/s | 2.0/s")
end)

test("coalesces a burst of events into one read on the next frame", function()
	local client, broker = LoadWithRates(10, 2)
	local reads = client.calls.GetManaRegen
	client.normalRegen = 12
	for slot = 1, 3 do
		client:Fire("PLAYER_EQUIPMENT_CHANGED", slot, true)
	end
	client:Fire("UNIT_STATS", "player")
	client:Fire("UNIT_AURA", "player", {})
	equal(#client.timers, 1, "queued reads")
	client:NextFrame()
	equal(client.calls.GetManaRegen, reads + 1, "GetManaRegen calls")
	equal(broker.text, "12.0/s | 2.0/s")
end)

test("does not republish unchanged rates", function()
	local client = LoadWithRates(10, 2)
	local watcher = client:WatchLikeDataBars(NAME)
	local writes = #client:Writes(NAME)
	client:Fire("UNIT_AURA", "player", {})
	client:NextFrame()
	client:Fire("UNIT_STATS", "player")
	client:NextFrame()
	equal(#client:Writes(NAME), writes, "attribute assignments")
	equal(watcher.repaints, 0, "DataBars repaints")
end)

test("repaints a DataBars block once per change", function()
	local client, broker = LoadWithRates(10, 2)
	local watcher = client:WatchLikeDataBars(NAME)
	client.normalRegen = 11
	client:Fire("UNIT_AURA", "player", {})
	client:NextFrame()
	equal(broker.text, "11.0/s | 2.0/s")
	equal(watcher.repaints, 1, "DataBars repaints")
end)

test("hides the rates while the game returns secrets", function()
	local client = wow.Load()
	client.normalRegen, client.castingRegen = wow.Secret(), wow.Secret()
	client:Fire("PLAYER_ENTERING_WORLD", false, true)
	client:NextFrame()
	equal(client:Broker(NAME).text, "--")
	local text = client:TooltipText(NAME)
	contains(text, "hiding character statistics")
	excludes(text, "mana/s")
end)

test("treats one secret rate as hiding both", function()
	local secret = wow.Secret()
	for _, rates in ipairs({ { secret, 34.5 }, { 85.2, secret } }) do
		local client, broker = LoadWithRates(rates[1], rates[2])
		equal(broker.text, "--")
		truthy(client.checked[secret], "the secret went through issecretvalue")
	end
end)

test("drops the last readable rates once they turn secret", function()
	local client, broker = LoadWithRates(85.2, 34.5)
	client.normalRegen, client.castingRegen = wow.Secret(), wow.Secret()
	client:Fire("UNIT_AURA", "player", {})
	client:NextFrame()
	equal(broker.text, "--")
	excludes(client:TooltipText(NAME), "85.2")
end)

test("reads the settled state after an activating restriction", function()
	local client, broker = LoadWithRates(85.2, 34.5)
	local reads = client.calls.GetManaRegen
	-- The restriction is enforced only once this dispatch has finished.
	client:Fire("ADDON_RESTRICTION_STATE_CHANGED", COMBAT, ACTIVATING)
	equal(client.calls.GetManaRegen, reads, "nothing is read during the dispatch")
	client.normalRegen, client.castingRegen = wow.Secret(), wow.Secret()
	client:NextFrame()
	equal(broker.text, "--")
end)

test("restores the rates when the restriction lifts", function()
	local client, broker = LoadWithRates(wow.Secret(), wow.Secret())
	equal(broker.text, "--")
	client.normalRegen, client.castingRegen = 85.2, 34.5
	client:Fire("ADDON_RESTRICTION_STATE_CHANGED", COMBAT, INACTIVE)
	client:NextFrame()
	equal(broker.text, "85.2/s | 34.5/s")
	excludes(client:TooltipText(NAME), "hiding")
end)

test("rejects rates that are not finite numbers", function()
	local invalid = {
		{ nil, 1 }, { 1, nil }, { "85", 1 }, { 0 / 0, 1 }, { math.huge, 1 }, { 1, -math.huge },
	}
	for _, rates in ipairs(invalid) do
		local client, broker = LoadWithRates(rates[1], rates[2])
		equal(broker.text, "--")
		contains(client:TooltipText(NAME), "not reported usable regeneration rates")
	end
end)

test("shows No mana for characters without a mana pool", function()
	local client = wow.Load()
	client.maxMana = 0
	client:Fire("PLAYER_ENTERING_WORLD", true, false)
	client:NextFrame()
	equal(client:Broker(NAME).text, "No mana")
	equal(client.lastArgs.UnitPowerMax[1], "player", "unit")
	equal(client.lastArgs.UnitPowerMax[2], 0, "power type (Enum.PowerType.Mana)")
	local text = client:TooltipText(NAME)
	contains(text, "does not use mana")
	excludes(text, "mana/s")
end)

test("keeps reading the rates when the mana pool size is secret", function()
	local client = wow.Load()
	client.maxMana = wow.Secret()
	client.normalRegen, client.castingRegen = 12, 3
	client:Fire("PLAYER_ENTERING_WORLD", true, false)
	client:NextFrame()
	equal(client:Broker(NAME).text, "12.0/s | 3.0/s")
	truthy(client.checked[client.maxMana], "the pool size went through issecretvalue")
end)

test("leaves the resting broker alone", function()
	local client = LoadWithRates(10, 2)
	local restingReads = client.calls.IsResting
	client:Fire("UNIT_AURA", "player", {})
	client:Fire("ADDON_RESTRICTION_STATE_CHANGED", COMBAT, INACTIVE)
	client:NextFrame()
	equal(client.calls.IsResting, restingReads, "IsResting calls")
	truthy(client:Broker("EllesmereMetrics_Resting"), "resting broker still registered")
end)
