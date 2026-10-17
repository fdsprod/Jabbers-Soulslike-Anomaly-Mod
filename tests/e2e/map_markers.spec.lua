-- End to end: no map marker outlives the thing it points at.
--
-- A player on 0.50 reported a stash icon on the map and minimap that stays
-- after they recover their items, with no stash under it. Each describe below
-- is one way that can happen.
--
-- The engine makes this easy to get wrong (harness/fakes.lua cites each rule):
--
--   * map_add_object_spot_ser always adds a new spot, even when one of the
--     same type is already on that id.
--   * map_remove_object_spot removes only the first matching spot.
--   * Releasing an object does not remove its spots.
--
-- So every spot the mod adds needs exactly one remove, and the remove must run
-- before or after the release, never instead of it. These specs assert on what
-- is left on the map at the end, not on how many times a function was called.
-- A call count cannot see a spot that was added twice.

local H = require("harness.init")
local B = H.builders

local MOD_SCRIPTS = {
    "soulslike_classes", "soulslike", "soulslike_mcm",
    "soulslike_message_factory", "soulslike_scenarios",
    "soulslike_scenario_logic_factory",
}

local SPOT = "secondary_task_location"
local TREASURE_ID = 8080

local function live_scenario()
    return H.loader.upvalue(soulslike.wakeup_callback, "scenario_logic")
end

--- Win every keep roll and fail every loss roll, so all items reach the stash.
local function lose_nothing()
    H.fakes.set_random(function(a, b)
        if a == nil then return 0.0 end
        return b or 1
    end)
end

--- Take every item out of a box, then fire the callback the inventory UI
--- fires per item taken (ui_inventory.script:2180).
local function empty_box(id)
    local box = level.object_by_id(id)
    box:iterate_inventory_box(function(_, item) alife_release(item) end)
    H.tick()
    SendScriptCallback("actor_on_item_take_from_box", box, nil)
    H.tick()
end

