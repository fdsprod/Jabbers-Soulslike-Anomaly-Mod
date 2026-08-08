-- save_state / load_state (soulslike.script:777-795 and :760-775).
--
-- Both are file-locals registered as callbacks, reached here as upvalues of
-- on_game_start, which closes over all thirteen handlers.
--
-- This pair carries the scenario across a ChangeLevel: the engine unloads and
-- re-executes every script, so the live scenario object cannot survive -- only
-- what save_state put into the save table does. The mod's own comment at :790
-- calls the path fragile, and it is the only route by which a death in progress
-- outlives the level transition it triggers.

local H = require("harness.init")
local B = H.builders

local MOD_SCRIPTS = {
    "soulslike_classes", "soulslike", "soulslike_mcm",
    "soulslike_message_factory", "soulslike_scenarios",
    "soulslike_scenario_logic_factory",
}

local save_state, load_state

local function bind_handlers()
    save_state = H.loader.upvalue(soulslike.on_game_start, "save_state")
    load_state = H.loader.upvalue(soulslike.on_game_start, "load_state")
end

local function boot(opts)
    opts = opts or {}
    H.boot{
        load = MOD_SCRIPTS,
        soulslike_mode = opts.soulslike_mode ~= false,
        state = opts.state,
    }
    H.fakes.set_random_min()
    H.set_spawn{ level = "zaton" }
    -- create_new consults these, and unstubbed they scan 65534 alife slots.
    B.stub_finders{ friendly_stalker = B.make_stalker{} }
    bind_handlers()
    soulslike.on_game_start()
end

--- Drive a real death so soulslike.script ends up holding a scenario, rather
--- than reaching into its file-locals to plant one. The handler takes
--- (who, flags) and writes ret_value onto flags (soulslike.script:497, :516).
local function die()
    SendScriptCallback("actor_on_before_death", nil, {})
end

--- The scenario soulslike.script is currently holding, read out of the same
--- file-local the handlers assign to.
local function live_scenario()
    return H.loader.upvalue(soulslike.wakeup_callback, "scenario_logic")
end

describe("save_state()", function()

    beforeEach(function() boot() end)

    it("is reachable as an upvalue of on_game_start", function()
        expect(save_state).toBeType("function")
    end)

    describe("given soulslike mode is off", function()
        it("writes nothing to the save", function()
            boot{ soulslike_mode = false }
            soulslike.get_soulslike_state().spawn_location.level = nil
            save_state({})
            expect(soulslike.get_soulslike_state().spawn_location.level).toBeNil()
        end)
    end)

    describe("given no spawn point has been recorded", function()
        it("records one", function()
            soulslike.get_soulslike_state().spawn_location.level = nil
            save_state({})
            expect(soulslike.get_soulslike_state().spawn_location.level).toBe("zaton")
        end)

        it("captures the actor's position", function()
            H.set_actor{ position = { x = 7, y = 8, z = 9 } }
            soulslike.get_soulslike_state().spawn_location.level = nil
            save_state({})
            local pos = soulslike.get_soulslike_state().spawn_location.position
            expect(pos.x).toBe(7)
            expect(pos.z).toBe(9)
        end)

        -- fake_start is the character-creation level; recording a spawn there
        -- would peg every future death to the intro area.
        it("does not record one on fake_start", function()
            H.fakes.set_level("fake_start")
            soulslike.get_soulslike_state().spawn_location.level = nil
            save_state({})
            expect(soulslike.get_soulslike_state().spawn_location.level).toBeNil()
        end)
    end)

    describe("given a spawn point is already recorded", function()
        it("leaves it alone", function()
            H.fakes.set_level("jupiter")
            save_state({})
            expect(soulslike.get_soulslike_state().spawn_location.level).toBe("zaton")
        end)
    end)

    describe("given no scenario is running", function()
        it("leaves logic_state absent", function()
            save_state({})
            expect(soulslike.get_soulslike_state().logic_state).toBeNil()
        end)
    end)

    describe("given a scenario is running", function()
        local scenario

        beforeEach(function()
            die()
            scenario = live_scenario()
            scenario.logic_state.stash_id = 4242
        end)

        it("persists the running scenario's state", function()
            save_state({})
            expect(soulslike.get_soulslike_state().logic_state).toBeDefined()
        end)

        it("stores the scenario id", function()
            save_state({})
            expect(soulslike.get_soulslike_state().logic_state.scenario_id).toBeDefined()
        end)

        -- CHARACTERIZATION: assigned by reference, with no serialization step
        -- (:793). Safe only because logic_state holds plain data; anything with
        -- a metatable or an engine object in it would not survive a real save.
        it("CHARACTERIZATION: stores the live table, not a copy", function()
            save_state({})
            local saved = soulslike.get_soulslike_state().logic_state
            expect(saved).toBe(live_scenario().logic_state)
        end)

        it("CHARACTERIZATION: later scenario mutations reach the save", function()
            save_state({})
            live_scenario().logic_state.stash_id = 9999
            expect(soulslike.get_soulslike_state().logic_state.stash_id).toBe(9999)
        end)
    end)

    -- CHARACTERIZATION: both handlers shadow their `data` parameter with
    -- get_soulslike_state() on the very next line (:765, :782), so the payload
    -- the callback dispatches is ignored entirely.
    describe("CHARACTERIZATION: the callback payload", function()
        it("is ignored", function()
            local payload = { sentinel = true }
            save_state(payload)
            expect(payload).toEqual({ sentinel = true })
        end)
    end)
end)

