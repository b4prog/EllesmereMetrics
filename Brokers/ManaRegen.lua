-- Brokers\ManaRegen.lua
-- EllesmereMetrics_ManaRegen: the mana regeneration rates GetManaRegen()
-- reports, in mana per second, shown as "<not casting>/s | <while casting>/s".
--
-- These are rates the game reports, not measured gain: which one applies depends
-- on the five-second rule (the casting rate holds for five seconds after mana is
-- spent), and mana itself is secret on WoW Forever, so actual gain cannot be
-- measured reliably. The broker does not try.
--
-- On WoW Forever both returns are SecretWhenUnitStatsRestricted: secret while
-- the game restricts unit stats, in combat at least. The broker then shows the
-- placeholder instead of the last readable rates, and reads again at every
-- ADDON_RESTRICTION_STATE_CHANGED.

local _, ns = ...

local C_Timer = C_Timer
local GetManaRegen = GetManaRegen
local UnitPowerMax = UnitPowerMax
local format = string.format
local huge = math.huge
local IsSecret = ns.IsSecret

local MANA = Enum.PowerType.Mana
local ICON = "Interface\\Icons\\Spell_Nature_ManaRegenTotem"
local RATES_TEXT = "%.1f/s | %.1f/s"
local RATE_TEXT = "%.1f mana/s"
local NO_MANA_TEXT = "No mana"
local RULE_NOTE = "Rates reported by the game, in mana per second. The casting rate applies for five"
	.. " seconds after you spend mana (the five-second rule)."
local RATE_NOTE = "They are rates, not a measurement of the mana you are gaining right now."
local RESTRICTED_NOTE = "The game is hiding character statistics right now, for example during combat."
	.. " The rates come back when the restriction ends."
local UNAVAILABLE_NOTE = "The game has not reported usable regeneration rates yet."
local NO_MANA_NOTE = "This character does not use mana."

-- "ready": both rates are readable numbers, kept in normalRegen/castingRegen.
-- "restricted": the game returned secrets. "unavailable": nothing usable yet.
-- "noMana": the character has no mana pool (Warriors and Rogues).
local status = "unavailable"
local normalRegen, castingRegen

-- Only for values that already passed IsSecret: comparing a secret raises.
local function IsFiniteNumber(value)
	return type(value) == "number" and value == value and value ~= huge and value ~= -huge
end

local function ReadRegen()
	local maxMana = UnitPowerMax("player", MANA)
	if not IsSecret(maxMana) and maxMana == 0 then
		return "noMana"
	end
	local normal, casting = GetManaRegen()
	if IsSecret(normal) or IsSecret(casting) then
		return "restricted"
	end
	if IsFiniteNumber(normal) and IsFiniteNumber(casting) then
		return "ready", normal, casting
	end
	return "unavailable"
end

local function FormatRate(rate)
	if rate then return format(RATE_TEXT, rate) end
	return ns.PLACEHOLDER_TEXT
end

local function ShowTooltip(tooltip)
	tooltip:AddLine("Mana Regeneration")
	if status == "noMana" then
		ns.AddNote(tooltip, NO_MANA_NOTE)
		return
	end
	tooltip:AddDoubleLine("Not casting", FormatRate(normalRegen), 1, 1, 1, 1, 1, 1)
	tooltip:AddDoubleLine("While casting", FormatRate(castingRegen), 1, 1, 1, 1, 1, 1)
	tooltip:AddLine(" ")
	if status == "ready" then
		ns.AddNote(tooltip, RULE_NOTE)
		ns.AddNote(tooltip, RATE_NOTE)
	elseif status == "restricted" then
		ns.AddNote(tooltip, RESTRICTED_NOTE)
	else
		ns.AddNote(tooltip, UNAVAILABLE_NOTE)
	end
end

local dataobj = ns.NewBroker("EllesmereMetrics_ManaRegen", {
	label = "Mana Regen",
	text = ns.PLACEHOLDER_TEXT,
	icon = ICON,
	OnTooltipShow = ShowTooltip,
})
if not dataobj then return end

local function Update()
	local newStatus, normal, casting = ReadRegen()
	if newStatus == status and normal == normalRegen and casting == castingRegen then return end
	status, normalRegen, castingRegen = newStatus, normal, casting
	if newStatus == "ready" then
		dataobj.text = format(RATES_TEXT, normal, casting)
	elseif newStatus == "noMana" then
		dataobj.text = NO_MANA_TEXT
	else
		dataobj.text = ns.PLACEHOLDER_TEXT
	end
end

local updateQueued = false

local function RunQueuedUpdate()
	updateQueued = false
	Update()
end

-- Each event queues one read for the next frame. That coalesces bursts (a gear
-- swap fires several of these events at once) and lets restriction edges settle:
-- an activating restriction is enforced only once the dispatch of its
-- ADDON_RESTRICTION_STATE_CHANGED has finished.
local function QueueUpdate()
	if updateQueued then return end
	updateQueued = true
	C_Timer.After(0, RunQueuedUpdate)
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", QueueUpdate)
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
-- Regeneration follows stats, gear, auras (some buffs change it without any stat
-- event) and talents.
eventFrame:RegisterUnitEvent("UNIT_STATS", "player")
eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
eventFrame:RegisterEvent("SPELLS_CHANGED")
-- Combat, encounter and map restrictions starting or ending.
eventFrame:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