describe("e2e: map markers", function()

    -- Suspect 1, the common path. The Default scenario drops a backpack and
    -- marks it. Emptying the backpack must leave nothing on the map.
    describe("given the player dies and empties the backpack", function()
        local stash_id

        beforeEach(function()
            H.boot{ load = MOD_SCRIPTS, soulslike_mode = true }
            H.fakes.set_random_min()
            H.set_spawn{ level = "zaton", position = { x = 0, y = 0, z = 0 } }
            H.set_actor{ position = { x = 0, y = 0, z = 500 } }
            B.stub_finders{ friendly_stalker = B.make_stalker{ name = "medic" } }
            H.fakes.set_ltx("itm_actor_backpack", { kind = "i_backpack" })
            H.fakes.set_mcm("debug/is_enabled", true)
            H.fakes.set_mcm("debug/debug_the_default_scenario", true)
            soulslike.on_game_start()

            H.world.give("actor", "wpn_ak74", { kind = "weapon" })
            H.world.give("actor", "medkit")
            lose_nothing()

            SendScriptCallback("actor_on_before_hit",
                { power = 50, type = hit.wound }, 1, { ret_value = true })
            SendScriptCallback("actor_on_before_death", nil, { ret_value = true })
            stash_id = live_scenario().logic_state.stash_id
            H.tick()
        end)

        it("marks the backpack once", function()
            expect(#H.fakes.spots_on(stash_id, SPOT)).toBe(1)
        end)

        it("leaves no marker on the backpack", function()
            empty_box(stash_id)
            expect(#H.fakes.spots_on(stash_id)).toBe(0)
        end)
    end)

    -- Suspect 1, the duplicate path. get_random_stash picks from the boxes
    -- that are still free (treasure_manager.script:285-310) and the mod never
    -- marks its box as used, so two deaths on one level can pick the same
    -- treasure box. Each death adds a spot on that box id.
    describe("given two Hidden Stash deaths on one level", function()
        local OTHER_ID = 8082
        local first, second

        --- One death: pick a box, create the stash, mark the box.
        local function die_once()
            local s = B.make_scenario{ class = "HiddenStashSoulslikeScenarioLogic" }
            local se = s:CreateStash()
            H.tick()
            if se then s:ApplyTransferItemsPostConditions() end
            return s
        end

        local function boot(box_ids)
            H.boot{ load = MOD_SCRIPTS, soulslike_mode = true }
            H.fakes.set_random_min()
            H.set_spawn{ level = "zaton" }
            H.set_actor{ position = { x = 10, y = 0, z = 20 } }
            B.stub_finders{}
            for i, id in ipairs(box_ids) do
                H.world.container("treasure_" .. i, {
                    id = id,
                    position = B.make_vector{ x = 300 * i, y = 0, z = 400 },
                })
            end
            -- With spawn_local set, stock get_random_stash keeps a box only if
            -- box_in_same_map(id) accepts it (treasure_manager.script:299-304),
            -- then picks one at random. The pick is pinned to the first
            -- candidate here. Both scenarios pass spawn_local = true.
            H.mods.enable("treasure_manager", {
                box_in_same_map = function() return true end,
                get_random_stash = function(_, _, spawn_local)
                    for _, id in ipairs(box_ids) do
                        if not spawn_local or treasure_manager.box_in_same_map(id) then
                            return id
                        end
                    end
                end,
            })
            soulslike.on_game_start()
        end

        describe("and two free boxes", function()
            beforeEach(function()
                boot{ TREASURE_ID, OTHER_ID }
                first = die_once()
                second = die_once()
            end)

            it("puts the second stash in the other box", function()
                expect(first.logic_state.treasure_stash_id).toBe(TREASURE_ID)
                expect(second.logic_state.treasure_stash_id).toBe(OTHER_ID)
            end)

            it("marks each box once", function()
                expect(#H.fakes.spots_on(TREASURE_ID, SPOT)).toBe(1)
                expect(#H.fakes.spots_on(OTHER_ID, SPOT)).toBe(1)
            end)

            it("leaves no marker on a box once the player opens it", function()
                SendScriptCallback("physic_object_on_use_callback",
                    level.object_by_id(TREASURE_ID), nil)
                H.tick()
                expect(#H.fakes.spots_on(TREASURE_ID)).toBe(0)
            end)
        end)

        describe("and only one box", function()
            beforeEach(function()
                boot{ TREASURE_ID }
                first = die_once()
                second = die_once()
            end)

            it("does not reuse the box for the second death", function()
                expect(second.logic_state.treasure_stash_id).toBeNil()
            end)

            it("keeps the first stash's entry", function()
                expect(soulslike.get_soulslike_state().hidden_stashes[TREASURE_ID].stash_id)
                    .toBe(first.logic_state.hidden_stash_id)
            end)

            it("marks the box once", function()
                expect(#H.fakes.spots_on(TREASURE_ID, SPOT)).toBe(1)
            end)
        end)
    end)

    -- Suspect 2. With "mark looter NPCs" on, TransferItems marks the stalker
    -- who took the player's items, with the same icon as the stash. No code
    -- removes that spot.
    describe("given a marked looter", function()
        local looter

        beforeEach(function()
            H.boot{ load = MOD_SCRIPTS, soulslike_mode = true }
            H.fakes.set_random_min()
            H.set_spawn{ level = "zaton" }
            B.stub_finders{}
            soulslike.on_game_start()

            looter = H.world.spawn_npc("looter", { name = "bandit" })
            local s = B.make_scenario{ state = {
                looter_id = looter:id(),
                looter_type = soulslike.entity_type.Stalker,
                looter = true,
                are_looter_npcs_marked = true,
            } }
            s:TransferItems(nil)
        end)

        it("marks the looter", function()
            expect(#H.fakes.spots_on(looter:id(), SPOT)).toBe(1)
        end)

        it("removes the marker when the looter dies", function()
            SendScriptCallback("npc_on_death_callback", looter, nil)
            expect(#H.fakes.spots_on(looter:id())).toBe(0)
        end)
    end)
end)
