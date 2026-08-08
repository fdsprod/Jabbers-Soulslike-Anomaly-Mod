-- End to end: a death that spans a level change.
--
-- Dying triggers a ChangeLevel, and the engine unloads and re-executes every
-- script across that boundary. So the death is genuinely split in two:
--
--   [level A]  hit -> death -> stash -> transfer -> save_state -> ChangeLevel
--   ===================== scripts re-execute ======================
--   [level B]  load_state -> on_game_load -> OnRespawn -> ... -> wakeup
--
-- Nothing but the save table survives the middle. This is the journey the mod's
-- own comment at soulslike.script:790 calls fragile, and the one where a
-- regression costs the player their gear with no way back.

local H = require("harness.init")
local B = H.builders

local MOD_SCRIPTS = {
    "soulslike_classes", "soulslike", "soulslike_mcm",
    "soulslike_message_factory", "soulslike_scenarios",
    "soulslike_scenario_logic_factory",
}

local function live_scenario()
    return H.loader.upvalue(soulslike.wakeup_callback, "scenario_logic")
end

--- Wire up whichever copy of the scripts is currently loaded.
local function arm()
    H.fakes.set_random_min()
    B.stub_finders{ friendly_stalker = B.make_stalker{ name = "medic" } }
    soulslike.on_game_start()
end

local function boot_on_level(name)
    H.boot{ load = MOD_SCRIPTS, soulslike_mode = true }
    H.fakes.set_level(name or "zaton")
    H.set_spawn{ level = "zaton", position = { x = 0, y = 0, z = 0 } }
    H.set_actor{ position = { x = 0, y = 0, z = 500 }, rank = 5000 }
    H.fakes.set_mcm("debug/is_enabled", true)
    H.fakes.set_mcm("debug/debug_the_default_scenario", true)
    arm()
end

--- The other side of the ChangeLevel: same save, brand new script state.
local function change_level_to(name)
    H.reboot{ load = MOD_SCRIPTS, soulslike_mode = true }
    H.fakes.set_level(name or "jupiter")
    H.set_actor{ position = { x = 0, y = 0, z = 0 } }
    arm()
end

local function die()
    SendScriptCallback("actor_on_before_death", nil, { ret_value = true })
end

