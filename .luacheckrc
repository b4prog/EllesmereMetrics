-- luacheck configuration: https://luacheck.readthedocs.io
-- The addon runs on WoW Forever's embedded Lua 5.1. It defines no globals and
-- reads only the WoW API listed below; add an entry only after confirming on
-- warcraft.wiki.gg that the API exists on Forever 1.60.1.

std = "lua51"
max_line_length = 120
exclude_files = { "build/**", "dist/**" }

read_globals = {
	"C_PlayerInfo",
	"C_Timer",
	"CreateFrame",
	"Enum",
	"GetManaRegen",
	"GetMaxLevelForPlayerExpansion",
	"GetTime",
	"IsResting",
	"LibStub",
	"UnitLevel",
	"UnitPowerMax",
	"UnitXP",
	"UnitXPMax",
	"issecretvalue",
}

-- The tests run on a desktop interpreter (Lua 5.1 in CI, LuaJIT or newer
-- locally) and use its standard library.
files["tests/**/*.lua"] = {
	std = "max",
}
