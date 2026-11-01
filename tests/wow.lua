-- tests/wow.lua
-- A stand-in for the parts of the WoW Forever client the addon touches: its API
-- functions, an event bus, C_Timer on a virtual clock, LibStub with
-- LibDataBroker-1.1, a GameTooltip-like recorder and secret values. wow.Load()
-- builds a fresh client and runs the addon's TOC files in it, so tests never
-- share state.

local wow = {}

wow.ADDON_NAME = "EllesmereMetrics"
wow.TOC_PATH = wow.ADDON_NAME .. ".toc"
wow.Restriction = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5 }
wow.RestrictionState = { Inactive = 0, Activating = 1, Active = 2 }

-- The client raises an error when a frame registers an unknown event, and so
-- does this mock. Add an event only once warcraft.wiki.gg lists it for Forever.
local KNOWN_EVENTS = {
	ADDON_RESTRICTION_STATE_CHANGED = true,
	DISABLE_XP_GAIN = true,
	ENABLE_XP_GAIN = true,
	PLAYER_ENTERING_WORLD = true,
	PLAYER_EQUIPMENT_CHANGED = true,
	PLAYER_LEVEL_UP = true,
	PLAYER_UPDATE_RESTING = true,
	PLAYER_XP_UPDATE = true,
	SPELLS_CHANGED = true,
	UNIT_AURA = true,
	UNIT_STATS = true,
}

-- Standard Lua the client also provides. Reading any other global that the mock
-- does not define (io, os, loadstring, a misspelled API...) fails the test.
local LUA_GLOBALS = {
	"assert", "error", "getmetatable", "ipairs", "next", "pairs", "pcall", "rawequal", "rawget",
	"rawset", "select", "setmetatable", "tonumber", "tostring", "unpack", "xpcall",
	"coroutine", "math", "string", "table",
}

-- Attributes an EllesmereUI DataBars "Broker Plugin" block repaints for.
local RENDERED_ATTRIBUTES = {
	text = true, value = true, suffix = true, label = true,
	icon = true, iconR = true, iconG = true, iconB = true, iconCoords = true,
}

-------------------------------------------------------------------------------
-- Secret values
-------------------------------------------------------------------------------
-- A secret is an empty table whose metamethods all raise, so arithmetic,
-- concatenation, ordering, indexing, calling or tostring() on one fails the test,
-- and the sandbox's type() reports the type it stands for, as the client does.
-- The mock is stricter than the client in one way (the client lets concatenation
-- and string.format build secret strings, which the addon never needs) and
-- weaker in another: plain Lua never consults a metamethod for `secret == 0`,
-- so that comparison returns false here instead of raising. To narrow that gap,
-- the client records every secret passed to issecretvalue (client.checked), so
-- tests can at least require the check; its order stays a review rule.

local secretKinds = setmetatable({}, { __mode = "k" })

local function Refuse(action)
	return function()
		error("attempt to " .. action .. " a secret value", 2)
	end
end

local SECRET_METATABLE = {
	__metatable = "secret",
	__index = Refuse("index"),
	__newindex = Refuse("index"),
	__call = Refuse("call"),
	__concat = Refuse("concatenate"),
	__len = Refuse("get the length of"),
	__unm = Refuse("perform arithmetic on"),
	__add = Refuse("perform arithmetic on"),
	__sub = Refuse("perform arithmetic on"),
	__mul = Refuse("perform arithmetic on"),
	__div = Refuse("perform arithmetic on"),
	__mod = Refuse("perform arithmetic on"),
	__pow = Refuse("perform arithmetic on"),
	__eq = Refuse("compare"),
	__lt = Refuse("compare"),
	__le = Refuse("compare"),
	__tostring = Refuse("convert"),
}

-- Returns a new secret standing for a value of the given type ("number" by default).
function wow.Secret(kind)
	local secret = setmetatable({}, SECRET_METATABLE)
	secretKinds[secret] = kind or "number"
	return secret
end

function wow.IsSecret(value)
	return secretKinds[value] ~= nil
end

local function CheckedText(text)
	if type(text) ~= "string" then
		error("tooltip text must be a plain string, got a " .. (wow.IsSecret(text) and "secret" or type(text)), 3)
	end
	return text
end

-------------------------------------------------------------------------------
-- LibStub and LibDataBroker-1.1
-------------------------------------------------------------------------------
-- Mirrors LibDataBroker-1.1 v1.1.4, the version EllesmereUI ships: a data object
-- is an empty proxy whose attributes live in a side table; assigning an equal
-- value is ignored, and any other assignment fires the
-- LibDataBroker_AttributeChanged callbacks. The mock also records every
-- assignment and refuses secrets, which the library would fail to compare.

