# EllesmereMetrics: agent instructions

EllesmereMetrics is an unofficial companion addon for EllesmereUI. It publishes
character metrics as LibDataBroker-1.1 data objects that EllesmereUI DataBars
shows in "Broker Plugin" blocks. It targets **World of Warcraft: Forever 1.60.1
only** (`## Interface: 16001`), which runs the 12.x engine (secret values, addon
restrictions) with vanilla content. `README.md` is the user documentation; this
file holds the rules for changing the code.

## Layout

| Path | Role |
| --- | --- |
| `EllesmereMetrics.toc` | Metadata and load order. The only list of runtime Lua files: `make pack` and the tests read it. |
| `Core.lua` | Loads first. Resolves LibDataBroker-1.1 (shipped by EllesmereUI) and defines the `ns` helpers. |
| `Brokers/*.lua` | One data object per file, with its own state, events and tooltip. Brokers never depend on each other. |
| `tests/` | `run.lua` (runner, assertions), `wow.lua` (client mock), `test_*.lua`. |
| `scripts/verify-archive.sh` | Archive checks behind `make verify`. |

## Commands

- `make check`: syntax check, `luacheck`, tests. Run it before every commit.
- `make pack`, then `make verify`: build `dist/EllesmereMetrics-<version>.zip` and check it.
- `make all` runs everything above; `make clean` deletes `build/` and `dist/`.
- Tools: make, a Lua 5.1 interpreter (`lua5.1`, or LuaJIT; override with `LUA=...`),
  `luacheck`, `zip`, `unzip`. CI uses Ubuntu's `lua5.1` and `lua-check`.

## Lua conventions

- Lua 5.1 as embedded in WoW: no `goto`, `//`, bitwise operators, `table.unpack`
  or other 5.2+ features. LuaJIT accepts some of them, so CI parses with `lua5.1`.
- No globals. Files start with `local _, ns = ...`; shared helpers live on `ns`.
  Cache WoW API functions in locals at the top of the file.
- One tab per indentation level (shown two columns wide), never spaces. Lua and
  TOC files are ASCII only. Code, comments and docs are in English.
- Prefer clear names to comments. Comment WoW restrictions, event ordering and
  other non-obvious decisions.
- Each WoW API the addon reads needs a `read_globals` entry in `.luacheckrc`,
  added only after warcraft.wiki.gg confirms it exists on Forever 1.60.1. Never
  silence warnings broadly.
- No `loadstring`, SavedVariables, settings UI, `OnUpdate` scripts, protected
  frames or EllesmereUI frames.

## LibDataBroker and DataBars contract

- Broker names (`EllesmereMetrics_ManaRegen`, `EllesmereMetrics_Resting`,
  `EllesmereMetrics_XPRate`) are saved in users' DataBars profiles. Never rename one.
- Register through `ns.NewBroker(name, attributes)`, which sets
  `type = "data source"` and the icon crop. Use stock `Interface\Icons\` art.
- DataBars repaints on `LibDataBroker_AttributeChanged_<name>` for `text`,
  `value`, `suffix`, `label`, `icon`, `iconR/G/B` and `iconCoords`. Assign an
  attribute only when what it shows changes; compare raw values before formatting.
- Keep `text` plain and short: DataBars strips color codes by default, and users
  may recolor or hide icons. The name goes in `label`, explanations in
  `OnTooltipShow` (GameTooltip `AddLine`/`AddDoubleLine`).
- Never copy EllesmereUI code or touch its frames or saved variables.

## Secret values and restrictions

- Both `GetManaRegen()` returns are `SecretWhenUnitStatsRestricted`: secret while
  the game restricts unit stats (in combat, at least).
- Call `ns.IsSecret(value)` before comparing, formatting, concatenating, indexing
  or doing arithmetic on a value from such an API, and before publishing it.
  `type()` cannot detect a secret: it reports the underlying type.
- Never publish a secret, never present the last readable value as current, and
  never try to get around a restriction.
- Restriction edges arrive as `ADDON_RESTRICTION_STATE_CHANGED`. Re-read on the
  next frame: an activating restriction is enforced only after that dispatch.
- `IsResting()`, `UnitXP()`, `UnitXPMax()` and `UnitLevel()` have no secret
  predicate on 1.60.1. Check each new API's page.

## Events and performance

- Event-driven; unit events via `RegisterUnitEvent(event, "player")`.
- Handle events with `ns.NextFrameUpdater(update)`: one read on the next frame per burst.
- No polling, except for a value that changes with elapsed time alone (XP Rate):
  one `C_Timer.NewTicker` of 10 seconds or more, cancelled once the value can no
  longer change.
- The client raises an error on unknown event names. Add each new event to
  `KNOWN_EVENTS` in `tests/wow.lua` once it is verified for Forever.

## Adding a broker

1. Create `Brokers/<Name>.lua`, modeled on `Brokers/ManaRegen.lua` if its API can
   return secrets, otherwise on `Brokers/Resting.lua`.
2. List it in `EllesmereMetrics.toc` after `Core.lua`.
3. Add `tests/test_<name>.lua`: initial state, every event, unchanged values,
   and unreadable or secret values.
4. Document it in `README.md`: features, configuration, limitations.

## Packaging

The ZIP holds a single `EllesmereMetrics/` folder with the TOC, the files it lists
and `LICENSE`, nothing else. The version comes from the TOC's `## Version:` line.
Development files (`AGENTS.md`, `CLAUDE.md`, `README.md`, `Makefile`, `tests/`,
`scripts/`, `.github/`, dotfiles) never ship; `make verify` enforces it.

## Testing

- Every behavior change comes with a test. The mock rejects unknown globals,
  global writes, unknown events and secrets published to LibDataBroker.
- Passing tests and lint do not prove in-game behavior. Say what still needs an
  in-game check, and keep the manual procedure in `README.md` up to date.

## Agent instruction files

`AGENTS.md` is the single source of instructions for coding agents. `CLAUDE.md`
contains only `@AGENTS.md`, which Claude Code imports. Edit this file, never
`CLAUDE.md`.
