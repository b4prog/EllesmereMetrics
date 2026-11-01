# EllesmereMetrics

[![CI](https://github.com/b4prog/EllesmereMetrics/actions/workflows/ci.yml/badge.svg)](https://github.com/b4prog/EllesmereMetrics/actions/workflows/ci.yml)

EllesmereMetrics adds extra character information to the **EllesmereUI DataBars** of
**World of Warcraft: Forever**. It currently provides two indicators:

- **Mana Regen**: your character's mana regeneration rates, in mana per second.
- **Resting Area**: whether your character is standing where rested XP builds up.

> [!NOTE]
> EllesmereMetrics is an **unofficial** companion addon. It is not made, endorsed or
> supported by Ellesmere or the EllesmereUI project. Please report EllesmereMetrics
> problems in [its issue tracker](https://github.com/b4prog/EllesmereMetrics/issues),
> not to EllesmereUI.

## Contents

- [Overview](#overview)
- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Configuring EllesmereUI DataBars](#configuring-ellesmereui-databars)
- [Usage examples](#usage-examples)
- [Known limitations](#known-limitations)
- [Development](#development)
- [CI and automated reviews](#ci-and-automated-reviews)
- [License](#license)

## Overview

[EllesmereUI](https://github.com/EllesmereGaming/EllesmereUI) is a complete interface
suite. Its **DataBars** module draws information bars (clock, gold, durability and
more) built from blocks. One block type, **Broker Plugin**, displays information
published by *other* addons through **LibDataBroker**, a long-standing standard that
lets an addon share a small piece of text, an icon and a tooltip with any compatible
display.

EllesmereMetrics uses that mechanism. It does not change EllesmereUI or draw any
frames of its own: it registers two LibDataBroker data objects, keeps their text up to
date, and DataBars shows them wherever you place a Broker Plugin block.

```text
game events ---> EllesmereMetrics ---> LibDataBroker ---> DataBars "Broker Plugin" block
(stats, auras,   reads the game API,   notifies every     redraws its text, icon
 resting areas)  updates its text      display            and tooltip
```

EllesmereMetrics relies on the copy of LibDataBroker that EllesmereUI already ships, so
it adds no libraries of its own. It reacts to game events instead of checking
continuously, so it costs next to nothing while you play.

## Features

### Mana Regen

Data broker name: `EllesmereMetrics_ManaRegen` (label `Mana Regen`).

It shows the two regeneration rates the game reports through `GetManaRegen()`, in
**mana per second**:

| Shown as | Rate | Meaning |
| --- | --- | --- |
| first number | **Not casting** | Regeneration while you have not spent mana for five seconds. |
| second number | **While casting** | Regeneration within five seconds of spending mana on a spell (the "five-second rule"). |

For example, `85.2/s | 34.5/s` means 85.2 mana per second outside the five-second
rule and 34.5 mana per second inside it. Multiply by 5 to compare with "mana per 5
seconds" (MP5) values. The tooltip spells out both rates.

The rates update when something that affects them changes: stats, gear, buffs and
debuffs, talents, and the end of combat restrictions.

These are the **rates the game reports**, not a live measurement of the mana you are
gaining. Which rate applies at a given moment depends on when you last spent mana, and
effects that restore mana directly (drinking, potions, spells) are separate from
these rates. WoW Forever also hides the current mana value from addons in some
situations, so EllesmereMetrics cannot measure actual gain reliably and does not try.

**Combat and restricted situations.** WoW Forever runs Blizzard's modern engine, which
hides some character statistics from addons while restrictions apply, in combat at
least. The game then returns *secret values* that addons may not read. When that
happens the indicator shows `--` and its tooltip says why; it never keeps showing the
old numbers as if they were current. The rates come back on their own as soon as the
restriction ends.

Characters without a mana pool (Warriors and Rogues) see `No mana`. A druid in cat or
bear form still has a mana pool, so the block keeps showing the rates the game reports.

> EllesmereUI's **Quality of Life** module can also show MP5 in its Secondary Stats
> display on WoW Forever. EllesmereMetrics adds both per-second rates as a DataBars
> block.

### Resting Area

Data broker name: `EllesmereMetrics_Resting` (label `Resting Area`).

It shows **`Resting`** while your character is in a resting area (an inn or a major
city) and **`Not Resting`** everywhere else. The icon is bright while resting and
dimmed otherwise, but the text alone always tells the state, so it stays clear even if
you recolor the block or hide its icon. It changes the moment you enter or leave a
resting area, using the game's own `IsResting()` check and `PLAYER_UPDATE_RESTING`
event; there is no list of cities or inns to maintain.

Being in a resting area is **not** the same as having rested XP:

- `Resting` means your current location lets rested XP build up.
- It does not tell you how much rested XP you already have, whether you are earning
  experience right now, or whether you are at the maximum level.

The tooltip repeats this distinction. EllesmereUI's Clock block has an optional
"Resting Icon"; this broker is a separate, text-based indicator you can place anywhere
on a bar.

## Requirements

- **World of Warcraft: Forever**, client **1.60.1** (addon interface `16001`).
- **[EllesmereUI](https://github.com/EllesmereGaming/EllesmereUI)**, with its
  **EllesmereUI DataBars** module enabled. EllesmereUI is a required dependency:
  EllesmereMetrics does not load without it.

Other World of Warcraft versions (Retail, Classic Era, Classic progression servers)
are not supported.

## Installation

1. **Get the archive.** Download `EllesmereMetrics-<version>.zip` from the
   [GitHub Releases](https://github.com/b4prog/EllesmereMetrics/releases) page once a
   release is published. Until then, build it yourself with `make pack` (see
   [Development](#development)); the archive appears in `dist/`.
2. **Exit World of Warcraft.** A game that is already running may not notice a new
   addon until it restarts; `/reload` only reloads addons it already knows.
3. **Find the WoW Forever AddOns folder**: `World of Warcraft\_forever_\Interface\AddOns`.
   With a default installation that is
   `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns` on Windows and
   `/Applications/World of Warcraft/_forever_/Interface/AddOns` on macOS. If you
   installed the game elsewhere, open the Battle.net app, select World of Warcraft with
   the WoW Forever version, then use the gear menu next to **Play** and choose
   **Show in Explorer** (Windows) or **Show in Finder** (macOS). Create the `Interface`
   and `AddOns` folders if they do not exist yet. Addons placed in `_retail_` or
   `_classic_` folders do not load in WoW Forever.
4. **Extract the archive into `AddOns`.** The ZIP contains a single folder named
   `EllesmereMetrics`. You should end up with:

   ```text
   _forever_/Interface/AddOns/EllesmereMetrics/EllesmereMetrics.toc
   ```

   Avoid an extra level such as `AddOns/EllesmereMetrics/EllesmereMetrics/...` or
   `AddOns/EllesmereMetrics-0.1.0/EllesmereMetrics/...` (some extraction tools add one):
   the game ignores addons nested that way. Move the inner `EllesmereMetrics` folder up
   if that happens.
5. **Start the game.** On the character selection screen, open **AddOns** and make
   sure **EllesmereUI**, **EllesmereUI DataBars** and **EllesmereMetrics** are enabled.
   EllesmereMetrics lists EllesmereUI as a dependency, so it stays disabled without it.
6. **Enter the world** with any character.
7. **Check that it loaded.** Type `/dump C_AddOns.IsAddOnLoaded("EllesmereMetrics")` in
   chat: both values it prints should be `true`. The two brokers then appear in the
   DataBars plugin list (next section). EllesmereMetrics prints nothing in chat unless
   something is wrong.

## Configuring EllesmereUI DataBars

The labels below come from the EllesmereUI source code (version 9.7.2). Later
EllesmereUI versions may rename or move them. Settings cannot be opened during combat.

1. **Open the EllesmereUI settings** with `/eui` (`/ellesmere` and `/ellesmereui` also
   work).
2. **Go to DataBars**: in the sidebar, under **Utility Addons**, select **DataBars**.
3. **Choose a bar.** Pick an existing bar in the bar selector at the top of the page,
   or click **+ New Bar** and choose a template: **Start Empty**, **Top/Bottom Info
   Bar**, **Minimap Companion** or **Micro Menu Strip**.
4. **Add a Broker Plugin block.** Click the **+** tile at the end of the bar preview
   and choose **Broker Plugin** from the list. The settings jump to the new block's
   **Plugin** dropdown, which pulses until a plugin is chosen.
5. **Select `EllesmereMetrics_ManaRegen`** in the **Plugin** dropdown. The dropdown is
   searchable; the entry reads `EllesmereMetrics_ManaRegen (Mana Regen)`.
6. **Add a second Broker Plugin block** the same way (the **+** tile, then **Broker
   Plugin**). Each block shows one plugin.
7. **Select `EllesmereMetrics_Resting`**, listed as
   `EllesmereMetrics_Resting (Resting Area)`.
8. **Adjust each block** with the options DataBars offers:

   | Option | Effect |
   | --- | --- |
   | **Show Icon** | Shows the plugin's icon next to its text (on by default). |
   | **Show Text** | Shows the plugin's text; off leaves an icon-only block that keeps the tooltip. |
   | **Show Label** | Puts the plugin's label in front of the text, e.g. `Mana Regen: 85.2/s \| 34.5/s`. |
   | **Strip Colors** | Removes color codes from the plugin's text. EllesmereMetrics uses none, so this changes nothing for it. |
   | **Max Width** | Holds the block at a fixed width. Useful for Mana Regen, whose text width changes with the numbers. `0` sizes the block to its text. |
   | **Text Color**, **Icon Color** | Block colors. An explicit Icon Color replaces the Resting Area icon dimming; the text still shows the state. |

   To reorder blocks, drag them in the bar preview. Bar size and visibility are in the
   **Bar Settings** section of the same page; bars are positioned with EllesmereUI's
   unlock mode (`/unlock`).

If the plugins are missing from the dropdown, EllesmereMetrics is not loaded: see step
7 of the [installation](#installation). A block whose plugin is no longer loaded hides
itself and shows as "not loaded" in its dropdown.

## Usage examples

The numbers below are only examples. Your values depend on your character's class,
level, stats, gear, talents and buffs.

Mana Regen block, with **Show Label** off and on:

```text
[icon] 85.2/s | 34.5/s
[icon] Mana Regen: 85.2/s | 34.5/s
```

Other states of the Mana Regen block:

```text
[icon] --          the game is hiding the rates (for example in combat), or has not reported them yet
[icon] No mana     the character has no mana pool
```

Its tooltip:

```text
Mana Regeneration
Not casting                    85.2 mana/s
While casting                  34.5 mana/s

Rates reported by the game, in mana per second. The casting rate applies for
five seconds after you spend mana (the five-second rule).
They are rates, not a measurement of the mana you are gaining right now.
```

Resting Area block:

```text
[icon] Resting       in an inn or a major city (bright icon)
[icon] Not Resting   anywhere else (dimmed icon)
```

## Known limitations

- **Restricted statistics.** While the game restricts character statistics, Mana Regen
  shows `--`. Blizzard does not document every situation that triggers this; combat is
  one, and encounters or instances may be others. The values return once the
  restriction ends.
- **Rates, not measurements.** Mana Regen shows the rates `GetManaRegen()` reports. It
  does not track the five-second rule, server regeneration ticks, drinking or potions.
- **Not yet verified in game.** This version has not been tested in the WoW Forever
  client. The automated tests run against a simulated client and cannot prove how the
  real one behaves, in particular how it restricts statistics in each situation. Use
  the checklist below before each release.
- **Labels may drift.** The DataBars instructions match EllesmereUI 9.7.2.
- **WoW Forever only**, English only, and no settings of its own.

### Manual in-game test checklist

Turn on Lua error display first with `/console scriptErrors 1`, then:

1. Log in with a mana user (for example a Mage) and add both blocks as described above.
2. Out of combat, compare the Mana Regen block with `/dump GetManaRegen()`: the two
   numbers should match, rounded to one decimal.
3. Change something that affects regeneration: take off or put on gear with Spirit or
   Intellect, or receive a buff. The block should follow within a moment.
4. Enter combat by attacking an easy enemy. Mana Regen shows `--` if the game
   restricts statistics, or keeps updating if it does not. No Lua error may appear.
5. Leave combat: the rates come back on their own.
6. Optionally repeat steps 4 and 5 inside a dungeon.
7. Log in with a Warrior or Rogue: Mana Regen shows `No mana`.
8. Walk into an inn: Resting Area switches to `Resting` and the icon brightens. Walk
   out: it switches to `Not Resting` and the icon dims. Repeat in a major city.
9. Log out inside an inn and log back in: the block shows `Resting` right after
   loading.
10. Hover each block: the tooltips match the descriptions above.

Testers can also try `/console addonCombatRestrictionsForced 1`, a test setting of the
modern WoW engine that applies combat restrictions outside combat, and
`/console addonCombatRestrictionsForced 0` to turn it off again. It has not been
verified on WoW Forever and may not exist there.

## Development

### Tools

- **GNU make** (the version shipped with macOS works).
- **A Lua 5.1 interpreter**: `lua5.1` matches the game best. LuaJIT also works for
  local runs. The Makefile picks `lua5.1`, then `luajit`, then `lua`; override it with
  `LUA=...`.
- **[luacheck](https://github.com/lunarmodules/luacheck)** for static analysis.
- **zip** and **unzip** for packaging.

On macOS: `brew install luajit luacheck`. On Debian or Ubuntu:
`sudo apt-get install lua5.1 lua-check zip unzip`. With LuaRocks:
`luarocks install luacheck`. No WoW installation is needed.

### Make targets

| Command | What it does |
| --- | --- |
| `make help` | Lists the targets. |
| `make syntax` | Checks that every Lua file parses. |
| `make lint` | Runs luacheck on the addon and the tests (configured in `.luacheckrc`). |
| `make test` | Runs the automated tests. |
| `make check` | Runs `syntax`, `lint` and `test`. |
| `make pack` | Builds `dist/EllesmereMetrics-<version>.zip`. |
| `make verify` | Checks the archive built by `make pack`. |
| `make all` | Runs `check`, `pack` and `verify`. |
| `make clean` | Deletes `build/` and `dist/`. |

### Project structure

```text
EllesmereMetrics/
├── EllesmereMetrics.toc       addon metadata and load order
├── Core.lua                   shared helpers, LibDataBroker lookup
├── Brokers/
│   ├── ManaRegen.lua          EllesmereMetrics_ManaRegen
│   └── Resting.lua            EllesmereMetrics_Resting
├── tests/
│   ├── run.lua                test runner and assertions
│   ├── wow.lua                simulated WoW client
│   └── test_*.lua             test suites
├── scripts/verify-archive.sh  archive checks used by make verify
├── Makefile
├── .luacheckrc                luacheck settings and allowed WoW API
├── .editorconfig              formatting rules (tabs, two columns wide)
├── .github/                   CI workflow and Dependabot settings
├── .coderabbit.yaml           CodeRabbit review settings
├── README.md                  this file
├── AGENTS.md                  instructions for AI coding agents
├── CLAUDE.md                  imports AGENTS.md for Claude Code
└── LICENSE
```

`Core.lua` loads first and provides `ns.NewBroker`, `ns.IsSecret`, `ns.AddNote` and
`ns.PLACEHOLDER_TEXT` to the brokers. Each file in `Brokers/` owns one data object, its
state, its events and its tooltip; brokers never depend on one another.

### Adding a data broker

1. Create `Brokers/<Name>.lua`. The general shape:

   ```lua
   local _, ns = ...

   local GetExampleValue = GetExampleValue

   local dataobj = ns.NewBroker("EllesmereMetrics_Example", {
   	label = "Example",
   	text = ns.PLACEHOLDER_TEXT,
   	icon = "Interface\\Icons\\INV_Misc_QuestionMark",
   	OnTooltipShow = function(tooltip)
   		tooltip:AddLine("Example")
   		ns.AddNote(tooltip, "What the value means and where it comes from.")
   	end,
   })
   if not dataobj then return end

   local shown

   local function Update()
   	local value = GetExampleValue()
   	if ns.IsSecret(value) then
   		value = nil
   	end
   	if value == shown then return end
   	shown = value
   	dataobj.text = value and tostring(value) or ns.PLACEHOLDER_TEXT
   end

   local eventFrame = CreateFrame("Frame")
   eventFrame:SetScript("OnEvent", Update)
   eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
   ```

2. List the file in `EllesmereMetrics.toc`, after `Core.lua`. The TOC is the only list
   of runtime files: packaging and tests read it.
3. Add every WoW function it uses to `read_globals` in `.luacheckrc`, and every event it
   registers to `KNOWN_EVENTS` in `tests/wow.lua`, after checking on
   [warcraft.wiki.gg](https://warcraft.wiki.gg) that they exist on WoW Forever 1.60.1.
4. Add `tests/test_<name>.lua` and document the broker in this README.

The broker name is saved in players' DataBars settings, so never rename it after a
release. `AGENTS.md` lists the remaining rules.

### Tests and linting

The tests run on a desktop Lua interpreter against a simulated client (`tests/wow.lua`)
that provides the game functions the addon uses, events, timers, LibDataBroker and
*secret values*: placeholder objects that raise an error on arithmetic, ordering
comparisons, indexing and similar operations, as the real game does for addon code. The
simulation is stricter on one point: it also rejects formatting a secret, which the game
allows but the addon never needs. The simulated client also fails a
test when the addon writes a global, reads an unknown global, registers an unknown
event, or hands a secret to LibDataBroker. The suites cover broker registration, initial
values, formatting, every refresh event, unchanged values, secret and invalid values,
characters without mana, and entering and leaving resting areas.

A simulation cannot reproduce everything. For instance, plain Lua cannot make
`secret == 0` raise an error the way the game does, so the order of checks is also
enforced by code review. Lint and tests passing never prove in-game behavior: use the
[manual checklist](#manual-in-game-test-checklist).

`make lint` runs luacheck with `.luacheckrc`, which pins the addon to Lua 5.1 and to an
explicit list of WoW functions. A misspelled or unexpected game function is reported as
an unknown global.

### Packaging

`make pack` copies the TOC, the files it lists and `LICENSE` into `build/EllesmereMetrics/`
and zips that folder into `dist/EllesmereMetrics-<version>.zip`. The version comes from
the `## Version:` line of `EllesmereMetrics.toc`. Nothing else is copied, so development
files never ship.

`make verify` then checks that the archive:

- has a single top-level `EllesmereMetrics/` folder;
- contains the TOC, every file the TOC lists, and `LICENSE`, and nothing else;
- contains no development files (`AGENTS.md`, `CLAUDE.md`, `README.md`, `Makefile`,
  `tests/`, `scripts/`, `.github/`, configuration dotfiles);
- is named after the TOC version and matches the working tree file for file.

To publish a release, bump `## Version:` in the TOC, run `make all`, and attach the ZIP
to a GitHub Release.

### Instructions for AI coding agents

[`AGENTS.md`](AGENTS.md) is the **canonical** instruction file for AI coding agents
(Codex and other tools that read `AGENTS.md`). [`CLAUDE.md`](CLAUDE.md) contains a
single line, `@AGENTS.md`, which Claude Code reads as an import of `AGENTS.md`. Every
agent therefore follows the same rules from one place. **Edit instructions only in
`AGENTS.md`**; never add rules to `CLAUDE.md`.

## CI and automated reviews

### GitHub Actions

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs on pushes to `main`, on
pull requests targeting `main`, and on demand (**Actions** tab, **Run workflow**). On
Ubuntu 24.04 it installs `lua5.1` and luacheck from the Ubuntu archive, then runs
`make syntax`, `make lint`, `make test`, `make pack` and `make verify`, and uploads the
ZIP as a workflow artifact for 14 days. GitHub wraps artifacts in its own ZIP, so
extract the download once to get `EllesmereMetrics-<version>.zip`.

The workflow uses only official GitHub actions, pinned to full commit SHAs, with a
read-only token and no secrets. Pull requests from forks run with the same
restrictions.

### Dependabot

[`.github/dependabot.yml`](.github/dependabot.yml) checks the GitHub Actions used by the
workflow every week and groups updates into a single pull request. Dependabot reads the
file from the default branch, so version updates start once it is merged into `main`.

### CodeRabbit

[`.coderabbit.yaml`](.coderabbit.yaml) configures [CodeRabbit](https://www.coderabbit.ai)
to review pull requests targeting `main` automatically (drafts excluded), with
project-specific guidance on Lua 5.1, WoW Forever APIs, secret values, events,
performance, the LibDataBroker contract and packaging. CodeRabbit also reads `AGENTS.md`
as coding guidelines. No GitHub workflow is involved: CodeRabbit runs as a GitHub App.

### One-time repository setup

These steps need the repository owner and cannot be done from the repository files:

1. **Actions**: in **Settings > Actions > General**, make sure Actions are allowed. To
   require a passing build before merging, add the **Lint, test and package** check to a
   branch protection rule or ruleset for `main`.
2. **Dependabot**: version updates need nothing beyond the merged file. Optionally turn
   on **Dependabot alerts** and **Dependabot security updates** in the repository's
   security settings.
3. **CodeRabbit**: sign in at [app.coderabbit.ai](https://app.coderabbit.ai) with GitHub
   and install the CodeRabbit GitHub App for `b4prog/EllesmereMetrics` (choosing **Only
   select repositories** keeps its access limited). Check CodeRabbit's current plans for
   pricing. Reviews then start on the next pull request; comment
   `@coderabbitai review` on a pull request to request one manually.

## License

EllesmereMetrics is released under the [MIT License](LICENSE). The license file ships
inside every release archive.
