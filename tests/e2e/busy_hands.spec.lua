-- End to end: dying while an item-use animation locks the player's hands.
--
-- FDDA plays an animation when the player uses a medkit. While it plays, the
-- player can only move, the weapons are blocked, and the hands are empty.
-- Timed events undo all three when the animation ends (see
-- harness/models/enhanced_animations.lua for the chain).
--
--   [level A]  use medkit -> 1 s later, die -> stash, transfer ->
--              RespawnActor -> ChangeLevel, about 1 s after the death
--   ========== scripts re-execute, the timed event queue is not saved ==========
--   [level B]  load_state -> on_game_load -> actor_on_first_update ->
--              dream -> wakeup
--
-- A medkit animation is 6.95 s, so FDDA's unlock events (at 6.95 s and
-- 7.05 s) are still queued when the level changes. The stock save does not
-- keep the queue (alife_storage_manager.script:188 and :268 have
-- ProcessEventQueueState commented out), so they never run. The movekeys lock
-- and the input lock are C++ globals that a level change does not reset.
--
-- If nothing on level B releases them, the player wakes up in "busy hands":
-- able to walk, unable to do anything else. Two things release them:
--   - stock actor_effects, on its first update (actor_effects.script:1854)
--   - the mod, in SoulslikeScenarioLogic:ReleaseInputLocks (OnComplete)
-- Both arms below run the whole journey, with and without actor_effects.

local H = require("harness.init")
local B = H.builders

local MOD_SCRIPTS = {
    "soulslike_classes", "soulslike", "soulslike_mcm",
    "soulslike_message_factory", "soulslike_scenarios",
    "soulslike_scenario_logic_factory",
}

local function lose_nothing()
    H.fakes.set_random(function(a, b)
        if a == nil then return 0.0 end
        return b or 1
    end)
end

local function arm()
    lose_nothing()
    B.stub_finders{ friendly_stalker = B.make_stalker{ name = "medic" } }
    soulslike.on_game_start()
end

local function boot_opts(with_actor_effects)
    return {
        load = MOD_SCRIPTS, soulslike_mode = true,
        mods = { "enhanced_animations" },
        without = (not with_actor_effects) and { "actor_effects" } or nil,
    }
end

--- Level A: the player stands with a rifle in slot 2 and a medkit in the pack.
local function boot_level_a(with_actor_effects)
    H.boot(boot_opts(with_actor_effects))
    H.fakes.set_level("zaton")
    H.set_spawn{ level = "zaton", position = { x = 0, y = 0, z = 0 } }
    H.set_actor{ position = { x = 0, y = 0, z = 500 } }
    H.fakes.set_mcm("debug/is_enabled", true)
    H.fakes.set_mcm("debug/debug_the_default_scenario", true)
    arm()

    local rifle = H.world.give("actor", "wpn_ak74", { kind = "weapon" })
    db.actor._slots[2] = rifle
    db.actor:activate_slot(2)
    return H.world.give("actor", "medkit")
end

--- Use an item the way a player does: from the inventory. While
--- only_allow_movekeys is set, the engine drops every key but movement, fire,
--- pause, drop, screenshot, quit, console and quick save/load
--- (Level_input.cpp:194-198), so the inventory never opens. Returns whether
--- the item was used.
local function use_from_inventory(item)
    if game.only_movekeys_allowed() then return false end
    enhanced_animations.use_item(item)
    return true
end

local function level_changed()
    return H.fakes.call_count("ChangeLevel") > 0
end

local function die()
    SendScriptCallback("actor_on_before_death", nil, { ret_value = true })
end

--- Everything after the ChangeLevel packet, up to the player standing up.
local function respawn_on_level_b(with_actor_effects)
    SendScriptCallback("save_state", {})
    H.reboot(boot_opts(with_actor_effects))
    H.fakes.set_level("jupiter")
    H.set_actor{ position = { x = 0, y = 0, z = 0 } }
    arm()

    SendScriptCallback("load_state", {})
    SendScriptCallback("on_game_load")
    SendScriptCallback("actor_on_first_update")
    H.fakes.set_random_const(8)
    soulslike.dream_callback()
    lose_nothing()
    soulslike.wakeup_callback()
end

describe("e2e: busy hands", function()

    -- The model has to lock and unlock the way FDDA does, or the rest of this
    -- file proves nothing. These three pin that.
    describe("given the player heals and nothing interrupts it", function()
        local medkit

        beforeEach(function()
            medkit = boot_level_a(true)
            use_from_inventory(medkit)
        end)

        it("locks the player partway through the animation", function()
            H.run_for(1000)
            expect(game.only_movekeys_allowed()).toBe(true)
            expect(db.actor:weapons_blocked()).toBe(true)
            expect(db.actor:active_slot()).toBe(0)
        end)

        it("unlocks the player when the animation ends", function()
            H.run_for(7200)
            expect(game.only_movekeys_allowed()).toBe(false)
            expect(db.actor:weapons_blocked()).toBe(false)
        end)

        it("gives the rifle back", function()
            H.run_for(7200)
            expect(db.actor:active_slot()).toBe(2)
        end)

        it("eats the medkit", function()
            H.run_for(7200)
            expect(H.fakes.calls_to("actor.eat")[1][1]).toBe(medkit)
        end)
    end)

    for _, with_actor_effects in ipairs({ true, false }) do
        local label = with_actor_effects and "with stock actor_effects"
                                          or  "without actor_effects"

        describe("given the player dies 1 s into a medkit, " .. label, function()
            local locked_at_level_change, unlocks_left

            beforeEach(function()
                local medkit = boot_level_a(with_actor_effects)
                use_from_inventory(medkit)
                H.run_for(1000)

                die()
                H.run_for(10000, { stop = level_changed })

                locked_at_level_change = game.only_movekeys_allowed()
                unlocks_left = 0
                for _, key in ipairs(H.timeevents.peek()) do
                    if key:find("^ea_") then unlocks_left = unlocks_left + 1 end
                end

                respawn_on_level_b(with_actor_effects)
            end)

            -- The precondition. If the level changed after FDDA finished, this
            -- file would not be testing busy hands at all.
            it("changes level before the animation can unlock", function()
                expect(locked_at_level_change).toBe(true)
                expect(unlocks_left).toBeGreaterThan(0)
            end)

            it("loses FDDA's unlock events in the level change", function()
                for _, key in ipairs(H.timeevents.peek()) do
                    expect(key:find("^ea_")).toBeNil()
                end
            end)

            it("wakes up able to use more than the movement keys", function()
                expect(game.only_movekeys_allowed()).toBe(false)
            end)

            it("wakes up with input enabled", function()
                expect(H.fakes.engine.input_disabled).toBe(false)
            end)

            it("wakes up with weapons unblocked", function()
                expect(db.actor:weapons_blocked()).toBe(false)
            end)

            it("can heal again, and the heal finishes", function()
                local medkit = H.world.give("actor", "medkit")
                expect(use_from_inventory(medkit)).toBe(true)
                H.run_for(7200)
                expect(game.only_movekeys_allowed()).toBe(false)
                expect(db.actor:weapons_blocked()).toBe(false)
            end)
        end)
    end
end)

return true
