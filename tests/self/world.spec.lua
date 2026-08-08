-- Harness self-test: the item/container world model.
--
-- The deferred-mutation specs below are the load-bearing ones. If the model
-- ever silently starts snapshotting or applying immediately, item-placement
-- assertions in every scenario spec become claims about behavior the game does
-- not have.

local H = require("harness.init")
local world = H.world

describe("harness/world", function()

    local actor

    beforeEach(function()
        H.boot()
        actor = _G.db.actor
    end)

    describe("give()", function()
        describe("given a section and container", function()
            it("places the item there", function()
                local ak = world.give("actor", "wpn_ak74")
                expect(world.where(ak)).toBe("actor")
            end)

            it("shows up in contents()", function()
                world.give("actor", "wpn_ak74")
                world.give("actor", "medkit")
                expect(world.contents("actor")).toEqual({ "wpn_ak74", "medkit" })
            end)

            it("gives the item the engine accessors the mod calls", function()
                local ak = world.give("actor", "wpn_ak74", { condition = 0.8 })
                expect(ak:section()).toBe("wpn_ak74")
                expect(ak:condition()).toBeCloseTo(0.8)
                expect(ak:id()).toBeType("number")
            end)
        end)
    end)

    describe("iterate_inventory()", function()

        describe("given several items", function()
            it("visits each one", function()
                world.give("actor", "a"); world.give("actor", "b")
                local seen = {}
                actor:iterate_inventory(function(_, item)
                    seen[#seen + 1] = item:section()
                end)
                expect(seen).toEqual({ "a", "b" })
            end)
        end)

        describe("given the callback returns true", function()
            it("stops early, matching IterateInventory", function()
                world.give("actor", "a"); world.give("actor", "b")
                local seen = {}
                actor:iterate_inventory(function(_, item)
                    seen[#seen + 1] = item:section()
                    return true
                end)
                expect(seen).toEqual({ "a" })
            end)
        end)
    end)

    describe("deferred mutation", function()
        -- The engine walks the LIVE m_all container with raw iterators
        -- (script_game_object_inventory_owner.cpp:266), which is only safe
        -- because transfer_item sends GE_TRADE_* network events and
        -- alife_release queues an alife release -- both land on a later frame.

        describe("given alife_release is called inside the loop", function()
            it("leaves the item visible for the rest of that loop", function()
                -- If this fails, the model applied the removal immediately or
                -- snapshotted -- either way it no longer matches the engine.
                world.give("actor", "a")
                world.give("actor", "b")
                world.give("actor", "c")

                local seen = {}
                actor:iterate_inventory(function(_, item)
                    seen[#seen + 1] = item:section()
                    alife_release(item)          -- release every item as we go
                end)

                expect(seen).toEqual({ "a", "b", "c" })
            end)

            it("still holds the items until the next tick", function()
                local a = world.give("actor", "a")
                alife_release(a)
                expect(world.where(a)).toBe("actor")
            end)

            it("removes them once ticked", function()
                local a = world.give("actor", "a")
                alife_release(a)
                H.tick()
                expect(world.where(a)).toBeNil()
            end)

            it("reports them as destroyed", function()
                world.give("actor", "a")
                alife_release(world.item_by_section("a"))
                H.tick()
                expect(world.destroyed()).toEqual({ "a" })
            end)
        end)

        describe("given transfer_item is called inside the loop", function()
            it("does not move anything until the tick", function()
                world.container("stash")
                local a = world.give("actor", "a")
                actor:transfer_item(a, "stash")
                expect(world.where(a)).toBe("actor")
            end)

            it("moves everything on the tick", function()
                local stash = world.container("stash")
                world.give("actor", "a"); world.give("actor", "b")

                actor:iterate_inventory(function(_, item)
                    actor:transfer_item(item, stash)
                end)
                H.tick()

                expect(world.contents("stash")).toEqual({ "a", "b" })
                expect(world.contents("actor")).toEqual({})
            end)
        end)

        describe("given an item is both transferred and released", function()
            it("applies them in queue order, so the release wins", function()
                world.container("stash")
                local a = world.give("actor", "a")
                actor:transfer_item(a, "stash")
                alife_release(a)
                H.tick()
                expect(world.where(a)).toBeNil()
            end)
        end)
    end)

    describe("containers", function()
        describe("given an empty container", function()
            it("reports itself empty", function()
                local box = world.container("stash")
                expect(box:is_inv_box_empty()).toBeTruthy()
            end)
        end)

        describe("given a container with items", function()
            it("reports itself non-empty", function()
                local box = world.container("stash")
                world.give("stash", "a")
                expect(box:is_inv_box_empty()).toBeFalsy()
            end)

            it("iterates its contents", function()
                local box = world.container("stash")
                world.give("stash", "a"); world.give("stash", "b")
                local seen = {}
                box:iterate_inventory_box(function(_, item)
                    seen[#seen + 1] = item:section()
                end)
                expect(seen).toEqual({ "a", "b" })
            end)
        end)
    end)

    describe("alife_create()", function()
        describe("given a section", function()
            it("returns a server object with an id", function()
                local se = alife_create("inv_backpack", actor:position(), 1, 1)
                expect(se.id).toBeType("number")
                expect(se.section).toBe("inv_backpack")
            end)

            it("makes it findable via level.object_by_id", function()
                local se = alife_create("inv_backpack", actor:position(), 1, 1)
                expect(level.object_by_id(se.id)).toBeDefined()
            end)

            it("records the creation for assertion", function()
                alife_create("inv_backpack", actor:position(), 1, 1)
                expect(world.created).toHaveLength(1)
            end)
        end)
    end)

    describe("hide()", function()
        -- Exercises the "stash is not online yet" retry in
        -- HandleItemsAndRespawn (soulslike_scenarios.script:536).
        describe("given a created object is hidden", function()
            it("becomes invisible to level.object_by_id", function()
                local se = alife_create("inv_backpack", actor:position(), 1, 1)
                world.hide(se.id)
                expect(level.object_by_id(se.id)).toBeNil()
            end)

            it("reappears when revealed", function()
                local se = alife_create("inv_backpack", actor:position(), 1, 1)
                world.hide(se.id)
                world.reveal(se.id)
                expect(level.object_by_id(se.id)).toBeDefined()
            end)
        end)
    end)

    describe("alife_create_item()", function()
        describe("given an owner", function()
            it("puts the item in that owner's container", function()
                alife_create_item("bread", actor)
                expect(world.contents("actor")).toContain("bread")
            end)
        end)
    end)
end)

return true
