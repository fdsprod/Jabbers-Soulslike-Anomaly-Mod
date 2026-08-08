-- soulslike.get_soulslike_state() (soulslike.script:207-265).
--
-- Real save-migration logic. It runs against whatever shape an older save left
-- behind, and every guard exists because some past version shipped without
-- that field. Cheap to pin, expensive to get wrong: a missed guard is a
-- nil-index crash on load for players upgrading.

local H = require("harness.init")
local fakes = H.fakes

describe("soulslike.get_soulslike_state()", function()

    beforeEach(function()
        H.boot{ load = { "soulslike_classes", "soulslike" } }
    end)

    local function state() return soulslike.get_soulslike_state() end

    describe("given a save with no soulslike data at all", function()

        beforeEach(function() fakes.game_state = {} end)

        it("creates every top-level collection", function()
            local s = state()
            expect(s.created_stashes).toBeDefined()
            expect(s.hidden_stashes).toBeDefined()
            expect(s.note_message_data).toBeDefined()
        end)

        it("creates spawn_location with its position and angle sub-tables", function()
            local s = state()
            expect(s.spawn_location).toBeDefined()
            expect(s.spawn_location.position).toBeDefined()
            expect(s.spawn_location.angle).toBeDefined()
        end)

        it("leaves spawn coordinates nil rather than zeroed", function()
            -- create_new() branches on `spawn_loc.level` being set
            -- (soulslike_scenario_logic_factory.script:164). Defaulting these
            -- to 0 would make an unset spawn look like a valid origin.
            local s = state()
            expect(s.spawn_location.level).toBeNil()
            expect(s.spawn_location.position.x).toBeNil()
            expect(s.spawn_location.game_vertex_id).toBeNil()
            expect(s.spawn_location.level_vertex_id).toBeNil()
        end)

        it("persists the state onto the save table", function()
            -- Build first: expect()'s argument is evaluated before the matcher
            -- call, so inlining state() here would capture the pre-call nil.
            local s = state()
            expect(fakes.game_state.soulslike).toBe(s)
        end)

        it("returns the same table on subsequent calls", function()
            local first = state()
            first.marker = "mine"
            expect(state().marker).toBe("mine")
        end)
    end)

    describe("given a save from a version missing one field", function()

        it("repairs a missing note_message_data", function()
            fakes.game_state = { soulslike = {
                created_stashes = {}, hidden_stashes = {}, spawn_location = {} } }
            expect(state().note_message_data).toBeDefined()
        end)

        it("repairs a missing hidden_stashes", function()
            fakes.game_state = { soulslike = {
                created_stashes = {}, note_message_data = {}, spawn_location = {} } }
            expect(state().hidden_stashes).toBeDefined()
        end)

        it("repairs a missing created_stashes", function()
            fakes.game_state = { soulslike = {
                hidden_stashes = {}, note_message_data = {}, spawn_location = {} } }
            expect(state().created_stashes).toBeDefined()
        end)

        it("repairs a missing spawn_location with its full sub-shape", function()
            fakes.game_state = { soulslike = {
                created_stashes = {}, hidden_stashes = {}, note_message_data = {} } }
            local s = state()
            expect(s.spawn_location).toBeDefined()
            expect(s.spawn_location.position).toBeDefined()
            expect(s.spawn_location.angle).toBeDefined()
        end)
    end)

    describe("given a save with data worth preserving", function()

        beforeEach(function()
            fakes.game_state = {
                soulslike = {
                    created_stashes = { [42] = { lost_items = { "wpn_ak74" } } },
                    -- hidden_stashes, note_message_data, spawn_location absent
                },
            }
        end)

        it("keeps the existing entries", function()
            local s = state()
            expect(s.created_stashes[42]).toBeDefined()
            expect(s.created_stashes[42].lost_items[1]).toBe("wpn_ak74")
        end)

        it("still adds the missing siblings", function()
            local s = state()
            expect(s.hidden_stashes).toBeDefined()
            expect(s.note_message_data).toBeDefined()
            expect(s.spawn_location).toBeDefined()
        end)
    end)

    describe("given a fully populated spawn_location", function()

        beforeEach(function()
            fakes.game_state = { soulslike = {
                created_stashes = {}, hidden_stashes = {}, note_message_data = {},
                spawn_location = {
                    level = "zaton",
                    position = { x = 1, y = 2, z = 3 },
                    angle = { x = 0, y = 0, z = 0 },
                    level_vertex_id = 111,
                    game_vertex_id = 222,
                },
            } }
        end)

        it("leaves it untouched", function()
            local s = state()
            expect(s.spawn_location.level).toBe("zaton")
            expect(s.spawn_location.position.x).toBe(1)
            expect(s.spawn_location.game_vertex_id).toBe(222)
        end)
    end)

    describe("given a bare soulslike table from an early version", function()
        -- Worst case: a save that wrote soulslike = {} and nothing else. All
        -- four repairs must run in a single pass.
        beforeEach(function() fakes.game_state = { soulslike = {} } end)

        it("runs every guard at once", function()
            local s = state()
            expect(s.created_stashes).toBeDefined()
            expect(s.hidden_stashes).toBeDefined()
            expect(s.note_message_data).toBeDefined()
            expect(s.spawn_location).toBeDefined()
            expect(s.spawn_location.position).toBeDefined()
            expect(s.spawn_location.angle).toBeDefined()
        end)
    end)

    describe("given another mod's data in the same save", function()
        it("does not disturb it", function()
            fakes.game_state = { some_other_mod = { keep = true } }
            state()
            expect(fakes.game_state.some_other_mod.keep).toBe(true)
        end)
    end)
end)

return true
