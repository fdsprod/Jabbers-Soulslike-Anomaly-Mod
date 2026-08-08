# tests/ — orientation for an agent

Read this before touching anything under `tests/`. `README.md` next to it is the
human-facing reference (matchers, helper signatures, worked examples); this file
is the *why*, and the rules that are not obvious from the code.

---

## What this is

A BDD suite that runs the mod's Lua **unmodified**, outside the game. No
Anomaly install, no dying repeatedly to check a change. It works by
reimplementing the parts of the engine the mod actually touches, in pure Lua.

```
tests\run.bat                     all specs        (self gates unit + e2e)
tests\run.bat self|unit|e2e       one suite
tests\run.bat --file ambush       spec files matching a substring
tests\run.bat -t "keep roll"      tests matching a substring
tests\locals.bat                  MCM localisation report + its spec
tests\tools\luajit.exe probe.lua  reachability check
```

Exit 0 pass, 1 fail, 2 no runtime / nothing matched.

Nothing here ships: `deploy.bat` packages `gamedata/` only.

### Runtime

**LuaJIT 2.x or Lua 5.1 — not 5.2+.** The module loader uses `setfenv`, removed
in 5.2. `run.bat` finds `luajit.exe` on PATH, else `tools\luajit.exe`.

`tools/` is gitignored: it is a build artifact, and the whole point is that it
comes from the same source tree as the game.

```
copy  xray-monolith\src\3rd party\luajit-2  somewhere\
call  "…\VC\Auxiliary\Build\vcvars64.bat"
cd    somewhere\src
set   PATH=%CD%;%PATH%          REM msvcbuild invokes the minilua it just built
call  msvcbuild.bat static
copy  luajit.exe  <mod>\tests\tools\
```

---

## The core bargain, and the standing risk

These specs validate **mod logic against our model of the engine**. When the
model is wrong, the spec is not merely useless — it is *permanently green*
while asserting something the game would never do. That is the single failure
mode to design against.

So the rule is: **anything the engine decides gets a citation, or it does not
go in.**

Two upstreams:

| What | Source |
|---|---|
| Engine behaviour — bindings, types, clamping, lifetimes | <https://github.com/themrdemonized/xray-monolith> |
| MCM option schema, storage paths, label derivation | <https://github.com/RAX-Anomaly/Anomaly-Mod-Configuration-Menu> |

Anomaly's own gamedata scripts (`_g.script`, `utils_item.script`, …) are a
third: several things that *look* like engine behaviour are Lua, and the
difference matters. `CreateTimeEvent` and `alife_create` are Lua; `iterate_inventory`
and `transfer_item` are C++.

### How to add a fake faithfully

1. Find the real thing. Grep the engine repo for the binding
   (`script_game_object_*.cpp`, `alife_simulator_script.cpp`,
   `xrServer_Objects_script.cpp`), or the MCM repo for UI contracts.
2. Copy the *semantics*, not a plausible guess — return type, whether it
   clamps, whether it is deferred, what it does on nil.
3. Cite `file.cpp:line` in a comment at the fake.
4. If you cannot verify it, mark it `GUESS` explicitly. `harness/fakes.lua`
   opens with this convention; keep it.

Facts already established this way are tabulated in `README.md` under
*Standing caveat*. Consult it before assuming — several are counter-intuitive:

- Inventory slots run **1..18**, not 1..12. Slot 0 is `NO_ACTIVE_SLOT`.
- `iterate_inventory` stops on **any truthy** return; `CreateTimeEvent`
  re-queues on anything **not literally `true`**. Opposite conventions, easy
  to conflate.
- Server objects expose `id`/`position` as **fields**; client objects as
  **methods**. Conflating them yields a table keyed by a function.
- `give_money(-N)` does **not** clamp — it underflows u32.
- `set_character_rank` truncates **toward zero**, not floor, and never clamps.
- Grenades are **not** weapons at either layer.
- `vector():set(nil,…)` is **UB in release** — `NDEBUG` compiles out luabind's
  no-overload guard. Not catchable. The harness raises so it stays visible;
  call sites are guarded instead.

---

## How the pieces fit

```
harness/spec.lua        describe / it / expect, the runner
harness/loader.lua      reproduces the engine's script-module namespacing
harness/class.lua       luabind class / super
harness/dispatch.lua    RegisterScriptCallback / SendScriptCallback
harness/fakes.lua       engine globals: level, db, ui_mcm, alife, …
harness/builders.lua    fixtures: actors, npcs, items, logic_state, scenarios
harness/world.lua       item/container model + the alife simulator
harness/timeevents.lua  CreateTimeEvent queue and pump
harness/mods.lua        base-Anomaly and third-party script registry
harness/mcm_labels.lua  MCM label derivation, analysis, and its baselines
harness/init.lua        H.boot / H.tick / H.reboot — start here
```

### The loader is the load-bearing piece

The engine textually wraps every `.script` before compiling it
(`script_storage.cpp:608`). That produces semantics plain `require` does not,
and the mod depends on all of them:

| In a module | Lands as |
|---|---|
| `RELATIONS = {...}` | `soulslike.RELATIONS` — module-local, not global |
| `function debug(o)` | `soulslike.debug`, shadowing the stdlib `debug` table |
| `function math.clamp(…)` | mutates the **shared** `math` table |
| `function _G.IsSoulslikeMode()` | a true global |
| reading an undefined global | `nil`, **not** an error |

