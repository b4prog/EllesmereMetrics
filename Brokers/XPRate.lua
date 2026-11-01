-- Brokers\XPRate.lua
-- EllesmereMetrics_XPRate: the experience gained per hour this session and the
-- time to the next level at that pace, shown as "4.08k XP/h . 1h12m" (with a
-- middle dot as the separator).
--
-- A session starts at login or /reload, and again when XP gains are turned back
-- on. The pace is the XP gained since then divided by the time elapsed, so time
-- without XP lowers it; it shows once WARMUP_SECONDS have passed. Both numbers
-- move with time alone, so besides the XP events a ticker refreshes them every
-- TICK_SECONDS while the character can gain XP. UnitXP, UnitXPMax and UnitLevel
-- carry no secret-value predicate on WoW Forever 1.60.1.

local _, ns = ...

local C_PlayerInfo = C_PlayerInfo
local C_Timer = C_Timer
local GetMaxLevelForPlayerExpansion = GetMaxLevelForPlayerExpansion
local GetTime = GetTime
local UnitLevel = UnitLevel
local UnitXP = UnitXP
local UnitXPMax = UnitXPMax
local floor = math.floor
local format = string.format

local ICON = "Interface\\Icons\\INV_Misc_PocketWatch_01"
local TICK_SECONDS = 1
local WARMUP_SECONDS = 60
-- " . " with a UTF-8 middle dot, written as escapes so the file stays ASCII.
local SEPARATOR = " \194\183 "
local RATE_TEXT = "%s XP/h" .. SEPARATOR .. "%s"
local WARMUP_TEXT = format(RATE_TEXT, ns.PLACEHOLDER_TEXT, ns.PLACEHOLDER_TEXT)
local PAUSED_TEXT = { maxLevel = "Max level", xpOff = "XP off" }
local STATE_NOTE = {
	waiting = "The session starts when you enter the world.",
	maxLevel = "This character is at the maximum level.",
	xpOff = "Experience gains are turned off for this character.",
}
local SESSION_NOTE = "Average since you logged in, reloaded the UI or turned XP gains back on."
	.. " Time without XP lowers it; /reload starts a new session."
local WARMUP_NOTE = "The rate appears once the session is a minute old."
-- Three significant digits; a threshold is where the rounded value reaches its unit.
local UNITS = {
	{ threshold = 999500, size = 1e6, suffix = "M" },
	{ threshold = 999.5, size = 1e3, suffix = "k" },
}
local DECIMAL_FORMATS = { [0] = "%.0f%s", "%.1f%s", "%.2f%s" }

-- "waiting" until the first read, then "tracking", "maxLevel" or "xpOff".
local state = "waiting"
local sessionStart -- GetTime() when the session started; nil while none runs
local gained = 0 -- XP gained this session, level-ups included
local lastXP, lastMax, lastLevel
local ticker
local shownText = ns.PLACEHOLDER_TEXT

-- 850, 4.08k, 40.8k, 408k, 1.23M.
local function Abbreviate(amount)
	for i = 1, #UNITS do
		local unit = UNITS[i]
		if amount >= unit.threshold then
			local value = amount / unit.size
			local decimals = value < 9.995 and 2 or value < 99.95 and 1 or 0
			return format(DECIMAL_FORMATS[decimals], value, unit.suffix)
		end
	end
	return format("%.0f", amount)
end

-- <1m, 45m, 1h12m, 1d3h.
local function FormatDuration(seconds)
	local minutes = floor(seconds / 60 + 0.5)
	if minutes < 1 then return "<1m" end
	if minutes < 60 then return format("%dm", minutes) end
	local hours = floor(minutes / 60)
	if hours < 24 then return format("%dh%dm", hours, minutes % 60) end
	return format("%dd%dh", floor(hours / 24), hours % 24)
end

-- XP per hour this session, or nil during the warm-up.
local function XPPerHour(now)
	local elapsed = now - sessionStart
	if elapsed < WARMUP_SECONDS then return nil end
	return gained * 3600 / elapsed
