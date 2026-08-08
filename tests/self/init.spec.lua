-- Harness self-test: boot/reboot lifecycle and the spawn-point fixture.
--
-- H.reboot is what makes the save/load round-trip testable at all: a plain
-- H.boot wipes the save table, so a "reload" would have nothing to restore
-- from. It models a level change -- every script re-executes and every module
-- table is discarded, but alife_storage_manager's state survives.

local H = require("harness.init")

local MOD_SCRIPTS = { "soulslike_classes", "soulslike" }

describe("harness/init", function()

    describe("boot{ state = ... }", function()
        -- fakes.game_state is the whole save table; the mod's own state lives
        -- under the "soulslike" key (soulslike.script:210), which is what
        -- opts.state seeds.
        it("seeds the mod's sub-table of the save", function()
            H.boot{ state = { created_stashes = { [42] = { examine = true } } } }
            expect(H.fakes.game_state.soulslike.created_stashes[42].examine).toBe(true)
        end)

        it("is visible to get_soulslike_state()", function()
            H.boot{ load = MOD_SCRIPTS, state = { uuid = "seeded" } }
            expect(soulslike.get_soulslike_state().uuid).toBe("seeded")
        end)

        it("still gets the missing collections repaired onto it", function()
            H.boot{ load = MOD_SCRIPTS, state = { uuid = "seeded" } }
            expect(soulslike.get_soulslike_state().created_stashes).toBeDefined()
        end)

        it("is wiped by a plain boot", function()
            H.boot{ state = { uuid = "seeded" } }
            H.boot()
            expect(H.fakes.game_state.soulslike).toBeNil()
        end)
    end)

    describe("set_spawn()", function()

        beforeEach(function() H.boot{ load = MOD_SCRIPTS } end)

        it("records a spawn point into the save", function()
            H.set_spawn{ level = "jupiter" }
            expect(soulslike.get_soulslike_state().spawn_location.level).toBe("jupiter")
        end)

        -- Without this, RespawnActor builds a vector out of nil coordinates,
        -- which strict_vectors raises on and the engine hard-crashes on
        -- (soulslike_scenarios.script:845).
        it("gives the position real coordinates", function()
            local s = H.set_spawn{ position = { x = 10, y = 2, z = 30 } }
            expect(s.position.x).toBe(10)
            expect(s.position.z).toBe(30)
        end)

        it("returns the recorded table", function()
            expect(H.set_spawn()).toBe(soulslike.get_soulslike_state().spawn_location)
        end)
    end)

    describe("reboot()", function()

        beforeEach(function()
            H.boot{ load = MOD_SCRIPTS, soulslike_mode = true }
        end)

        it("preserves the save table across the restart", function()
            soulslike.get_soulslike_state().uuid = "survives"
            H.reboot{ load = MOD_SCRIPTS, soulslike_mode = true }
            expect(soulslike.get_soulslike_state().uuid).toBe("survives")
        end)

        it("preserves persisted vars, which live in the save too", function()
            save_var(db.actor, "grw_in_water", true)
            H.reboot{ load = MOD_SCRIPTS, soulslike_mode = true }
            expect(load_var(db.actor, "grw_in_water")).toBe(true)
        end)

        it("preserves info portions", function()
            give_info_portion("npcx_beh_test")
            H.reboot{ load = MOD_SCRIPTS, soulslike_mode = true }
            expect(has_alife_info("npcx_beh_test")).toBe(true)
        end)

        -- The point of the distinction: module state is NOT persistent. A level
        -- change re-executes every script, so file-scope locals start over.
        it("discards module tables, as a level change does", function()
            local before = soulslike
            H.reboot{ load = MOD_SCRIPTS, soulslike_mode = true }
            expect(soulslike).never.toBe(before)
        end)

        it("clears the world model", function()
            H.world.give("actor", "wpn_ak74")
            H.reboot{ load = MOD_SCRIPTS, soulslike_mode = true }
            expect(H.world.count("actor")).toBe(0)
        end)

        it("re-applies soulslike mode when asked", function()
            H.reboot{ load = MOD_SCRIPTS, soulslike_mode = true }
            expect(soulslike.IsSoulslikeMode()).toBeTruthy()
        end)
    end)

    describe("tick()", function()
        beforeEach(function() H.boot() end)

        it("drains time events before applying world mutations", function()
            local box = H.world.container("stash")
            local ak = H.world.give("actor", "wpn_ak74")
            CreateTimeEvent("t", "a", 0, function()
                db.actor:transfer_item(ak, box)
                return true
            end)
            expect(H.world.where(ak)).toBe("actor")
            H.tick()
            expect(H.world.where(ak)).toBe("stash")
        end)
    end)
end)

return true
