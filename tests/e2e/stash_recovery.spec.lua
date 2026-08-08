-- End to end: the player walks back and empties their death stash.
--
--   actor_on_item_take_from_box  (fires per item taken)
--     -> once the box is empty:
--          hide_hud_inventory, map spot removed, stash released,
--          try_send_inventory_examined_message, entry cleared from the save
--
--   actor_on_stash_remove        (the "abandon stash" path)
--     -> cancels the removal, same cleanup
--
-- The examined message is the only place the player learns what did NOT
-- survive, and it is latched so it can only ever be shown once.

local H = require("harness.init")
local B = H.builders

local MOD_SCRIPTS = {
    "soulslike_classes", "soulslike", "soulslike_mcm",
    "soulslike_message_factory", "soulslike_scenarios",
    "soulslike_scenario_logic_factory",
}

local STASH_ID = 4242

--- A world where a death stash exists, optionally holding items and a record
--- of what was lost.
local function boot(opts)
    opts = opts or {}
    H.boot{ load = MOD_SCRIPTS, soulslike_mode = true }
    H.fakes.set_random_min()
    H.set_spawn{ level = "zaton" }
    soulslike.on_game_start()

    local stash = H.world.container("stash", {
        id = STASH_ID, section = opts.section or "inv_backpack",
    })

    for _, sec in ipairs(opts.contents or {}) do
        H.world.give("stash", sec)
    end

    soulslike.get_soulslike_state().created_stashes[STASH_ID] = {
        lost_items = opts.lost_items or {},
        examine = opts.examine or false,
    }

    return stash
end

--- The last examined message shown to the player, or nil.
local function examined_message()
    local call = H.fakes.last_call("give_game_news")
    return call and call[2]
end

local function take_from(stash)
    SendScriptCallback("actor_on_item_take_from_box", stash, nil)
end

