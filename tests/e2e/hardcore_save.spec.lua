-- End to end: hardcore saves.
--
-- Two halves, both irreversible from the player's side.
--
--   on_before_save_input  -- blocks manual saving outside the permitted spots
--   on_console_execute    -- after a save completes, DELETES every sibling save
--                            belonging to the same run, so there is only ever
--                            one restore point
--
-- The pruning walk reads each candidate off disk with io.open before decoding
-- it (soulslike.script:666), so without the save-fs shim the loop body never
-- executes and a spec asserting "nothing was deleted" would pass for entirely
-- the wrong reason.

local H = require("harness.init")

local MOD_SCRIPTS = {
    "soulslike_classes", "soulslike", "soulslike_mcm",
    "soulslike_message_factory", "soulslike_scenarios",
    "soulslike_scenario_logic_factory",
}

local UUID = "test_run_uuid"

local function boot(opts)
    opts = opts or {}
    H.boot{ load = MOD_SCRIPTS, soulslike_mode = opts.soulslike_mode ~= false }
    H.fakes.set_random_min()
    H.set_spawn{ level = "zaton" }
    H.fakes.install_save_fs()
    if opts.hardcore ~= false then
        H.fakes.set_mcm("hardcore/is_enabled", true)
    end
    soulslike.get_soulslike_state().uuid = UUID
    soulslike.on_game_start()
end

--- Attempt a manual save. Returns the flags table the handler wrote into.
local function try_save()
    local flags = {}
    SendScriptCallback("on_before_save_input", flags, nil, "quicksave")
    return flags
end

