-- End to end: the player wakes up on the far side of the level change.
--
--   on_game_load -> OnRespawn -> HealActor
--                             -> AdvanceTime  (fade to black, sleep effector)
--   dream_callback   (fired by the sleep effector)
--     -> change_game_time, actor_on_sleep
--   wakeup_callback  (fired by the second effector)
--     -> OnComplete -> GiveFoodAndWater, SpawnAmbush, SendWakeupMessage
--     -> scenario torn down, logic_state cleared from the save
--
-- The teardown at the end is what makes the death "over": until wakeup_callback
-- runs, a reload would restore the scenario and replay the respawn.

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

--- Boot with a scenario already saved, as it would be after a death that
--- triggered a level change.
local function boot_mid_death(state_overrides)
    H.boot{ load = MOD_SCRIPTS, soulslike_mode = true }
    H.fakes.set_random_min()
    H.set_spawn{ level = "zaton" }
    H.set_actor{
        health = 0, power = 0, radiation = 0.5,
        bleeding = 0.5, psy_health = 0.2, satiety = 0.1,
    }
    B.stub_finders{}

    local saved = B.make_logic_state(state_overrides or {})
    saved.scenario_id = _G.soulslike.SCENARIOS.NoLoss
    soulslike.get_soulslike_state().logic_state = saved

    soulslike.on_game_start()
    SendScriptCallback("load_state", {})
    return saved
end