describe("e2e: stash recovery", function()

    describe("given the player empties the stash", function()
        local stash

        beforeEach(function()
            stash = boot{ lost_items = { "wpn_ak74", "medkit", "medkit" } }
            take_from(stash)
        end)

        it("closes the inventory window", function()
            expect(H.fakes.call_count("hide_hud_inventory")).toBe(1)
        end)

        it("removes the map marker", function()
            expect(H.fakes.call_count("level.map_remove_object_spot")).toBe(1)
        end)

        it("releases the stash object", function()
            H.tick()
            expect(H.world.object(STASH_ID)).toBeNil()
        end)

        it("clears the stash from the save", function()
            expect(soulslike.get_soulslike_state().created_stashes[STASH_ID]).toBeNil()
        end)

        it("tells the player what was missing", function()
            expect(examined_message()).toContain("missing the following items")
        end)

        it("groups repeated sections with a count", function()
            expect(examined_message()).toContain("2 x medkit")
        end)

        it("lists a single item without a count", function()
            expect(examined_message()).toContain("wpn_ak74")
            expect(examined_message()).never.toContain("1 x wpn_ak74")
        end)
    end)

    describe("given the stash still holds items", function()
        local stash

        beforeEach(function()
            stash = boot{
                contents = { "bread", "vodka" },
                lost_items = { "wpn_ak74" },
            }
            take_from(stash)
        end)

        it("leaves the stash in place", function()
            expect(soulslike.get_soulslike_state().created_stashes[STASH_ID]).toBeDefined()
        end)

        it("keeps the map marker", function()
            expect(H.fakes.call_count("level.map_remove_object_spot")).toBe(0)
        end)

        it("says nothing yet", function()
            expect(examined_message()).toBeNil()
        end)
    end)

    describe("given nothing was lost", function()
        it("cleans up without a message", function()
            local stash = boot{ lost_items = {} }
            take_from(stash)
            expect(soulslike.get_soulslike_state().created_stashes[STASH_ID]).toBeNil()
            expect(examined_message()).toBeNil()
        end)
    end)

    describe("given the message was already shown", function()
        -- The `examine` latch exists so a stash emptied over several trips
        -- does not repeat the bad news each time.
        it("does not repeat it", function()
            local stash = boot{ lost_items = { "wpn_ak74" }, examine = true }
            take_from(stash)
            expect(examined_message()).toBeNil()
        end)
    end)

    describe("given a box that is not a death stash", function()
        it("is ignored", function()
            local other = boot{ section = "inv_box_generic" }
            take_from(other)
            expect(H.fakes.call_count("hide_hud_inventory")).toBe(0)
            expect(soulslike.get_soulslike_state().created_stashes[STASH_ID]).toBeDefined()
        end)
    end)

    describe("given the player abandons the stash from the map", function()
        local data

        beforeEach(function()
            boot{ lost_items = { "wpn_ak74" } }
            data = { stash_id = STASH_ID }
            SendScriptCallback("actor_on_stash_remove", data)
        end)

        -- The mod owns this stash's lifetime, so the engine's own removal has
        -- to be cancelled or the cleanup below runs against a dead object.
        it("cancels the engine's removal", function()
            expect(data.cancel).toBe(true)
        end)

        it("removes the map marker", function()
            expect(H.fakes.call_count("level.map_remove_object_spot")).toBe(1)
        end)

        it("shows the examined message", function()
            expect(examined_message()).toContain("missing the following items")
        end)

        it("clears the stash from the save", function()
            expect(soulslike.get_soulslike_state().created_stashes[STASH_ID]).toBeNil()
        end)
    end)

    describe("given an unrelated stash is removed", function()
        it("is left to the engine", function()
            boot{ lost_items = { "wpn_ak74" } }
            local data = { stash_id = 9999 }
            SendScriptCallback("actor_on_stash_remove", data)
            expect(data.cancel).toBeNil()
            expect(soulslike.get_soulslike_state().created_stashes[STASH_ID]).toBeDefined()
        end)
    end)

    describe("given soulslike mode is off", function()
        it("ignores the box entirely", function()
            H.boot{ load = MOD_SCRIPTS }
            H.fakes.set_random_min()
            soulslike.on_game_start()

            local stash = H.world.container("stash", {
                id = STASH_ID, section = "inv_backpack",
            })
            soulslike.get_soulslike_state().created_stashes[STASH_ID] =
                { lost_items = { "wpn_ak74" }, examine = false }

            take_from(stash)
            expect(soulslike.get_soulslike_state().created_stashes[STASH_ID]).toBeDefined()
        end)
    end)

    describe("the full round trip", function()
        -- Die, walk back, empty the stash: the state the death created must be
        -- entirely gone afterwards.
        it("leaves no trace of the stash in the save", function()
            H.boot{ load = MOD_SCRIPTS, soulslike_mode = true }
            H.fakes.set_random_min()
            H.set_spawn{ level = "zaton", position = { x = 0, y = 0, z = 0 } }
            H.set_actor{ position = { x = 0, y = 0, z = 500 } }
            B.stub_finders{ friendly_stalker = B.make_stalker{} }
            H.fakes.set_mcm("debug/is_enabled", true)
            H.fakes.set_mcm("debug/debug_the_default_scenario", true)
            soulslike.on_game_start()

            H.world.give("actor", "bread")
            H.fakes.set_random(function(a, b)
                if a == nil then return 0.0 end
                return b or 1
            end)

            SendScriptCallback("actor_on_before_death", nil, { ret_value = true })
            H.tick()

            local stash_id = H.world.created[1].id
            expect(soulslike.get_soulslike_state().created_stashes[stash_id]).toBeDefined()

            -- Empty it and hand the now-empty box back to the callback.
            local box = H.world.object(stash_id)
            for _, item in ipairs({ H.world.item_by_section("bread") }) do
                H.world.queue_release(item)
            end
            H.tick()

            take_from(box)
            expect(soulslike.get_soulslike_state().created_stashes[stash_id]).toBeNil()
        end)
    end)
end)

return true
