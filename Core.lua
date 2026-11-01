-- Core.lua
-- Shared plumbing for the brokers in Brokers\: the LibDataBroker-1.1 instance
-- EllesmereUI ships, the secret-value test, the next-frame updater and small
-- presentation helpers.

local ADDON_NAME, ns = ...

local C_Timer = C_Timer

-- EllesmereUI, the required dependency, embeds LibStub, CallbackHandler-1.0 and
-- LibDataBroker-1.1 and always loads first. The lookup is silent so a broken
-- install prints one clear message instead of raising an error per broker.
local LDB = LibStub and LibStub:GetLibrary("LibDataBroker-1.1", true)

-- Crops the border baked into Interface\Icons artwork.
local ICON_COORDS = { 0.08, 0.92, 0.08, 0.92 }
local NOTE_R, NOTE_G, NOTE_B = 0.75, 0.75, 0.75

-- WoW Forever runs the 12.x engine, where APIs guarded by addon restrictions
-- (combat, encounters, restricted maps) can return secret values. Addon code may
-- store a secret or hand it to an API that accepts one, but comparing it, doing
-- arithmetic on it, indexing it or testing a secret boolean raises an error, and
-- type() reports the underlying type, so it cannot detect one. issecretvalue is
-- the supported test; an engine without it has no secret values.
ns.IsSecret = issecretvalue or function() return false end

-- Shown wherever a value is not known yet or cannot be read right now.
ns.PLACEHOLDER_TEXT = "--"

local function Warn(message)
	print("|cffff6060" .. ADDON_NAME .. ":|r " .. message)
end

if not LDB then
	Warn("LibDataBroker-1.1 was not found. Install or update EllesmereUI.")
end

-- Registers a LibDataBroker data source and returns it, or nil when it cannot
-- be registered (the caller then sets nothing up). DataBars saves the name in
-- each Broker Plugin block, so a released name must never change.
function ns.NewBroker(name, attributes)
	if not LDB then return nil end
	attributes.type = "data source"
	attributes.iconCoords = ICON_COORDS
	local dataobj = LDB:NewDataObject(name, attributes)
	if not dataobj then
		Warn("another addon already registered the data broker " .. name .. ".")
	end
	return dataobj
end

-- Adds one grey, word-wrapped explanation line to a tooltip.
function ns.AddNote(tooltip, text)
	tooltip:AddLine(text, NOTE_R, NOTE_G, NOTE_B, true)
end

-- Returns a function that runs `update` once on the next frame, however often it
-- is called before then. As an OnEvent handler it turns a burst of events into a
-- single read, taken after the dispatch: a restriction announced by
-- ADDON_RESTRICTION_STATE_CHANGED is enforced only once that dispatch ends.
function ns.NextFrameUpdater(update)
	local queued = false
	local function Run()
		queued = false
		update()
	end
	return function()
		if queued then return end
		queued = true
		C_Timer.After(0, Run)
	end
end