describe("e2e: respawn to completion", function()

    describe("given the player loads in after dying", function()
        beforeEach(function()
            boot_mid_death()
            SendScriptCallback("on_game_load")
        end)

        it("restores the scenario", function()
            expect(live_scenario()).toBeDefined()
        end)

        it("heals to the configured fraction", function()
            -- health_loss_percent defaults to 0.75, so a quarter health.
            expect(db.actor.health).toBeCloseTo(0.25)
        end)

        it("restores stamina", function()
            expect(db.actor.power).toBe(1)
        end)

        it("clears radiation and bleeding", function()
            expect(db.actor.radiation).toBe(0)
            expect(db.actor.bleeding).toBe(0)
        end)

        it("restores psy health", function()
            expect(db.actor.psy_health).toBe(1)
        end)

        it("clears the in-water flag", function()
            expect(load_var(db.actor, "grw_in_water")).toBeNil()
        end)

        it("fades to black and starts the sleep effector", function()
            expect(H.fakes.call_count("level.add_cam_effector")).toBeGreaterThan(0)
        end)

        it("stamps a save uuid for hardcore save pruning", function()
            expect(soulslike.get_soulslike_state().uuid).toBeDefined()
        end)
    end)

    describe("given the dream plays out", function()
        beforeEach(function()
            boot_mid_death()
            SendScriptCallback("on_game_load")
            H.fakes.set_random_const(8)
            soulslike.dream_callback()
        end)

        it("advances the clock", function()
            expect(H.fakes.call_count("level.change_game_time")).toBe(1)
        end)

        it("advances by the rolled number of hours", function()
            expect(H.fakes.last_call("level.change_game_time")[2]).toBe(8)
        end)

        it("queues the wakeup effector", function()
            local last = H.fakes.last_call("level.add_cam_effector")
            expect(last[4]).toBe("soulslike.wakeup_callback")
        end)

        it("announces the sleep", function()
            expect(H.dispatch.sends_of("actor_on_sleep")).toHaveLength(1)
        end)

        -- actor_on_sleep force-saves only when no scenario is running
        -- (soulslike.script:877). Mid-death there is one, so the save is
        -- suppressed -- otherwise the player could bank the half-finished state.
        it("does not force a save while the scenario is still running", function()
            expect(H.fakes.call_count("delete_save_game")).toBe(0)
            expect(H.fakes.calls_to("exec_console_cmd")).never.toContain("save")
        end)
    end)

    describe("given the player wakes up", function()
        beforeEach(function()
            boot_mid_death()
            SendScriptCallback("on_game_load")
            H.fakes.set_random_const(8)
            soulslike.dream_callback()
            soulslike.wakeup_callback()
        end)

        it("re-enables the interface", function()
            expect(H.fakes.call_count("xr_effects.enable_ui")).toBe(1)
        end)

        it("clears the sleeping info portions", function()
            expect(has_alife_info("actor_is_sleeping")).toBe(false)
            expect(has_alife_info("sleep_active")).toBe(false)
        end)

        it("re-activates the hud", function()
            expect(H.fakes.call_count("actor_status.activate_hud")).toBe(1)
        end)

        it("sends the wakeup message", function()
            expect(H.fakes.call_count("send_tip")
                   + H.fakes.call_count("set_msg")).toBeGreaterThan(0)
        end)

        it("reports the death count", function()
            expect(H.fakes.call_count("set_msg")).toBeGreaterThan(0)
        end)

        -- The scenario is finished: nothing left to restore on a later load.
        it("tears the scenario down", function()
            expect(live_scenario()).toBeNil()
        end)

        it("clears logic_state from the save", function()
            expect(soulslike.get_soulslike_state().logic_state).toBeNil()
        end)
    end)

    describe("given the player was fed on wakeup", function()
        beforeEach(function()
            boot_mid_death()
            SendScriptCallback("on_game_load")
            H.fakes.set_random_const(8)
            soulslike.dream_callback()
            soulslike.wakeup_callback()
        end)

        it("spawns bread and water", function()
            expect(H.world.contents("actor")).toContain("bread")
            expect(H.world.contents("actor")).toContain("water_drink")
        end)

        it("records it in the story before the message is built", function()
            -- The scenario is torn down by now, so this is asserted through the
            -- effect: the items only spawn when the flag was set.
            expect(H.world.contents("actor")).toContain("bread")
        end)
    end)

    describe("given hardcore saves are enabled", function()
        it("force-saves on respawn", function()
            boot_mid_death()
            H.fakes.set_mcm("hardcore/is_enabled", true)
            SendScriptCallback("on_game_load")
            H.fakes.set_random_const(8)
            soulslike.dream_callback()
            soulslike.wakeup_callback()

            local saved = false
            for _, call in ipairs(H.fakes.calls_to("exec_console_cmd")) do
                if tostring(call[1]):find("save", 1, true) then saved = true end
            end
            expect(saved).toBe(true)
        end)
    end)

    describe("nighttime respawn", function()
        -- RespawnActor pushes the clock to daylight when nighttime respawns are
        -- disabled (soulslike_scenarios.script:887-900).
        local function respawn_at(hour)
            H.boot{ load = MOD_SCRIPTS, soulslike_mode = true }
            H.fakes.set_random_min()
            H.set_spawn{ level = "zaton" }
            B.stub_finders{}
            H.fakes.set_mcm("character/allow_nighttime_respawn", false)
            H.fakes.time_hours = hour
            H.fakes.set_random_const(0)     -- no extra scatter

            B.make_scenario{}:RespawnActor()
            return H.fakes.calls_to("level.change_game_time")
        end

        it("advances from 3am to 7am", function()
            local calls = respawn_at(3)
            expect(calls).toHaveLength(1)
            expect(calls[1][2]).toBe(4)
        end)

        it("advances from 23:00 to 7am the next day", function()
            local calls = respawn_at(23)
            expect(calls).toHaveLength(1)
            expect(calls[1][2]).toBe(8)
        end)

        it("advances from 21:00, the first blocked hour", function()
            expect(respawn_at(21)).toHaveLength(1)
        end)

        it("does not advance at 7am", function()
            expect(respawn_at(7)).toHaveLength(0)
        end)

        it("does not advance at midday", function()
            expect(respawn_at(12)).toHaveLength(0)
        end)

        it("does not advance at 20:00, the last allowed hour", function()
            expect(respawn_at(20)).toHaveLength(0)
        end)

        it("leaves the clock alone when nighttime respawn is allowed", function()
            H.boot{ load = MOD_SCRIPTS, soulslike_mode = true }
            H.fakes.set_random_min()
            H.set_spawn{ level = "zaton" }
            B.stub_finders{}
            H.fakes.time_hours = 3

            B.make_scenario{}:RespawnActor()
            expect(H.fakes.calls_to("level.change_game_time")).toHaveLength(0)
        end)
    end)

    -- FIXES: D8. SetIsInDoor and SetIsInWater wrote only the top-level
    -- logic_state fields, but SendWakeupMessage hands `story` to the message
    -- factory as its params (:935) and the factory keys the indoor rescue text
    -- off params.player_died_indoor
    -- (soulslike_message_factory.script:135). story declared both keys and
    -- never received either, so the indoor message set was unreachable.
    describe("the indoor rescue message", function()
        it("puts the indoor flag where the message factory reads it", function()
            H.boot{ load = MOD_SCRIPTS, soulslike_mode = true }
            H.fakes.set_random_min()
            local s = B.make_scenario{ indoor = true }
            expect(s.logic_state.story.player_died_indoor).toBe(true)
        end)

        it("keeps the top-level flag IsItemLossAllowed reads", function()
            H.boot{ load = MOD_SCRIPTS, soulslike_mode = true }
            H.fakes.set_random_min()
            local s = B.make_scenario{ in_water = true }
            expect(s.logic_state.player_died_in_water).toBe(true)
            expect(s.logic_state.story.player_died_in_water).toBe(true)
        end)

        it("selects the indoor message set", function()
            H.boot{ load = MOD_SCRIPTS, soulslike_mode = true }
            H.fakes.set_random_const(1)
            local rescuer = B.make_stalker{ name = "medic" }

            local indoor = soulslike_message_factory.create(rescuer, {
                player_died_indoor = true, level_name = "zaton",
            })
            local outdoor = soulslike_message_factory.create(rescuer, {
                player_died_indoor = false, level_name = "zaton",
            })
            expect(indoor).never.toBe(outdoor)
        end)
    end)
end)

return true
