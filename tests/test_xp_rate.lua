-- tests/test_xp_rate.lua
-- EllesmereMetrics_XPRate: the session pace, level-ups, the time to the next
-- level, the refresh ticker, and characters that cannot gain XP.

local testing = require("testing")
local wow = require("wow")

local test, equal, truthy = testing.test, testing.equal, testing.truthy
local contains, excludes = testing.contains, testing.excludes

local NAME = "EllesmereMetrics_XPRate"

-- The broker text for a pace and a time to level.
local function Text(rate, timeToLevel)
	return rate .. " XP/h \194\183 " .. timeToLevel
end

-- A client logged in at level 20 with `xp` of `xpMax`, its session started at 0.
local function LoggedIn(xp, xpMax)
	local client = wow.Load()
	client.level, client.xp, client.xpMax = 20, xp, xpMax
	client:Fire("PLAYER_ENTERING_WORLD", true, false)
	client:NextFrame()
	return client, client:Broker(NAME)
end

-- Sets the XP reading and delivers PLAYER_XP_UPDATE.
local function GainXP(client, xp)
	client.xp = xp
	client:Fire("PLAYER_XP_UPDATE", "player")
	client:NextFrame()
end

-- The pace shown after gaining `amount` XP in one hour.
local function HourlyPace(amount)
	local client, broker = LoggedIn(0, 1e9)
	GainXP(client, amount)
	client:Advance(3600)
	return broker.text:match("^(.-) XP/h")
end

-- The time to level shown at 3600 XP/h with `remaining` XP still to earn.
local function TimeToLevelFor(remaining)
	local client, broker = LoggedIn(0, 3600 + remaining)
	GainXP(client, 3600)
	client:Advance(3600)
	return broker.text:match("\194\183 (.+)$")
end

test("shows the placeholder and reads nothing before login", function()
	local client = wow.Load()
	equal(client:Broker(NAME).text, "--")
	equal(client.calls.UnitXP, nil, "UnitXP calls")
	equal(client:ActiveTickers(), 0, "tickers")
	contains(client:TooltipText(NAME), "starts when you enter the world")
end)

test("waits a minute before showing a pace", function()
	local client, broker = LoggedIn(2000, 7576)
	equal(broker.text, Text("--", "--"))
	GainXP(client, 2100)
	client:Advance(59)
	equal(broker.text, Text("--", "--"), "after 59 seconds")
	contains(client:TooltipText(NAME), "once the session is a minute old")
	client:Advance(1)
	equal(broker.text, Text("6.00k", "55m"), "after 60 seconds")
end)

test("shows the pace and the time to the next level", function()
	local client, broker = LoggedIn(2000, 7576)
	client:Advance(600)
	GainXP(client, 2680)
	equal(broker.text, Text("4.08k", "1h12m"))
end)

test("explains the session in the tooltip", function()
	local client = LoggedIn(2000, 7576)
	client:Advance(600)
	GainXP(client, 2680)
	local text, rows = client:TooltipText(NAME)
	equal(rows[1], "XP Rate", "title")
	contains(text, "XP per hour\t4.08k")
	contains(text, "Next level in\t1h12m")
	contains(text, "XP this session\t680")
	contains(text, "Session length\t10m")
	contains(text, "/reload starts a new session")
end)

test("shows 0 XP/h when no XP comes in", function()
	local client, broker = LoggedIn(2000, 7576)
	client:Advance(60)
	equal(broker.text, Text("0", "--"))
end)

test("counts the XP of a level-up", function()
	local client, broker = LoggedIn(7000, 7576)
	client.level, client.xpMax = 21, 8000
	GainXP(client, 300)
	client:Advance(3600)
	equal(broker.text, Text("876", "8h47m"))
end)

test("waits for a level-up to settle before counting it", function()
	local client, broker = LoggedIn(7000, 7576)
	GainXP(client, 300)
	client.level, client.xpMax = 21, 8000
	client:Fire("PLAYER_LEVEL_UP", 21)
	client:NextFrame()
	client:Advance(3600)
	equal(broker.text, Text("876", "8h47m"))
end)

