-- End to end: the player finds and opens their RF Detector / Hidden Stash
-- marker box (physic_object_on_use_callback), pulling their gear out of the
-- real hidden stash and into the box they can see.

local H = require("harness.init")
local B = H.builders

local MOD_SCRIPTS = {
    "soulslike_classes", "soulslike", "soulslike_mcm",
    "soulslike_message_factory", "soulslike_scenarios",
    "soulslike_scenario_logic_factory",
}

local TREASURE_ID, STASH_ID = 8080, 8081

--- A world where a hidden stash exists behind a linked marker box, optionally
--- holding items, optionally registered for a radio frequency, and optionally
--- still offline.
local function boot(opts)
    opts = opts or {}
    H.boot{ load = MOD_SCRIPTS, soulslike_mode = true }
    H.fakes.set_random_min()
    H.set_spawn{ level = "zaton" }
    soulslike.on_game_start()

    local box = H.world.container("treasure_box", { id = TREASURE_ID })
    H.world.container("hidden_stash", { id = STASH_ID })

    for _, sec in ipairs(opts.contents or {}) do
        H.world.give("hidden_stash", sec)
    end

    soulslike.get_soulslike_state().hidden_stashes[TREASURE_ID] = {
        stash_id = STASH_ID,
        radio_id = opts.radio_id,
        radio_level = opts.radio_id and "zaton" or nil,
    }

    if opts.offline then H.world.hide(STASH_ID) end

    return box
end

local function use_box(box)
    SendScriptCallback("physic_object_on_use_callback", box, nil)
end

describe("e2e: RF Detector / Hidden Stash recovery", function()

    describe("given the linked box is used and the hidden stash is online", function()
        local box

        beforeEach(function()
            box = boot{ contents = { "wpn_ak74", "medkit" } }
            use_box(box)
            H.tick()
        end)

        it("transfers the items into the box the player can see", function()
            expect(H.world.contents("treasure_box")).toEqual({ "wpn_ak74", "medkit" })
        end)

        it("empties the hidden stash", function()
            expect(H.world.contents("hidden_stash")).toEqual({})
        end)

        it("removes the PDA marker for the box", function()
            expect(H.fakes.call_count("level.map_remove_object_spot")).toBe(1)
            expect(H.fakes.last_call("level.map_remove_object_spot")[1]).toBe(TREASURE_ID)
        end)

        it("releases the hidden stash object", function()
            expect(H.world.object(STASH_ID)).toBeNil()
        end)

        it("clears the hidden stash entry from the save", function()
            expect(soulslike.get_soulslike_state().hidden_stashes[TREASURE_ID]).toBeNil()
        end)
    end)

    describe("given the stash was registered for a radio frequency", function()
        it("clears the radio registration", function()
            local box = boot{ radio_id = TREASURE_ID }
            use_box(box)
            expect(H.fakes.call_count("item_radio.clear_stash")).toBe(1)
            local call = H.fakes.last_call("item_radio.clear_stash")
            expect(call[1]).toBe("zaton")
            expect(call[2]).toBe(TREASURE_ID)
        end)
    end)

    describe("given the stash was not registered for a radio frequency", function()
        -- HiddenStash marks the treasure on the PDA instead of handing out a
        -- radio note, so its hidden_stashes entry carries no radio_id.
        it("does not touch the radio at all", function()
            local box = boot()
            use_box(box)
            expect(H.fakes.call_count("item_radio.clear_stash")).toBe(0)
        end)
    end)

    -- Mirrors the warn-and-bail path in physic_object_on_use_callback: the
    -- stash id is registered but level.object_by_id can't find it yet.
    describe("given the hidden stash is still offline", function()
        local box

        beforeEach(function()
            box = boot{ contents = { "wpn_ak74" }, offline = true }
        end)

        it("does not crash", function()
            expect(function() use_box(box) end).never.toThrow()
        end)

        it("does not transfer anything", function()
            use_box(box)
            H.tick()
            expect(H.world.contents("treasure_box")).toEqual({})
        end)

        it("removes the now-invalid PDA marker for the box", function()
            use_box(box)
            expect(H.fakes.call_count("level.map_remove_object_spot")).toBe(1)
            expect(H.fakes.last_call("level.map_remove_object_spot")[1]).toBe(TREASURE_ID)
        end)

        it("leaves the hidden stash entry in the save for a future retry", function()
            use_box(box)
            expect(soulslike.get_soulslike_state().hidden_stashes[TREASURE_ID]).toBeDefined()
        end)
    end)

    describe("given the box is not linked to any hidden stash", function()
        it("is ignored", function()
            boot()
            local unrelated = H.world.container("unrelated_box", { id = 9999 })
            expect(function() use_box(unrelated) end).never.toThrow()
            expect(soulslike.get_soulslike_state().hidden_stashes[TREASURE_ID]).toBeDefined()
        end)
    end)

    describe("given the box is not an invbox at all", function()
        it("is ignored", function()
            boot()
            local not_a_box = B.make_stalker{ name = "passerby" }
            expect(function() use_box(not_a_box) end).never.toThrow()
        end)
    end)
end)

return true