If this drifts, every unit spec keeps passing while testing something the game
would never run. That is why **self-tests gate unit and e2e**: a self failure
aborts before the rest.

To confirm the gate still bites, break one semantic — remove the
`setmetatable(this, {__index = _G})` line from `loader.build_prologue` — and
check the run fails loudly rather than passing quietly.

### Deferred mutation is deliberate

`iterate_inventory` walks the live container with raw iterators while the mod
calls `alife_release` and `transfer_item` from inside that loop. That is only
safe because `transfer_item` emits network events processed on a later frame.
So `world.lua` queues too:

- Inside `iterate_inventory`, an item you just released is **still present**.
- `TransferItems` returning does **not** mean anything moved.
- **`H.tick()` before asserting placement.** `H.tick{ passes = 1 }` runs one
  frame and leaves retries queued, which is how you observe a wait mid-flight.

Snapshotting instead would give the same loop coverage for the wrong reason.

---

## Rules for writing specs

**Assert correct behaviour.** The suite ends green. A defect found while
writing a spec gets *fixed*, with the spec failing first to prove it caught
something. Three markers flag exceptions:

| Marker | Meaning |
|---|---|
| `FIXES: Dn` | This spec caught a defect. It went red, then the fix landed. |
| `CHARACTERIZATION:` | Behaviour deliberately left alone, pinned so a change is deliberate. |
| `DEAD CODE:` | Unreachable branch, with the gate that disables it cited. |

**Never leave a spec red to represent a known bug.** A permanently failing
suite destroys the signal for every future change. Where current breakage must
be tolerated, record it in an explicit **baseline table** with a guard
asserting the baseline itself is still accurate — see `harness/mcm_labels.lua`.
A stale baseline is worse than a plain break: it masks the next one in that slot.

**But do not baseline something a player can see.** This is the failure mode
that actually happened here: four MCM labels had no translation and rendered as
literal `ui_mcm_soulslike_debug_debug_squad_spawns` text in the shipped
settings menu. They were baselined, so `run.bat` reported PASS — green while
visibly broken, which is precisely what this suite exists to prevent. The
`MISSING_ENG` table is empty now and should stay empty.

Before baselining anything, ask: *would a player notice this?* If yes, it is a
defect, and the fix belongs in the same change as the spec that caught it.

**Separate defects from debt.** Untranslated strings are outstanding work, not
bugs. They are reported on every run so the count cannot quietly grow, but they
do not fail a build unless `--strict` is passed. Conflating the two either
blocks work on translation or hides real breakage in a pile of it.

**Determinism.** `math.random` raises unless pinned. Budgets matter — assert
them with `H.fakes.random_count()`. Some functions spend rolls of different
call forms wanting opposite values (`TransferItem` wants a high `math.random()`
and a low `math.random(0,100)`); use a predicate on the call form, not a
constant.

**Reaching file-locals.** A `local function` becomes an *upvalue* of any
exported function referencing it, so no mod edit is needed:

```lua
local f = H.loader.upvalue(_G.SoulslikeScenarioLogic.TransferItem, "ignore_list")
```

Pick the anchor that genuinely closes over it. Anchoring on the wrong function
resolves nil and the spec silently tests nothing — that exact bug lived in
`probe.lua` for a while.

**Naming.** `describe("<unit>") > describe("<method()>") > describe("given
<context>") > it("<observable behaviour>")`. `it` names complete the sentence
"it …".

**Adding a file.** Drop it in `self/`, `unit/` or `e2e/`; discovery picks it
up. Discovery sorts alphabetically, so specs must not depend on load order.

---

## MCM specifically

Two independent contracts, both from the MCM repo, both silently breakable.

**Storage.** The key is the path: `"<root>/<group>/<option>"`, resolved by
`ui_mcm.get`. `val` is a required **type code** — `0` string, `1` boolean,
`2` float — *not* an initial value. A mismatch does not fail loudly; the option
reads and writes through the wrong type and never persists. `unit/mcm_options.spec.lua`
walks the tree asserting this, and cross-references it against the keys the
getters actually read — discovered by driving each getter through a recording
`ui_mcm`, never by restating them.

**Labels.** A node with no `text` derives `"ui_mcm_" .. <path with / → _>`, so
`allow_weapon_loss` in group `items` needs
`ui_mcm_soulslike_items_allow_weapon_loss`. A miss renders the raw string id on
screen and nothing else reports it. Tooltips are looked up at `<key>_desc` and
are optional.

`locals.bat` reports this in both directions. Checking both is what makes a
rename obvious: the new id has no translation **and** the old translation is
orphaned, so one mistake fails two assertions pointing at each other.

Because the whole MCM module funnels through one accessor, faking `ui_mcm.get`
alone makes the **real** 1200-line module run. Unset keys exercise each
getter's declared default.

---

## Before you claim it works

- `tests\run.bat` exits 0.
- `probe.lua` still reports 0 unreachable.
- A fix has a spec that **went red first**. If it never failed, it proves
  nothing — delete it or make it meaningful.
- Engine-derived constants carry citations.
- `git diff gamedata/` reviewed on its own. The mod changes are the risky half;
  they should read as targeted fixes, not incidental churn.
- Say plainly what was *not* verified. None of this runs the actual game — a
  green suite is evidence about logic, not about Anomaly.