test("keeps lowering the pace while no XP comes in", function()
	local client, broker = LoggedIn(2000, 7576)
	client:Advance(600)
	GainXP(client, 2680)
	client:Advance(600)
	equal(broker.text, Text("2.04k", "2h24m"))
end)

test("refreshes through a single one-second ticker", function()
	local client = LoggedIn(2000, 7576)
	equal(client:ActiveTickers(), 1, "tickers")
	equal(client.tickers[1].interval, 1, "interval")
	client:Fire("PLAYER_ENTERING_WORLD", false, false)
	GainXP(client, 2100)
	equal(client:ActiveTickers(), 1, "tickers after more events")
end)

test("does not republish an unchanged text", function()
	local client = LoggedIn(2000, 7576)
	local watcher = client:WatchLikeDataBars(NAME)
	local writes = #client:Writes(NAME)
	client:Advance(50)
	equal(#client:Writes(NAME), writes, "attribute assignments")
	equal(watcher.repaints, 0, "DataBars repaints")
end)

test("formats the pace with three significant digits", function()
	local cases = {
		{ 850, "850" }, { 999, "999" }, { 1000, "1.00k" }, { 4080, "4.08k" }, { 9996, "10.0k" },
		{ 40800, "40.8k" }, { 99960, "100k" }, { 408000, "408k" }, { 999600, "1.00M" }, { 1234567, "1.23M" },
	}
	for _, case in ipairs(cases) do
		equal(HourlyPace(case[1]), case[2], case[1] .. " XP in one hour")
	end
end)

test("formats the time to the next level", function()
	local cases = { { 20, "<1m" }, { 2700, "45m" }, { 4320, "1h12m" }, { 97200, "1d3h" } }
	for _, case in ipairs(cases) do
		equal(TimeToLevelFor(case[1]), case[2], case[1] .. " XP to go at 3600 XP/h")
	end
end)

test("shows Max level and never ticks at the maximum level", function()
	local client = wow.Load()
	client.level = 60
	client:Fire("PLAYER_ENTERING_WORLD", true, false)
	client:NextFrame()
	equal(client:Broker(NAME).text, "Max level")
	equal(client:ActiveTickers(), 0, "tickers")
	local text = client:TooltipText(NAME)
	contains(text, "maximum level")
	excludes(text, "XP per hour")
end)

test("stops the ticker on reaching the maximum level", function()
	local client, broker = LoggedIn(7000, 7576)
	client.level = 60
	client:Fire("PLAYER_LEVEL_UP", 60)
	client:NextFrame()
	equal(broker.text, "Max level")
	equal(client:ActiveTickers(), 0, "tickers")
end)

test("pauses while XP gains are off, then starts a new session", function()
	local client, broker = LoggedIn(2000, 7576)
	client:Advance(600)
	GainXP(client, 2680)
	client.xpDisabled = true
	client:Advance(10)
	equal(broker.text, "XP off")
	contains(client:TooltipText(NAME), "turned off")
	client.xpDisabled = false
	client:Advance(10)
	equal(broker.text, Text("--", "--"), "a new session warms up")
	client:Advance(60)
	equal(broker.text, Text("0", "--"), "the earlier XP no longer counts")
end)

test("ignores XP updates about other units", function()
	local client = LoggedIn(2000, 7576)
	client.xp = 2500
	client:Fire("PLAYER_XP_UPDATE", "party1")
	equal(#client.timers, 0, "queued reads")
end)

test("reads once for an XP update and a level-up in the same frame", function()
	local client = LoggedIn(7000, 7576)
	local reads = client.calls.UnitXP
	client.level, client.xp, client.xpMax = 21, 300, 8000
	client:Fire("PLAYER_XP_UPDATE", "player")
	client:Fire("PLAYER_LEVEL_UP", 21)
	equal(#client.timers, 1, "queued reads")
	client:NextFrame()
	truthy(client.calls.UnitXP > reads, "read on the next frame")
end)