local function deleted_saves()
    local out = {}
    for _, call in ipairs(H.fakes.calls_to("delete_save_game")) do
        out[#out + 1] = call[1]
    end
    table.sort(out)
    return out
end

describe("e2e: hardcore saves", function()

    describe("blocking manual saves", function()

        describe("given hardcore saves are enabled on a normal level", function()
            local flags

            beforeEach(function()
                boot()
                flags = try_save()
            end)

            it("blocks the save", function()
                expect(flags.ret).toBe(true)
            end)

            it("tells the player why", function()
                expect(H.fakes.call_count("set_msg")).toBe(1)
            end)

            it("closes the menu", function()
                expect(H.fakes.last_call("exec_console_cmd")[1]).toBe("main_menu off")
            end)
        end)

        describe("given hardcore saves are off", function()
            it("allows the save", function()
                boot{ hardcore = false }
                expect(try_save().ret).toBeNil()
            end)
        end)

        describe("given soulslike mode is off", function()
            it("allows the save", function()
                boot{ soulslike_mode = false }
                expect(try_save().ret).toBeNil()
            end)
        end)

        describe("given campfire saves are permitted", function()
            it("allows the save", function()
                boot()
                H.fakes.set_mcm("hardcore/override_campfire_hardcore_saves", true)
                expect(try_save().ret).toBeNil()
            end)
        end)

        describe("given the player is on an invalid level", function()
            -- Underground and lab levels are not in valid_levels, and saving is
            -- left alone there rather than trapping the player.
            it("allows the save", function()
                boot()
                H.fakes.set_level("underground_lab")
                expect(try_save().ret).toBeNil()
            end)
        end)
    end)

    describe("pruning sibling saves", function()

        local function save_as(name)
            SendScriptCallback("on_console_execute", "save", name)
        end

        describe("given siblings from the same run", function()
            beforeEach(function()
                boot()
                H.fakes.set_save("current",  { soulslike = { uuid = UUID } })
                H.fakes.set_save("older",    { soulslike = { uuid = UUID } })
                H.fakes.set_save("other_run",{ soulslike = { uuid = "different" } })
                H.fakes.set_save("vanilla",  {})
                save_as("current")
            end)

            it("deletes the older sibling", function()
                expect(deleted_saves()).toEqual({ "older" })
            end)

            it("keeps the save just written", function()
                expect(deleted_saves()).never.toContain("current")
            end)

            it("keeps saves from a different run", function()
                expect(deleted_saves()).never.toContain("other_run")
            end)

            it("keeps saves with no soulslike data", function()
                expect(deleted_saves()).never.toContain("vanilla")
            end)

            -- Three files per save: the state, the position data, and the
            -- thumbnail. All are backed up before the delete.
            it("backs up all three files first", function()
                expect(H.fakes.call_count("fs.file_copy")).toBe(3)
            end)

            it("backs them up into the soulslike-backup folder", function()
                -- Called as fs:file_copy(src, dest), so the recorder sees the
                -- fs table as arg 1 and the destination as arg 3.
                local dest = H.fakes.last_call("fs.file_copy")[3]
                expect(dest).toContain("soulslike-backup/")
            end)

            it("backs up the state, position and thumbnail files", function()
                local copied = {}
                for _, call in ipairs(H.fakes.calls_to("fs.file_copy")) do
                    copied[#copied + 1] = tostring(call[2]):match("%.(%w+)$")
                end
                table.sort(copied)
                expect(copied).toEqual({ "dds", "scoc", "scop" })
            end)
        end)

        describe("given several older siblings", function()
            it("deletes all of them", function()
                boot()
                H.fakes.set_save("current", { soulslike = { uuid = UUID } })
                H.fakes.set_save("save_a",  { soulslike = { uuid = UUID } })
                H.fakes.set_save("save_b",  { soulslike = { uuid = UUID } })
                save_as("current")
                expect(deleted_saves()).toEqual({ "save_a", "save_b" })
            end)
        end)

        describe("given the save name differs only by case", function()
            -- Both sides are lowercased before comparison (:647, :678), so a
            -- save typed as "QuickSave" must not delete itself.
            it("still recognises the current save", function()
                boot()
                H.fakes.set_save("quicksave", { soulslike = { uuid = UUID } })
                save_as("QuickSave")
                expect(deleted_saves()).toEqual({})
            end)
        end)

        describe("given a save name with spaces", function()
            it("reassembles it from the console arguments", function()
                boot()
                H.fakes.set_save("my save", { soulslike = { uuid = UUID } })
                H.fakes.set_save("older",   { soulslike = { uuid = UUID } })
                SendScriptCallback("on_console_execute", "save", "my", "save")
                expect(deleted_saves()).toEqual({ "older" })
            end)
        end)

        describe("given hardcore saves are off", function()
            it("deletes nothing", function()
                boot{ hardcore = false }
                H.fakes.set_save("current", { soulslike = { uuid = UUID } })
                H.fakes.set_save("older",   { soulslike = { uuid = UUID } })
                save_as("current")
                expect(deleted_saves()).toEqual({})
            end)
        end)

        describe("given Weak-Willed Mode is enabled", function()
            -- Weak-Willed Mode is the "no safety net" option: the pruning
            -- walk still deletes every sibling save, it just skips copying
            -- each one into soulslike-backup/ first (soulslike.script:684).
            beforeEach(function()
                boot()
                H.fakes.set_mcm("hardcore/weak_willed_mode", true)
                H.fakes.set_save("current", { soulslike = { uuid = UUID } })
                H.fakes.set_save("older",   { soulslike = { uuid = UUID } })
                save_as("current")
            end)

            it("still deletes the older sibling", function()
                expect(deleted_saves()).toEqual({ "older" })
            end)

            it("does not back it up first", function()
                expect(H.fakes.call_count("fs.file_copy")).toBe(0)
            end)
        end)

        describe("given soulslike mode is off", function()
            it("deletes nothing", function()
                boot{ soulslike_mode = false }
                H.fakes.set_save("older", { soulslike = { uuid = UUID } })
                save_as("current")
                expect(deleted_saves()).toEqual({})
            end)
        end)

        describe("given this run has no uuid yet", function()
            -- The uuid is stamped on the first on_game_load
            -- (soulslike.script:857). Before that, nothing can match, and
            -- crucially nothing must be deleted on a guess.
            it("deletes nothing", function()
                boot()
                soulslike.get_soulslike_state().uuid = nil
                H.fakes.set_save("older", { soulslike = { uuid = UUID } })
                save_as("current")
                expect(deleted_saves()).toEqual({})
            end)
        end)

        describe("given a save file that cannot be read", function()
            it("skips it rather than deleting it", function()
                boot()
                H.fakes.set_save("current", { soulslike = { uuid = UUID } })
                H.fakes.set_save("corrupt", nil)
                save_as("current")
                expect(deleted_saves()).toEqual({})
            end)
        end)

        describe("given a console command other than save", function()
            it("is ignored", function()
                boot()
                H.fakes.set_save("older", { soulslike = { uuid = UUID } })
                SendScriptCallback("on_console_execute", "quit")
                expect(deleted_saves()).toEqual({})
            end)
        end)
    end)
end)

return true
