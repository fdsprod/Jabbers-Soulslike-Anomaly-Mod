-- Harness bootstrap. Require this first from any spec file.
--
--   local H = require("harness.init")
--   -- describe / it / beforeEach / expect are now ambient globals
--
--   describe("thing", function()
--     beforeEach(function() H.boot{ load = {"soulslike"} } end)
--     it("does the thing", function() expect(x).toBe(y) end)
--   end)

local M = {}

M.spec       = require("harness.spec")
M.class      = require("harness.class")
M.loader     = require("harness.loader")
M.dispatch   = require("harness.dispatch")
M.fakes      = require("harness.fakes")
M.builders   = require("harness.builders")
M.timeevents = require("harness.timeevents")
M.world      = require("harness.world")
M.mods       = require("harness.mods")

-- describe/it/expect as ambient globals, the way a TS suite gets them.
M.spec.install(_G)

-- tests/ ... /gamedata/scripts
local function default_script_dir()
    local base = os.getenv("SOULSLIKE_TESTS_DIR")
    if base and base ~= "" then
        return base .. "/../gamedata/scripts"
    end
    return "../gamedata/scripts"
end

M.booted = false

--- boot{ load = {...}, actor = {...}, soulslike_mode = true, mods = {...} }
---
--- `load` names are loaded in order (dependency order, not alphabetical).
--- `mods` are enabled BEFORE those scripts load, which matters for
--- demonized_time_events -- soulslike_scenarios captures it at file scope.
function M.boot(opts)
    opts = opts or {}

    M.fakes.reset()
    M.class.install(_G)
    M.builders.install(_G)
    M.dispatch.reset()
    M.dispatch.install(_G)

    M.timeevents.reset()
    M.timeevents.install(_G)

    M.world.reset()
    M.world.install(_G)

    -- Base-Anomaly scripts first (every install has them; two are called
    -- unguarded), then any third-party ones this spec asked for. Both happen
    -- before the mod scripts load, which matters for demonized_time_events --
    -- soulslike_scenarios captures it at file scope.
    M.mods.reset()
    M.mods.install_base()
    for _, name in ipairs(opts.mods or {}) do M.mods.enable(name) end
    for _, name in ipairs(opts.without or {}) do M.mods.disable(name) end

    M.builders.strict_vectors = opts.strict_vectors ~= false

    M.loader.reset()
    M.loader.init{
        script_dir = opts.script_dir or default_script_dir(),
        autoload   = opts.autoload,
    }
    -- Strict is applied after the mod scripts load, never during: loading them
    -- legitimately touches globals that are meant to resolve to nil.
    M.loader.strict = false

    -- Load order is dependency-driven, not alphabetical: soulslike.script
    -- constructs a TimedQueue at file scope (soulslike.script:58), so
    -- soulslike_classes must exist first. Autoload would cover it, but being
    -- explicit makes a load failure point at the right file.
    for _, name in ipairs(opts.load or {}) do
        local mod = M.loader.load(name)
        if not mod then
            error("harness: could not load mod script '" .. name .. "' from " ..
                  M.loader.script_dir, 0)
        end
    end

    if opts.actor ~= false then
        M.set_actor(opts.actor or {})
    end

    if opts.soulslike_mode then M.fakes.enable_soulslike_mode() end

    M.loader.strict = opts.strict == true

    M.booted = true
    return M
end

--- Create the actor, register it, and wire its inventory into the world model.
function M.set_actor(opts)
    local actor = M.builders.make_actor(opts or {})
    M.fakes.set_actor(actor)
    M.fakes.register_object(actor)
    M.world.attach_actor(actor, "actor")
    return actor
end

--- Advance one frame: drain deferred time events, then apply the queued
--- inventory mutations they produced. Assertions about item placement belong
--- AFTER this call -- see the deferred-mutation note in world.lua.
function M.tick()
    local events = M.timeevents.pump()
    local ops = M.world.pump()
    return events, ops
end

return M
