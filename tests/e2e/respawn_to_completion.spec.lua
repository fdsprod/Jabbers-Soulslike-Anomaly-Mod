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

    -- FIXES: busy hands. An animation mod locks input while a HUD animation
    -- plays, and a timed event unlocks it when the animation ends. FDDA's
    -- enhanced_animations.script calls game.only_allow_movekeys(true) in
    -- anim_prepare and clears it in its call_my_slot_back event. Dying
    -- mid-animation sends the player through a level change, and the stock
    -- save does not keep the event queue (alife_storage_manager.script:188 and
    -- :268 have ProcessEventQueueState commented out), so the unlock never
    -- runs. The lock itself is a C++ global the level change does not reset.
    -- The player wakes up able to move and nothing else.
    describe("given an animation left the player locked", function()
        beforeEach(function()
            boot_mid_death()
            game.only_allow_movekeys(true)
            game.set_actor_allow_ladder(false)
            SendScriptCallback("on_game_load")
            H.fakes.set_random_const(8)
            soulslike.dream_callback()
            soulslike.wakeup_callback()
        end)

        it("lets the player use more than the movement keys", function()
            expect(game.only_movekeys_allowed()).toBe(false)
        end)

        it("lets the player climb ladders", function()
            expect(H.fakes.engine.allow_ladder).toBe(true)
        end)

        it("stops the scripted HUD motion", function()
            expect(H.fakes.call_count("game.stop_hud_motion")).toBe(1)
        end)

        it("force-stops every HUD blend animation", function()
            expect(H.fakes.last_call("game.stop_all_hud_anms")).toEqual({ n = 1, true })
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

    -- FIXES: nighttime respawn. RespawnActor moved the clock to 7-9am before
    -- the level change, then dream_callback added its own 6-14 hours with no
    -- check. The player woke at 13:00-23:00, and at night whenever the dream
    -- roll ran past 21:00. The check has to run where the clock last moves.
    describe("given nighttime respawn is disabled", function()
        -- The highest legal value for every roll: the most hours the dream can
        -- add, and the latest morning the check can pick.
        local function roll_max(a, b)
            if a == nil then return 0.99 end
            if b == nil then return a end
            return b
        end

        local function wake_hour_after_dying_at(hour)
            boot_mid_death()
            H.fakes.set_mcm("character/allow_nighttime_respawn", false)
            H.fakes.set_game_time(hour, 0)
            H.fakes.set_random(roll_max)

            live_scenario():RespawnActor()
            SendScriptCallback("on_game_load")
            soulslike.dream_callback()
            return level.get_time_hours()
        end

        it("wakes in daylight after dying at 3am", function()
            local hour = wake_hour_after_dying_at(3)
            expect(hour >= 7 and hour < 21).toBe(true)
        end)

        it("wakes in daylight after dying at midday", function()
            local hour = wake_hour_after_dying_at(12)
            expect(hour >= 7 and hour < 21).toBe(true)
        end)

        it("wakes between 7am and 9am when the dream runs into the night", function()
            local hour = wake_hour_after_dying_at(12)
            expect(hour >= 7 and hour <= 9).toBe(true)
        end)

        it("wakes in daylight after dying at 23:00", function()
            local hour = wake_hour_after_dying_at(23)
            expect(hour >= 7 and hour < 21).toBe(true)
        end)

        it("advances the clock only once", function()
            wake_hour_after_dying_at(3)
            expect(H.fakes.call_count("level.change_game_time")).toBe(1)
        end)
    end)

    describe("given nighttime respawn is allowed", function()
        it("keeps the rolled dream length, even into the night", function()
            boot_mid_death()
            H.fakes.set_game_time(12, 0)
            H.fakes.set_random_const(14)

            SendScriptCallback("on_game_load")
            soulslike.dream_callback()
            expect(level.get_time_hours()).toBe(2)
        end)
    end)

    describe("the nighttime respawn check", function()
        -- dream_callback rolls the dream length, then adds hours to 7-9am if
        -- the player would wake at night. The wake hour is the start hour plus
        -- a 6 hour dream roll, so each case names the hour the dream lands on.
        local function dream_lands_on(wake_hour, scatter)
            boot_mid_death()
            SendScriptCallback("on_game_load")
            H.fakes.set_mcm("character/allow_nighttime_respawn", false)
            H.fakes.set_game_time((wake_hour - 6) % 24, 0)
            H.fakes.set_random_sequence(scatter and { 6, scatter } or { 6 })

            soulslike.dream_callback()
            return H.fakes.last_call("level.change_game_time")[2]
        end

        it("adds 4 hours when the dream lands on 3am", function()
            expect(dream_lands_on(3, 0)).toBe(6 + 4)
        end)

        it("adds 8 hours when the dream lands on 23:00", function()
            expect(dream_lands_on(23, 0)).toBe(6 + 8)
        end)

        it("adds up to 2 more hours of scatter", function()
            expect(dream_lands_on(3, 2)).toBe(6 + 4 + 2)
        end)

        it("adds hours when the dream lands on 21:00, the first blocked hour", function()
            expect(dream_lands_on(21, 0)).toBe(6 + 10)
        end)

        it("adds nothing when the dream lands on 7am", function()
            expect(dream_lands_on(7)).toBe(6)
        end)

        it("adds nothing when the dream lands on midday", function()
            expect(dream_lands_on(12)).toBe(6)
        end)

        it("adds nothing when the dream lands on 20:00, the last allowed hour", function()
            expect(dream_lands_on(20)).toBe(6)
        end)

        it("reports the full sleep to actor_on_sleep", function()
            dream_lands_on(3, 0)
            expect(H.dispatch.sends_of("actor_on_sleep")[1].args[1]).toBe(10)
        end)

        it("does not move the clock in RespawnActor", function()
            H.boot{ load = MOD_SCRIPTS, soulslike_mode = true }
            H.fakes.set_random_min()
            H.set_spawn{ level = "zaton" }
            B.stub_finders{}
            H.fakes.set_mcm("character/allow_nighttime_respawn", false)
            H.fakes.set_game_time(3, 0)

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