describe("e2e: a death across a level change", function()

    describe("given the player dies and the level changes", function()
        local before_state, before_scenario, stash_id

        beforeEach(function()
            boot_on_level("zaton")
            H.world.give("actor", "wpn_ak74", { kind = "weapon" })
            H.world.give("actor", "bread")

            -- Nothing lost, so the stash contents are predictable.
            H.fakes.set_random(function(a, b)
                if a == nil then return 0.0 end
                return b or 1
            end)

            die()
            H.tick()

            before_scenario = live_scenario()
            before_state = before_scenario.logic_state
            stash_id = before_state.stash_id

            SendScriptCallback("save_state", {})
            change_level_to("jupiter")
            SendScriptCallback("load_state", {})
        end)

        it("restores the scenario", function()
            expect(live_scenario()).toBeDefined()
        end)

        -- The scenario OBJECT is rebuilt: the module table holding it was
        -- discarded with the rest of the script state.
        it("rebuilds the scenario object", function()
            expect(live_scenario()).never.toBe(before_scenario)
        end)

        -- logic_state, however, is the SAME table -- save_state stored it by
        -- reference (:793) and the save survives the transition. In-game a real
        -- serialize/deserialize would yield an equal-but-distinct table, so
        -- this identity is a harness artifact; what matters, and what the rest
        -- of this block asserts, is that the contents round-trip intact.
        it("carries the state table through the save", function()
            expect(live_scenario().logic_state).toBe(before_state)
        end)

        it("keeps the scenario id", function()
            expect(live_scenario().logic_state.scenario_id)
                .toBe(before_state.scenario_id)
        end)

        it("keeps the stash id, so the player can find their gear", function()
            expect(live_scenario().logic_state.stash_id).toBe(stash_id)
        end)

        it("keeps the death location", function()
            expect(live_scenario().logic_state.death_location.position.z).toBe(500)
        end)

        it("keeps the story", function()
            expect(live_scenario().logic_state.story.level_name)
                .toBe(before_state.story.level_name)
        end)

        it("keeps the created stash registered in the save", function()
            expect(soulslike.get_soulslike_state().created_stashes[stash_id])
                .toBeDefined()
        end)

        it("keeps the spawn point", function()
            expect(soulslike.get_soulslike_state().spawn_location.level).toBe("zaton")
        end)
    end)

    describe("given the respawn completes on the new level", function()
        beforeEach(function()
            boot_on_level("zaton")
            H.world.give("actor", "bread")
            H.fakes.set_random(function(a, b)
                if a == nil then return 0.0 end
                return b or 1
            end)

            die()
            H.tick()
            SendScriptCallback("save_state", {})

            change_level_to("jupiter")
            SendScriptCallback("load_state", {})
            SendScriptCallback("on_game_load")

            H.fakes.set_random_const(8)
            soulslike.dream_callback()
            soulslike.wakeup_callback()
        end)

        it("heals the player on the far side", function()
            expect(db.actor.health).toBeCloseTo(0.25)
        end)

        it("finishes the scenario", function()
            expect(live_scenario()).toBeNil()
        end)

        it("clears logic_state from the save", function()
            expect(soulslike.get_soulslike_state().logic_state).toBeNil()
        end)

        -- The stash outlives the scenario on purpose: the player still has to
        -- walk back for it.
        it("leaves the stash registered", function()
            local stashes = soulslike.get_soulslike_state().created_stashes
            local n = 0
            for _ in pairs(stashes) do n = n + 1 end
            expect(n).toBe(1)
        end)
    end)

    describe("on_level_changing", function()
        it("records a spawn point if none exists", function()
            boot_on_level("zaton")
            soulslike.get_soulslike_state().spawn_location.level = nil
            SendScriptCallback("on_level_changing")
            expect(soulslike.get_soulslike_state().spawn_location.level).toBe("zaton")
        end)

        it("leaves an existing spawn point alone", function()
            boot_on_level("zaton")
            H.fakes.set_level("jupiter")
            SendScriptCallback("on_level_changing")
            expect(soulslike.get_soulslike_state().spawn_location.level).toBe("zaton")
        end)

        it("does not record one on fake_start", function()
            boot_on_level("fake_start")
            soulslike.get_soulslike_state().spawn_location.level = nil
            SendScriptCallback("on_level_changing")
            expect(soulslike.get_soulslike_state().spawn_location.level).toBeNil()
        end)

        it("does nothing outside soulslike mode", function()
            H.boot{ load = MOD_SCRIPTS }
            arm()
            soulslike.get_soulslike_state().spawn_location = { level = nil, position = {} }
            SendScriptCallback("on_level_changing")
            expect(soulslike.get_soulslike_state().spawn_location.level).toBeNil()
        end)
    end)

    describe("given the level changes twice before the player wakes", function()
        -- A transition can chain (respawn point on another level), so the
        -- restored state has to survive being saved again from the restored
        -- copy rather than the original.
        it("still restores the same scenario", function()
            boot_on_level("zaton")
            H.world.give("actor", "bread")
            H.fakes.set_random(function(a, b)
                if a == nil then return 0.0 end
                return b or 1
            end)

            die()
            H.tick()
            local stash_id = live_scenario().logic_state.stash_id
            SendScriptCallback("save_state", {})

            change_level_to("jupiter")
            SendScriptCallback("load_state", {})
            SendScriptCallback("save_state", {})

            change_level_to("pripyat")
            SendScriptCallback("load_state", {})

            expect(live_scenario()).toBeDefined()
            expect(live_scenario().logic_state.stash_id).toBe(stash_id)
        end)
    end)

    describe("given the save has no scenario in progress", function()
        it("loads cleanly on the far side", function()
            boot_on_level("zaton")
            SendScriptCallback("save_state", {})
            change_level_to("jupiter")
            SendScriptCallback("load_state", {})
            expect(live_scenario()).toBeNil()
        end)

        it("does not raise on game load", function()
            boot_on_level("zaton")
            SendScriptCallback("save_state", {})
            change_level_to("jupiter")
            SendScriptCallback("load_state", {})
            expect(function() SendScriptCallback("on_game_load") end).never.toThrow()
        end)
    end)
end)

return true
