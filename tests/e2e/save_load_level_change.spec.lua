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

    -- The relocation fallback must online the hidden stash holding the
    -- items, not the linked box (se_box) it's being moved to match --
    -- onlining the wrong one leaves the actual item container's online
    -- status to the engine's default distance-based logic even after being
    -- teleported.
    describe("on_game_load: hidden stash relocation", function()
        local BOX_ID, STASH_ID = 9001, 9002

        local function set_up_hidden_stash()
            H.world.container("treasure_box", {
                id = BOX_ID,
                position = B.make_vector{ x = 300, y = 0, z = 400 },
                online = true,
            })
            H.world.container("hidden_box", {
                id = STASH_ID,
                position = B.make_vector{ x = 0, y = 0, z = 0 },
            })
            H.world.hide(STASH_ID)
            soulslike.get_soulslike_state().hidden_stashes[BOX_ID] = { stash_id = STASH_ID }
        end

        beforeEach(function()
            boot_on_level("zaton")
            set_up_hidden_stash()
        end)

        it("forces the hidden stash itself online, not the linked box", function()
            SendScriptCallback("on_game_load")

            local onlined = {}
            for _, call in ipairs(H.fakes.calls_to("alife.set_switch_online")) do
                onlined[call[2]] = true
            end

            expect(onlined[STASH_ID]).toBe(true)
        end)

        it("makes the hidden stash findable via level.object_by_id afterwards", function()
            SendScriptCallback("on_game_load")
            expect(level.object_by_id(STASH_ID)).toBeDefined()
        end)

        it("moves the hidden stash to the linked box's position", function()
            SendScriptCallback("on_game_load")
            expect(H.world.server(STASH_ID).position.x).toBe(300)
            expect(H.world.server(STASH_ID).position.z).toBe(400)
        end)
    end)

    -- A save carrying a hidden stash still at the death position (not yet
    -- relocated to the treasure position its marker points at) has to
    -- recover across a real level change, not just an in-place on_game_load
    -- call: the fallback runs, then the player has to actually be able to
    -- open the box and get their items.
    describe("a hidden stash still at the wrong position, across a real level change", function()
        local BOX_ID, STASH_ID = 9201, 9202

        local function register_far_side_objects()
            H.world.container("treasure_box", {
                id = BOX_ID,
                position = B.make_vector{ x = 300, y = 0, z = 400 },
                online = true,
            })
            H.world.container("hidden_box", {
                id = STASH_ID,
                position = B.make_vector{ x = 0, y = 0, z = 0 },
            })
            H.world.give("hidden_box", "wpn_ak74")
            H.world.hide(STASH_ID)
        end

        it("lets the player retrieve their items after the level changes", function()
            boot_on_level("zaton")
            register_far_side_objects()
            soulslike.get_soulslike_state().hidden_stashes[BOX_ID] = { stash_id = STASH_ID }

            SendScriptCallback("save_state", {})
            change_level_to("jupiter")

            -- The real engine reconstructs every alife object from the save
            -- on load (m_flags survives, m_bOnline does not -- xray-monolith
            -- xrServer_Objects_ALife.cpp:366/427-476). The harness's world
            -- model only carries the mod's own game_state across H.reboot,
            -- so the stale objects are rebuilt here to model that reload.
            register_far_side_objects()

            SendScriptCallback("load_state", {})
            SendScriptCallback("on_game_load")

            local box = H.world.object(BOX_ID)
            SendScriptCallback("physic_object_on_use_callback", box, nil)
            H.tick()

            expect(H.world.contents("treasure_box")).toEqual({ "wpn_ak74" })
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