local function NewLibDataBroker(client)
	local ldb = {}
	local objects, names, attributes, handlers = {}, {}, {}, {}

	local function Fire(event, ...)
		for _, handler in pairs(handlers[event] or {}) do
			handler(event, ...)
		end
	end

	local proxy = {
		__metatable = "access denied",
		__index = function(dataobj, key)
			return attributes[dataobj][key]
		end,
		__newindex = function(dataobj, key, value)
			local name = names[dataobj]
			if wow.IsSecret(value) then
				error("secret value assigned to " .. name .. "." .. tostring(key), 2)
			end
			local writes = client.writes[name]
			writes[#writes + 1] = { key = key, value = value }
			if attributes[dataobj][key] == value then return end
			attributes[dataobj][key] = value
			Fire("LibDataBroker_AttributeChanged", name, key, value, dataobj)
			Fire("LibDataBroker_AttributeChanged_" .. name, name, key, value, dataobj)
			Fire("LibDataBroker_AttributeChanged_" .. name .. "_" .. key, name, key, value, dataobj)
			Fire("LibDataBroker_AttributeChanged__" .. key, name, key, value, dataobj)
		end,
	}

	function ldb.NewDataObject(_, name, dataobj)
		if objects[name] then return nil end
		dataobj = dataobj or {}
		local stored = {}
		for key, value in pairs(dataobj) do
			stored[key] = value
		end
		for key in pairs(stored) do
			dataobj[key] = nil
		end
		attributes[dataobj], names[dataobj], objects[name] = stored, name, dataobj
		client.writes[name] = {}
		setmetatable(dataobj, proxy)
		Fire("LibDataBroker_DataObjectCreated", name, dataobj)
		return dataobj
	end

	function ldb.GetDataObjectByName(_, name)
		return objects[name]
	end

	function ldb.DataObjectIterator()
		return pairs(objects)
	end

	-- CallbackHandler-1.0 style: lib.RegisterCallback(owner, event, handler).
	function ldb.RegisterCallback(owner, event, handler)
		assert(type(handler) == "function", "the mock supports function handlers only")
		handlers[event] = handlers[event] or {}
		handlers[event][owner] = handler
	end

	return ldb
end

local function NewLibStub(libraries)
	local LibStub = {}
	function LibStub.GetLibrary(_, major, silent)
		local library = libraries[major]
		if not library and not silent then
			error("Cannot find a library instance of " .. tostring(major) .. ".", 2)
		end
		return library
	end
	return setmetatable(LibStub, { __call = LibStub.GetLibrary })
end

-------------------------------------------------------------------------------
-- Frames and events
-------------------------------------------------------------------------------

local function NewFrame(client)
	local frame = { events = {}, units = {}, scripts = {} }

	function frame:RegisterEvent(event)
		if not KNOWN_EVENTS[event] then
			error('Attempt to register unknown event "' .. tostring(event) .. '"', 2)
		end
		self.events[event] = true
		self.units[event] = nil
	end

	function frame:RegisterUnitEvent(event, ...)
		self:RegisterEvent(event)
		self.units[event] = { ... }
	end

	function frame:SetScript(script, handler)
		self.scripts[script] = handler
	end

	client.frames[#client.frames + 1] = frame
	return frame
end

local function Contains(list, value)
	for i = 1, #list do
		if list[i] == value then return true end
	end
	return false
end

-------------------------------------------------------------------------------
-- Timers
-------------------------------------------------------------------------------
-- C_Timer.After(0, ...) callbacks run at Client:NextFrame(). Tickers run on a
-- virtual clock, which is also what GetTime() returns: Client:Advance(seconds)
-- moves it forward and fires each ticker when it falls due. Creating more than
-- MAX_TICKERS running tickers fails the test, so a leak cannot hang the suite.

local MAX_TICKERS = 8

local function NewTimerApi(client)
	return {
		After = function(seconds, callback)
			assert(seconds == 0, "the mock only models next-frame timers")
			assert(type(callback) == "function", "C_Timer.After needs a function")
			client.timers[#client.timers + 1] = callback
		end,
		NewTicker = function(seconds, callback, iterations)
			assert(type(seconds) == "number" and seconds > 0, "C_Timer.NewTicker needs a positive interval")
			assert(type(callback) == "function", "C_Timer.NewTicker needs a function")
			assert(iterations == nil, "the mock only models endless tickers")
			assert(client:ActiveTickers() < MAX_TICKERS, "the addon keeps creating tickers")
			local ticker = { interval = seconds, callback = callback, dueAt = client.now + seconds }
			function ticker.Cancel(handle)
				handle.cancelled = true
			end
			client.tickers[#client.tickers + 1] = ticker
			return ticker
		end,
	}
end

-- The running ticker due first, at or before `limit`.
local function NextDueTicker(tickers, limit)
	local due
	for _, ticker in ipairs(tickers) do
		if not ticker.cancelled and ticker.dueAt <= limit and (not due or ticker.dueAt < due.dueAt) then
			due = ticker
		end
	end
	return due
end

-------------------------------------------------------------------------------
-- Client
-------------------------------------------------------------------------------

local Client = {}
Client.__index = Client

-- Fires an event at every frame registered for it. As in the engine, a unit
-- event reaches a frame only for the units passed to RegisterUnitEvent.
function Client:Fire(event, ...)
	local unit = ...
	for _, frame in ipairs(self.frames) do
		local units = frame.units[event]
		if frame.events[event] and (not units or Contains(units, unit)) then
			local handler = frame.scripts.OnEvent
			if handler then handler(frame, event, ...) end
		end
	end
end

-- Runs the C_Timer callbacks queued so far, as the client does on the next
-- frame. Callbacks they queue wait for the frame after.
function Client:NextFrame()
	local due = self.timers
	self.timers = {}
	for _, callback in ipairs(due) do
		callback()
	end
end

-- Moves GetTime() forward by `seconds`, firing every ticker that falls due on
-- the way, in time order. A ticker cancelled meanwhile fires no more.
function Client:Advance(seconds)
	local target = self.now + seconds
	local ticker = NextDueTicker(self.tickers, target)
	while ticker do
		self.now = ticker.dueAt
		ticker.dueAt = ticker.dueAt + ticker.interval
		ticker.callback(ticker)
		ticker = NextDueTicker(self.tickers, target)
	end
	self.now = target
end

function Client:ActiveTickers()
	local count = 0
	for _, ticker in ipairs(self.tickers) do
		if not ticker.cancelled then count = count + 1 end
	end
	return count
end

function Client:Broker(name)
	return self.ldb:GetDataObjectByName(name)
end

-- Every attribute assignment made to the broker, unchanged values included.
function Client:Writes(name)
	return self.writes[name]
end

-- Shows the broker's tooltip in a GameTooltip-like recorder. Returns the text,
-- one row per line and "left<TAB>right" for double lines, and the rows.
function Client:TooltipText(name)
	local rows = {}
	local tooltip = {}
	function tooltip.AddLine(_, text)
		rows[#rows + 1] = CheckedText(text)
	end
	function tooltip.AddDoubleLine(_, left, right)
		rows[#rows + 1] = CheckedText(left) .. "\t" .. CheckedText(right)
	end
	self:Broker(name).OnTooltipShow(tooltip)
	return table.concat(rows, "\n"), rows
end

-- Counts repaints the way a DataBars Broker Plugin block would: one callback on
-- LibDataBroker_AttributeChanged_<name>, one repaint per rendered attribute change.
function Client:WatchLikeDataBars(name)
	local watcher = { repaints = 0 }
	self.ldb.RegisterCallback(watcher, "LibDataBroker_AttributeChanged_" .. name, function(_, _, key)
		if RENDERED_ATTRIBUTES[key] then watcher.repaints = watcher.repaints + 1 end
	end)
	return watcher
end

-------------------------------------------------------------------------------
-- Loading the addon
-------------------------------------------------------------------------------

-- Reads a TOC file: its "## Key: Value" metadata and its files in load order,
-- with WoW's backslashes turned into slashes.
function wow.ReadToc(path)
	local metadata, files = {}, {}
	for rawLine in io.lines(path) do
		local line = rawLine:gsub("\r$", "")
		local key, value = line:match("^##%s*([%w%-]+)%s*:%s*(.-)%s*$")
		if key then
			metadata[key] = value
		elseif line:match("%S") and not line:match("^%s*#") then
			files[#files + 1] = (line:match("^%s*(.-)%s*$"):gsub("\\", "/"))
		end
	end
	return metadata, files
end

local function LoadChunk(path, env)
	if setfenv then -- Lua 5.1 and LuaJIT
		return setfenv(assert(loadfile(path)), env)
	end
	return assert(loadfile(path, "t", env))
end

-- A fresh client. The fields after `now` are what the mocked APIs return; tests
-- change them between events.
local function NewClient()
	return setmetatable({
		frames = {},
		timers = {},
		tickers = {},
		writes = {},
		printed = {},
		calls = {}, -- API name -> number of calls
		lastArgs = {}, -- API name -> arguments of the latest call
		checked = setmetatable({}, { __mode = "k" }), -- secrets passed to issecretvalue
		now = 0, -- GetTime(), moved by Client:Advance
		maxMana = 1000,
		normalRegen = 0,
		castingRegen = 0,
		resting = false,
		restedXP = nil,
		restState = 2,
		level = 10,
		maxLevel = 60,
		xp = 0,
		xpMax = 1000,
		xpDisabled = false,
	}, Client)
end

-- A mocked API function: records the call, then returns read(client, ...).
local function Api(client, name, read)
	return function(...)
		client.calls[name] = (client.calls[name] or 0) + 1
		client.lastArgs[name] = { ... }
		return read(client, ...)
	end
end

-- A mocked unit API that, like the XP functions, only answers for the player.
local function PlayerApi(client, name, field)
	return Api(client, name, function(c, unit)
		assert(unit == "player", name .. " only works on the player")
		return c[field]
	end)
end

local function AddLuaGlobals(env, client)
	for _, name in ipairs(LUA_GLOBALS) do
		env[name] = _G[name]
	end
	env.type = function(value)
		return secretKinds[value] or type(value)
	end
	env.print = function(...)
		local parts = {}
		for i = 1, select("#", ...) do
			parts[i] = tostring((select(i, ...)))
		end
		client.printed[#client.printed + 1] = table.concat(parts, " ")
	end
end

local function AddEngineApi(env, client, libraries)
	env.issecretvalue = function(value)
		local secret = wow.IsSecret(value)
		if secret then client.checked[value] = true end
		return secret
	end
	env.Enum = {
		PowerType = { Mana = 0 },
		AddOnRestrictionType = wow.Restriction,
		AddOnRestrictionState = wow.RestrictionState,
	}
	env.LibStub = NewLibStub(libraries)
	env.CreateFrame = function(frameType)
		assert(frameType == "Frame", "the addon only creates plain frames")
		return NewFrame(client)
	end
	env.C_Timer = NewTimerApi(client)
	env.GetTime = function()
		return client.now
	end
end

local function AddCharacterApi(env, client)
	env.GetManaRegen = Api(client, "GetManaRegen", function(c)
		return c.normalRegen, c.castingRegen
	end)
	env.UnitPowerMax = PlayerApi(client, "UnitPowerMax", "maxMana")
	env.IsResting = Api(client, "IsResting", function(c)
		return c.resting
	end)
	-- Rested XP state, which the resting broker must not use.
	env.GetXPExhaustion = Api(client, "GetXPExhaustion", function(c)
		return c.restedXP
	end)
	env.GetRestState = Api(client, "GetRestState", function(c)
		return c.restState, c.restState == 1 and "Rested" or "Normal", 1
	end)
	env.UnitXP = PlayerApi(client, "UnitXP", "xp")
	env.UnitXPMax = PlayerApi(client, "UnitXPMax", "xpMax")
	env.UnitLevel = PlayerApi(client, "UnitLevel", "level")
	env.GetMaxLevelForPlayerExpansion = Api(client, "GetMaxLevelForPlayerExpansion", function(c)
		return c.maxLevel
	end)
	env.C_PlayerInfo = {
		IsXPUserDisabled = Api(client, "IsXPUserDisabled", function(c)
			return c.xpDisabled
		end),
	}
end

-- Removes `without` from the environment, then makes any other unknown global
-- read, and every global write, raise.
local function Seal(env, without)
	local absent = {}
	for _, name in ipairs(without) do
		env[name] = nil
		absent[name] = true
	end
	setmetatable(env, {
		__index = function(_, name)
			if not absent[name] then
				error("the addon read the undefined global " .. tostring(name), 2)
			end
		end,
		__newindex = function(_, name)
			error("the addon assigned the global " .. tostring(name), 2)
		end,
	})
end

-- Builds a fresh client and loads the addon into it. Options:
--   without = { "issecretvalue", ... }  globals this client lacks
--   withoutLibDataBroker = true         LibStub has no LibDataBroker-1.1
--   takenBrokerNames = { name, ... }    data objects another addon registered first
function wow.Load(options)
	options = options or {}
	local client = NewClient()
	local ldb = NewLibDataBroker(client)
	client.ldb = ldb
	for _, name in ipairs(options.takenBrokerNames or {}) do
		ldb:NewDataObject(name, { type = "data source", text = "taken" })
	end
	local libraries = {}
	if not options.withoutLibDataBroker then
		libraries["LibDataBroker-1.1"] = ldb
	end
	local env = {}
	AddLuaGlobals(env, client)
	AddEngineApi(env, client, libraries)
	AddCharacterApi(env, client)
	Seal(env, options.without or {})
	local ns = {}
	local _, files = wow.ReadToc(wow.TOC_PATH)
	for _, file in ipairs(files) do
		LoadChunk(file, env)(wow.ADDON_NAME, ns)
	end
	client.ns = ns
	return client
end

return wow
