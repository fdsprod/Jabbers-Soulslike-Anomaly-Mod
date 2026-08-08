# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Writing style

Use the `ste` skill for every response to this user, including chat replies.

## What this is

A gameplay mod for S.T.A.L.K.E.R. Anomaly, written in Lua. On death the player is
rescued and wakes at a chosen spawn bed. Their gear stays where they died, degraded
or partly lost depending on MCM settings.

Only `gamedata/` ships. `deploy.bat` copies it into a local GAMMA mods folder. The
paths in `deploy.bat` are hard-coded to one machine.

Two directories are reference material, not part of the mod, and are gitignored:

- `_scripts/` — stock Anomaly scripts. Read these to learn the base-game API.
- `_items/` — stock item configs.

The mod overwrites no stock script or ltx file. Keep it that way. Conflict-free
loading is a stated feature.

## Commands

```
tests\run.bat                     all specs (self-tests gate unit and e2e)
tests\run.bat self|unit|e2e       one suite
tests\run.bat --file ambush       spec files whose path contains "ambush"
tests\run.bat -t "keep roll"      tests whose full name contains "keep roll"
tests\locals.bat                  localisation spec, then the report (strict;
                                  --lax to not fail on untranslated strings)
tests\tools\luajit.exe probe.lua  reachability check
deploy.bat                        copy gamedata\ to the local GAMMA mods folder
```

Exit codes: 0 pass, 1 fail, 2 no Lua runtime or no match.

The suite needs LuaJIT 2.x or Lua 5.1. Lua 5.2 and later do not work, because the
module loader uses `setfenv`. `run.bat` looks for `luajit.exe` on PATH, then
`tests\tools\luajit.exe`. `tools\` is gitignored. `tests/README.md` gives the build
steps.

There is no build step, no linter, and no CI.

## Architecture

### Script modules

The engine loads every file in `gamedata/scripts/` as a module named after the
file. A module reads another module through its global name, such as
`soulslike.debug(...)`.

| File | Role |
|---|---|
| `soulslike.script` | Entry point. Registers every callback in `on_game_start()`. Holds shared state, enums, helpers, and the hit queue. |
| `soulslike_scenarios.script` | `SoulslikeScenarioLogic` base class and its four subclasses. Almost all death and respawn behaviour lives here. |
| `soulslike_scenario_logic_factory.script` | Reads the fatal hit, picks a scenario, and builds the logic object. |
| `soulslike_mcm.script` | The whole option tree, plus one `get_config` accessor every getter funnels through. |
| `soulslike_classes.script` | `TimedQueue`, used for the hit pool. |
| `soulslike_message_factory.script` | Picks a random rescuer message string id per beat. |
| `soulslike_note.script` | The note item the rescuer leaves. |
| `soulslike_sleep_dialog.script` | Sleep-to-save dialog for hardcore save mode. |
| `souslike_gamemode_injector_mcm.script` | Monkey-patches `ui_mm_faction_select.UINewGame` to add the Soulslike checkbox to new game. Note the typo in the filename. It is load-bearing. |

### The death flow

1. `actor_on_before_hit` pushes each hit into a `TimedQueue`. The queue expires
   entries after `MAX_HIT_TIME` (30 s) and holds `MAX_HIT_POOL_COUNT` (30).
2. `actor_on_before_death` asks the factory for a scenario.
3. The factory aggregates the queued hits, weights later hits more heavily, doubles
   the fatal one, and picks the strongest `entity_type`. That drives which
   `SCENARIOS` variant runs.
4. The scenario object runs the sequence: move items to a stash, roll condition
   loss and item loss, apply rank and reputation loss, spawn an ambush, advance
   time, respawn the actor, and send the wakeup message.

`SCENARIOS` (`Default`, `RFDetectorStash`, `HiddenStash`, `NoLoss`) and
`entity_type` (`Stalker`, `Monster`, `Anomaly`, `Self`, `Other`) are both defined
near the top of `soulslike.script`.

### State

All mod state lives in one table reached through
`soulslike.get_soulslike_state()`, saved and loaded through the `save_state` and
`load_state` callbacks. The getter creates any missing top-level collection, so it
is safe on an old save.

### MCM

Two contracts break silently. Both have specs.

**Storage.** The key is the path, `"soulslike/<group>/<option>"`. `val` is a type
code, not an initial value: `0` string, `1` boolean, `2` float. A wrong `val` reads
and writes through the wrong type and never persists. Nothing fails loudly.

**Labels.** A node with no `text` derives its string id as
`"ui_mcm_" .. <path with / replaced by _>`. A missing translation renders the raw
string id on the settings screen. Run `tests\locals.bat` after adding, renaming, or
moving any option.

### Localisation

`gamedata/configs/text/eng/` and `gamedata/configs/text/rus/`.

The Russian files are **windows-1251**, one byte per Cyrillic letter, and must stay
that way. A file re-saved as UTF-8 still parses and every string id still resolves,
so every label spec stays green while every Russian string renders as mojibake.
This has already happened once across ten commits. VS Code guesses the encoding
wrong on open and rewrites the file on save. `tests/unit/text_encoding.spec.lua` is
the guard. Do not edit the Russian files unless asked to.

## Tests

`tests/CLAUDE.md` is the full brief. Read it before touching anything under
`tests/`. The key points:

- The suite reimplements the parts of the engine the mod touches, in pure Lua. It
  runs the mod scripts unmodified.
- Anything the engine decides gets a citation to
  [xray-monolith](https://github.com/themrdemonized/xray-monolith) or the
  [MCM repo](https://github.com/RAX-Anomaly/Anomaly-Mod-Configuration-Menu), or it
  is marked `GUESS`. A wrong fake makes a spec permanently green while it asserts
  something the game would never do.
- Self-tests gate unit and e2e. A self failure aborts the run.
- Never leave a spec red to mark a known bug. Use the baseline tables in
  `harness/mcm_labels.lua` instead, and never baseline anything a player can see.
- A fix needs a spec that went red first.
- `H.tick()` before asserting item placement. Item moves are deferred by one frame
  on purpose, because the real `transfer_item` emits a network event.
- `math.random` raises unless pinned.
