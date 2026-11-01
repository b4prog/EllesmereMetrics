-- Brokers\Resting.lua
-- EllesmereMetrics_Resting: whether the character is in a resting area (an inn
-- or a major city), where rested XP builds up. IsResting() answers exactly that.
-- It is not the rested XP the character already has (GetXPExhaustion) nor the XP
-- bar's rest state (GetRestState), and it keeps working at maximum level.
--
-- IsResting carries no secret-value predicate on WoW Forever 1.60.1, and
-- PLAYER_UPDATE_RESTING fires on every change, so nothing is polled.

local _, ns = ...

local IsResting = IsResting

local ICON = "Interface\\Icons\\Spell_Nature_Sleep"
-- Icon shade while not resting. DataBars applies it only while the block's Icon
-- Color is left untouched, so the text alone must carry the state.
local DIMMED = 0.5
local RESTING_TEXT = "Resting"
local NOT_RESTING_TEXT = "Not Resting"
local AREA_NOTE = "Inns and major cities are resting areas, where your character builds up rested XP."
local SCOPE_NOTE = "This shows where you are, not how much rested XP you already have."

local resting -- nil until the first read

local function ShowTooltip(tooltip)
	tooltip:AddLine("Resting Area")
	if resting == nil then
		tooltip:AddDoubleLine("Status", ns.PLACEHOLDER_TEXT, 1, 1, 1, 1, 1, 1)
	elseif resting then
		tooltip:AddDoubleLine("Status", RESTING_TEXT, 1, 1, 1, 0.25, 1, 0.25)
	else
		tooltip:AddDoubleLine("Status", NOT_RESTING_TEXT, 1, 1, 1, 0.75, 0.75, 0.75)
	end
	tooltip:AddLine(" ")
	ns.AddNote(tooltip, AREA_NOTE)
	ns.AddNote(tooltip, SCOPE_NOTE)
end

local dataobj = ns.NewBroker("EllesmereMetrics_Resting", {
	label = "Resting Area",
	text = ns.PLACEHOLDER_TEXT,
	icon = ICON,
	iconR = DIMMED,
	iconG = DIMMED,
	iconB = DIMMED,
	OnTooltipShow = ShowTooltip,
})
if not dataobj then return end

local function Update()
	-- A plain boolean, so the change test compares like with like.
	local isResting = IsResting() and true or false
	if isResting == resting then return end
	resting = isResting
	local shade = isResting and 1 or DIMMED
	dataobj.text = isResting and RESTING_TEXT or NOT_RESTING_TEXT
	dataobj.iconR, dataobj.iconG, dataobj.iconB = shade, shade, shade
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", Update)
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_UPDATE_RESTING")