describe("load_state()", function()

    beforeEach(function() boot() end)

    it("is reachable as an upvalue of on_game_start", function()
        expect(load_state).toBeType("function")
    end)

    describe("given soulslike mode is off", function()
        it("restores nothing", function()
            boot{
                soulslike_mode = false,
                state = { logic_state = B.make_logic_state{ scenario_id = 1 } },
            }
            load_state({})
            expect(live_scenario()).toBeNil()
        end)
    end)

    describe("given the save has no logic_state", function()
        it("restores nothing", function()
            load_state({})
            expect(live_scenario()).toBeNil()
        end)

        it("does not raise", function()
            expect(function() load_state({}) end).never.toThrow()
        end)
    end)

    describe("given a logic_state with no scenario id", function()
        -- A save written mid-death by an older build. The scenario cannot be
        -- reconstructed, so the mod warns and leaves nothing running rather
        -- than guessing.
        beforeEach(function()
            boot{ state = { logic_state = B.make_logic_state{} } }
        end)

        it("restores nothing", function()
            load_state({})
            expect(live_scenario()).toBeNil()
        end)

        it("does not raise", function()
            expect(function() load_state({}) end).never.toThrow()
        end)
    end)

    describe("given a complete logic_state", function()
        local saved

        beforeEach(function()
            saved = B.make_logic_state{ rank = 4242 }
            saved.scenario_id = _G.soulslike.SCENARIOS.NoLoss
            saved.stash_id = 777
            boot{ state = { logic_state = saved } }
            load_state({})
        end)

        it("restores a scenario", function()
            expect(live_scenario()).toBeDefined()
        end)

        it("restores the right subclass", function()
            expect(H.class.is_instance(live_scenario(),
                                       _G.NoLossSoulslikeScenarioLogic)).toBe(true)
        end)

        it("adopts the saved table by reference", function()
            expect(live_scenario().logic_state).toBe(
                soulslike.get_soulslike_state().logic_state)
        end)

        it("preserves the scenario's own fields", function()
            expect(live_scenario().logic_state.stash_id).toBe(777)
            expect(live_scenario().logic_state.rank).toBe(4242)
        end)

        -- __init takes the restore branch when handed a state
        -- (soulslike_scenarios.script:227), so no MCM is re-read. A player who
        -- changed settings mid-death keeps the terms they died under.
        it("does not re-read MCM over the restored state", function()
            H.fakes.set_mcm("items/item_loss_scalar", 0.99)
            load_state({})
            expect(live_scenario().logic_state.item_loss_scalar)
                .toBeCloseTo(saved.item_loss_scalar)
        end)
    end)
end)

describe("the save/load round trip", function()

    -- H.reboot models a ChangeLevel: every script re-executes and every module
    -- table is discarded, but alife_storage_manager's state survives. That is
    -- the transition the mod's own comment at :790 flags as fragile.
    local function change_level()
        H.reboot{ load = MOD_SCRIPTS, soulslike_mode = true }
        H.fakes.set_random_min()
        bind_handlers()
        soulslike.on_game_start()
    end

    beforeEach(function() boot() end)

    describe("given a scenario was running when the level changed", function()
        local before

        beforeEach(function()
            die()
            before = live_scenario().logic_state
            before.stash_id = 4242
            before.story.items_were_lost = true

            save_state({})
            change_level()
            load_state({})
        end)

        it("restores a scenario on the far side", function()
            expect(live_scenario()).toBeDefined()
        end)

        it("restores the same scenario id", function()
            expect(live_scenario().logic_state.scenario_id).toBe(before.scenario_id)
        end)

        it("carries the stash id across", function()
            expect(live_scenario().logic_state.stash_id).toBe(4242)
        end)

        it("carries the story across", function()
            expect(live_scenario().logic_state.story.items_were_lost).toBe(true)
        end)

        it("carries the death location across", function()
            expect(live_scenario().logic_state.death_location)
                .toEqual(before.death_location)
        end)

        -- The module table really was replaced -- otherwise the round trip
        -- would be trivially "passing" against a scenario that never died.
        it("really did discard the old module state", function()
            expect(live_scenario()).never.toBe(before)
        end)
    end)

    describe("given no scenario was running", function()
        it("restores nothing across the level change", function()
            save_state({})
            change_level()
            load_state({})
            expect(live_scenario()).toBeNil()
        end)

        it("still carries the spawn point across", function()
            save_state({})
            change_level()
            expect(soulslike.get_soulslike_state().spawn_location.level).toBe("zaton")
        end)
    end)

    describe("given the save is reloaded twice", function()
        it("restores the same state each time", function()
            die()
            live_scenario().logic_state.stash_id = 4242
            save_state({})

            change_level()
            load_state({})
            expect(live_scenario().logic_state.stash_id).toBe(4242)

            save_state({})
            change_level()
            load_state({})
            expect(live_scenario().logic_state.stash_id).toBe(4242)
        end)
    end)
end)

return true