end

local function TimeToLevel(rate)
	if not rate or rate <= 0 then return ns.PLACEHOLDER_TEXT end
	return FormatDuration((UnitXPMax("player") - UnitXP("player")) / rate * 3600)
end

local function RateText(now)
	local rate = XPPerHour(now)
	if not rate then return WARMUP_TEXT end
	return format(RATE_TEXT, Abbreviate(rate), TimeToLevel(rate))
end

local function ShowTooltip(tooltip)
	tooltip:AddLine("XP Rate")
	if state ~= "tracking" then
		ns.AddNote(tooltip, STATE_NOTE[state])
		return
	end
	local now = GetTime()
	local rate = XPPerHour(now)
	tooltip:AddDoubleLine("XP per hour", rate and Abbreviate(rate) or ns.PLACEHOLDER_TEXT, 1, 1, 1, 1, 1, 1)
	tooltip:AddDoubleLine("Next level in", TimeToLevel(rate), 1, 1, 1, 1, 1, 1)
	tooltip:AddDoubleLine("XP this session", format("%.0f", gained), 1, 1, 1, 1, 1, 1)
	tooltip:AddDoubleLine("Session length", FormatDuration(now - sessionStart), 1, 1, 1, 1, 1, 1)
	tooltip:AddLine(" ")
	ns.AddNote(tooltip, rate and SESSION_NOTE or WARMUP_NOTE)
end

local dataobj = ns.NewBroker("EllesmereMetrics_XPRate", {
	label = "XP Rate",
	text = ns.PLACEHOLDER_TEXT,
	icon = ICON,
	OnTooltipShow = ShowTooltip,
})
if not dataobj then return end

local function Publish(text)
	if text == shownText then return end
	shownText = text
	dataobj.text = text
end

local function StartSession()
	sessionStart, gained = GetTime(), 0
	lastXP, lastMax, lastLevel = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
end

-- Adds the XP gained since the last reading. A level-up adds what the old level
-- still needed plus the XP into the new one. A lower reading at the same level is
-- taken mid level-up, before UnitLevel changes, and waits for the next reading.
local function TrackXP()
	local xp, level = UnitXP("player"), UnitLevel("player")
	if level == lastLevel then
		if xp < lastXP then return end
		gained = gained + xp - lastXP
	elseif level > lastLevel then
		gained = gained + lastMax - lastXP + xp
	end
	lastXP, lastMax, lastLevel = xp, UnitXPMax("player"), level
end

local function StopTicker()
	if not ticker then return end
	ticker:Cancel()
	ticker = nil
end

-- No session runs at the maximum level or with XP gains off: the text says why,
-- and the ticker stops, since nothing then changes with time.
local function Pause(reason)
	StopTicker()
	state, sessionStart = reason, nil
	Publish(PAUSED_TEXT[reason])
end

-- Reads the game and refreshes the text: on the frame after an event, and on
-- every tick while a session runs.
local function Update()
	if UnitLevel("player") >= GetMaxLevelForPlayerExpansion() then
		Pause("maxLevel")
		return
	end
	if C_PlayerInfo.IsXPUserDisabled() then
		Pause("xpOff")
		return
	end
	ticker = ticker or C_Timer.NewTicker(TICK_SECONDS, Update)
	if sessionStart then
		TrackXP()
	else
		StartSession()
	end
	state = "tracking"
	Publish(RateText(GetTime()))
end

-- XP events read on the next frame, once a level-up has settled: UnitLevel can
-- still report the old level while PLAYER_XP_UPDATE is dispatched.
local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", ns.NextFrameUpdater(Update))
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterUnitEvent("PLAYER_XP_UPDATE", "player")
eventFrame:RegisterEvent("PLAYER_LEVEL_UP")
-- XP gains turned off or back on: no tick runs while they are off.
eventFrame:RegisterEvent("DISABLE_XP_GAIN")
eventFrame:RegisterEvent("ENABLE_XP_GAIN")
