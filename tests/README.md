# Soulslike test harness

Runs the mod's Lua **unmodified**, outside the game engine, so scenario logic can
be exercised without launching Anomaly and dying repeatedly.

Specs are BDD — nested `describe` / `it` with a Jest-style `expect`, the same
shape as a TS suite.

```
run.bat          all specs (self-tests gate the unit specs)
run.bat self     harness self-tests only
run.bat unit     unit specs only

tools\luajit.exe probe.lua    reachability check -- see "Reachability probe"
```

Exit code is 0 on success, 1 on failure, 2 if no Lua runtime was found.

Nothing here ships to players: `deploy.bat` packages only `gamedata/`.

## Output

Results print as a tree, green `✓` for a pass, red `✗` for a failure, yellow `○`
for a pending `xit`:

```
compute_fatal_hit_info()
  power weighting
    given hits spread over time
      ✓ weights later hits more heavily
      ✗ gives the earliest hit zero weight
        expected 1000 to be 2
```

| Flag / variable | Effect |
|---|---|
| `--no-color` | plain output, no ANSI |
| `NO_COLOR` / `SPEC_NO_COLOR` | same, via the environment ([no-color.org](https://no-color.org)) |
| `FORCE_COLOR` | colour on even when `NO_COLOR` is set |
| `--ascii` or `SPEC_ASCII` | `ok` / `XX` / `--` instead of the symbols |

`run.bat` switches the console to code page 65001 for the duration of the run
and restores the previous one on exit, since the symbols are UTF-8. If you
invoke `luajit run.lua` directly from a legacy code page, pass `--ascii`.

## Runtime

Requires **LuaJIT 2.x or Lua 5.1**. Not 5.2+ — the module loader uses `setfenv`,
which was removed in 5.2.

`run.bat` looks for `luajit.exe` on PATH, then falls back to `tools\luajit.exe`.
`tools/` is gitignored; build it from the engine repo's vendored source:

```
copy  xray-monolith\src\3rd party\luajit-2  somewhere\
call  "…\VC\Auxiliary\Build\vcvars64.bat"
cd    somewhere\src
set   PATH=%CD%;%PATH%          REM msvcbuild invokes the minilua it just built
call  msvcbuild.bat static
copy  luajit.exe  <mod>\tests\tools\
```

## Layout

| Path | What |
|---|---|
| `harness/spec.lua` | BDD runner: `describe`/`it`/`beforeEach` + `expect` |
| `harness/loader.lua` | Reproduces the engine's script-module namespacing |
| `harness/class.lua` | Shim for luabind's `class` / `super` |
| `harness/dispatch.lua` | `RegisterScriptCallback` / `SendScriptCallback` registry |
| `harness/fakes.lua` | Fake engine globals (`level`, `db`, `ui_mcm`, …) |
| `harness/builders.lua` | Fixture builders (`make_actor`, `make_hit`, …) |
| `harness/world.lua` | Item/container model + the alife simulator |
| `harness/timeevents.lua` | `CreateTimeEvent` queue and pump |
| `harness/mods.lua` | Base-Anomaly and third-party script registry |
| `self/*.spec.lua` | Harness self-tests — these gate everything else |
| `unit/*.spec.lua` | Unit specs against the real mod scripts |
| `probe.lua` | Reachability check, not a test suite |

## Writing a spec

`describe` / `it` / `beforeEach` / `afterEach` / `expect` are ambient globals,
installed by `harness.init`.

```lua
local H = require("harness.init")

describe("soulslike.get_soulslike_state()", function()

  beforeEach(function()
    H.boot{ load = { "soulslike_classes", "soulslike" } }
  end)

  describe("given a save with no soulslike data at all", function()
    it("creates every top-level collection", function()
      expect(soulslike.get_soulslike_state().created_stashes).toBeDefined()
    end)
  end)
end)

return true
```

Then add the file to `SELF` or `UNIT` in `run.lua`.

### Naming

Follow the nesting the existing specs use:

```
describe("<unit under test>")
  describe("<method()>")
    describe("given <context>")
      it("<observable behavior>")
```

`it` names complete the sentence "it …" — `returns nil`, `does not raise`,
`falls back to Other`. Not `test nil return`.

### Matchers

`expect(x)` uses TS call syntax (a dot, not a colon). Prefix any matcher with
`.never` to negate it.

| | |
|---|---|
| `.toBe(v)` | identity / `==` |
| `.toEqual(v)` | deep structural equality |
| `.toBeNil()` / `.toBeDefined()` | nil checks |
| `.toBeTruthy()` / `.toBeFalsy()` | truthiness |
| `.toBeType("function")` | `type()` check |
| `.toContain(v)` | substring, or table membership |
| `.toHaveLength(n)` | `#` of a string or table |
| `.toBeCloseTo(n, tol)` | float compare, default tol `1e-9` |
| `.toBeGreaterThan(n)` / `.toBeLessThan(n)` | ordering |
| `.toThrow()` / `.toThrow("substr")` | wrap the call: `expect(function() … end).toThrow()` |

`xit("...")` marks a spec pending — reported with `○`, never run.

One gotcha: `expect()`'s argument is evaluated **before** the matcher call, so
build state first rather than inlining the call that creates it.

```lua
local s = state()                       -- do this
expect(fakes.game_state.soulslike).toBe(s)

expect(fakes.game_state.soulslike).toBe(state())   -- not this: captures nil
```

### The world model, and why you must tick

Items live in named containers. Assert final placement, not call sequences:

```lua
local ak = H.world.give("actor", "wpn_ak74", { kind = "weapon", condition = 0.8 })
local stash = H.world.container("stash")
H.world.spawn_npc("looter", { kind = "stalker", community = "bandit" })

scenario:TransferItems(stash:id())
H.tick()                                   -- REQUIRED before asserting

expect(H.world.where(ak)).toBe("stash")
expect(H.world.contents("looter")).toEqual({ "medkit" })
expect(H.world.destroyed()).toEqual({})
```

**Inventory mutations are deferred, and that is deliberate.** The engine walks
the live `m_all` container with raw iterators (`IterateInventory`,
`script_game_object_inventory_owner.cpp:266`) while the mod calls
`alife_release` and `transfer_item` from inside that loop. That is only safe
because `transfer_item` sends `GE_TRADE_SELL`/`GE_TRADE_BUY` network events
processed on a later frame. So the model queues too. Two rules follow:

- Inside `iterate_inventory`, an item you just released is **still present**.
- `TransferItems` returning does **not** mean anything moved. Tick first.

`H.tick()` drains time events and then applies the world mutations they caused.

Server and client objects are distinct, as in the engine: `alife_create` /
`alife_object` return a **server** object where `.id` is a *field*;
`level.object_by_id` returns a **client** object where `:id()` is a *method*.
`H.world.hide(id)` makes an object invisible to `level.object_by_id`, which is
how you exercise the "stash is not online yet" retry.

### Optional and base scripts

```lua
H.boot{ mods    = { "magazine_binder" } }   -- add a third-party integration
H.boot{ without = { "item_parts" } }        -- test an absent-dependency guard
```

`H.mods.BASE` (`actor_status_thirst`, `arszi_psy`, `item_parts`, `item_radio`,
`treasure_manager`) ship with Anomaly and are installed by default — two are
called unguarded, so "absent" is not a state the mod survives.
`H.mods.OPTIONAL` (`magazine_binder`, `grok_actor_damage_balancer`,
`demonized_time_events`) are third-party and absent by default.

`H.mods.patched(name)` lists fields replaced since `enable()` — use it to catch
an unrestored monkey-patch, e.g. `treasure_manager.box_in_same_map`
(soulslike_scenarios.script:1335).

### Strict globals

```lua
H.boot{ strict = true }
```

Raises on a global that resolved to nil instead of silently returning nil, so a
missing fake fails where it happens. Off by default, because nil-tolerance is
the engine's real behavior and the mod relies on it. Registered optional mods
are always exempt.

### Faking config

Every one of `soulslike_mcm`'s 60+ getters funnels through one accessor
(`soulslike_mcm.script:939`), so the **real** MCM module runs against a single
fake. Unset keys exercise each getter's declared default.

```lua
H.fakes.set_mcm("hardcore/is_enabled", true)   -- key omits the "soulslike/" prefix
```

### Determinism

`math.random` raises unless a spec pins it first — an unseeded roll is a bug,
not a default.

```lua
H.fakes.set_random_const(1)          -- always 1
H.fakes.set_random_sequence{1, 5, 3} -- in order; errors past the end
H.fakes.set_time(5000)               -- backs time_global()
```

### Testing a file-local function

`local function` at file scope is not exported, but it becomes an *upvalue* of
any exported function that references it — so it is reachable without editing
the mod:

```lua
local compute = H.loader.upvalue(
  soulslike_scenario_logic_factory.create_new, "compute_fatal_hit_info")
```

Call this from the spec, never from inside a module's environment
(`soulslike.script` shadows `debug`).

## Why self-tests gate unit specs

The harness re-implements three pieces of engine behavior. If any drifts, unit
specs keep passing while testing something the game would never execute. So a
self-test failure aborts the run before `unit/`.

The one that matters most is the module loader. The engine textually wraps every
`.script` file (`script_storage.cpp:608`), producing semantics plain `require`
does not:

| In a module | Lands as |
|---|---|
| `RELATIONS = {...}` | `soulslike.RELATIONS` (module-local) |
| `function debug(o)` | `soulslike.debug` — shadows the stdlib `debug` table |
| `function math.clamp(…)` | mutates the **shared** global `math` table |
| `function _G.IsSoulslikeMode()` | a true global |
| reading an undefined global | `nil`, **not** an error |

To confirm the harness is still load-bearing, break one semantic and check that
the run fails loudly rather than passing quietly. Removing the
`setmetatable(this, {__index = _G})` line from `loader.build_prologue` should
produce 9 self-test failures and skip `unit/` entirely.

The same applies to the world model. This must hold, and would not if the model
ever started snapshotting or applying immediately:

```lua
world.give("actor", "a"); world.give("actor", "b")
db.actor:iterate_inventory(function(_, item) alife_release(item) end)
expect(world.contents("actor")).toHaveLength(2)   -- still there
H.tick()
expect(world.contents("actor")).toHaveLength(0)   -- now gone
```

## Reachability probe

```
tools\luajit.exe probe.lua
```

Calls every non-UI mod function once and reports reachable / unreachable. It
asserts nothing about correctness — it answers "can the harness get here at
all". Currently **71 reachable, 0 unreachable**. Run it after touching the
fakes; a new FAIL means a fake regressed or the mod grew a dependency.

## Standing caveat

These specs validate mod logic against **our assumptions about the engine**. A
wrong constant in `fakes.lua` becomes a permanently green spec. Values taken
from engine source are cited in comments; anything else should be pinned against
a real game before it is trusted.

## Not covered yet

The harness reaches every non-UI function, but **specs have only been written
for a fraction of them**. Still unwritten: the scenario-selection matrix,
save/load round-trip, `SpawnAmbush`, `IsItemLossAllowed`, `TransferItem` and
the item-routing trio, the economy methods, and the full death→respawn flow.
All are reachable — see `probe.lua` for a working call of each.

Out of scope by decision: the two UI modules (`soulslike_sleep_dialog`,
`souslike_gamemode_injector_mcm`). They monkey-patch Anomaly UI classes at file
scope and need those classes to exist before they will load; they are thin
decorators, so testing them mostly tests the stub.

### Known sharp edge

`create_new` reads `spawn_location.position.x` and passes it to
`vector():set()`. Before any spawn has been recorded those are nil, and the
engine binds `set(float,float,float)` only — luabind raises `lua_cast_failed`,
which becomes `Debug.fatal`, i.e. a CTD. `RespawnActor` has the same shape at
soulslike_scenarios.script:845.

The harness reproduces this rather than coercing nil to 0, so it stays visible.
Measured: `create_new` raises on a fresh state, and stops raising after a single
`save_state` (which calls `set_spawn`). So the exposure is a death occurring
before the first save or level change. Whether Anomaly's new-game autosave
always closes that window has not been confirmed in-game.

Set `H.builders.strict_vectors = false` in a spec that needs to step past it.
