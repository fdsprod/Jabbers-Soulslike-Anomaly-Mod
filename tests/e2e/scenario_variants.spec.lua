-- End to end: each of the four scenario variants, from CreateStash through
-- the transfer to ApplyTransferItemsPostConditions.
--
-- The variants differ entirely in where the player's gear ends up and how they
-- are told to find it again:
--
--   Default      backpack dropped where they died, marked straight on the PDA
--   RFDetector   gear hidden in a treasure stash, located by radio frequency
--   HiddenStash  gear hidden in a treasure stash, marked straight on the PDA
--   NoLoss       nothing taken at all
--
-- Both hidden variants spawn (and force online) at the treasure's own alife
-- position, matching where their PDA marker/radio note actually points.
--
-- Both hidden variants monkey-patch treasure_manager.box_in_same_map and
-- restore it (:1414-1421, :1500-1508). The restore runs BEFORE the nil check,
-- so it survives the early return -- which is exactly the kind of thing that
-- usually does not, hence the leak assertions.

local H = require("harness.init")
local B = H.builders

local MOD_SCRIPTS = {
    "soulslike_classes", "soulslike", "soulslike_mcm",
    "soulslike_message_factory", "soulslike_scenarios",
    "soulslike_scenario_logic_factory",
}

local TREASURE_ID = 8080

--- Boot with a treasure stash available for the hidden variants to claim.
local function boot(opts)
    opts = opts or {}
    H.boot{ load = MOD_SCRIPTS, soulslike_mode = true }
    H.fakes.set_random_min()
    H.set_spawn{ level = "zaton" }
    H.set_actor{ position = { x = 10, y = 0, z = 20 } }
    B.stub_finders{}

    if opts.treasure ~= false then
        H.world.container("treasure", {
            id = TREASURE_ID,
            position = B.make_vector{ x = 300, y = 0, z = 400 },
        })
    end

    H.mods.enable("treasure_manager", {
        get_random_stash = function()
            return opts.treasure ~= false and TREASURE_ID or nil
        end,
    })
end

local function scenario(class)
    return B.make_scenario{ class = class }
end

describe("e2e: scenario variants", function()

    describe("the Default scenario", function()
        local s, se_stash

        beforeEach(function()
            boot()
            s = scenario("DefaultSoulslikeScenarioLogic")
            se_stash = s:CreateStash()
        end)

        it("drops a backpack", function()
            expect(H.world.created[1].section).toBe("inv_backpack")
        end)

        it("returns a server object with an id field", function()
            expect(se_stash.id).toBeType("number")
        end)

        it("registers the stash in the save", function()
            expect(s.game_state.created_stashes[se_stash.id]).toBeDefined()
        end)

        it("remembers the stash id", function()
            expect(s.logic_state.stash_id).toBe(se_stash.id)
        end)

        it("marks it on the PDA afterwards", function()
            s:ApplyTransferItemsPostConditions()
            expect(s.logic_state.story.has_pda_marker).toBe(true)
            expect(H.fakes.call_count("level.map_add_object_spot_ser")).toBe(1)
        end)

        it("names the marker after the player", function()
            s:ApplyTransferItemsPostConditions()
            expect(H.fakes.last_call("level.map_add_object_spot_ser")[3])
                .toContain("Marked One")
        end)
    end)

    describe("the RF Detector scenario", function()
        local s, se_stash

        beforeEach(function()
            boot()
            s = scenario("RFDetectorSoulslikeScenarioLogic")
            se_stash = s:CreateStash()
        end)

        it("creates a hidden box", function()
            expect(H.world.created[1].section).toBe("hidden_box")
        end)

        it("places it at the treasure, not at the body", function()
            expect(H.world.created[1].container).toBeDefined()
            expect(s.logic_state.treasure_stash_id).toBe(TREASURE_ID)
        end)

        it("forces the stash online", function()
            expect(H.fakes.call_count("alife.set_switch_online")).toBe(1)
            local call = H.fakes.last_call("alife.set_switch_online")
            expect(call[2]).toBe(se_stash.id)
            expect(call[3]).toBe(true)
        end)

        it("wires the hidden stash to its radio", function()
            local entry = s.game_state.hidden_stashes[TREASURE_ID]
            expect(entry.stash_id).toBe(se_stash.id)
            expect(entry.radio_id).toBe(TREASURE_ID)
            expect(entry.radio_level).toBe("zaton")
        end)

        it("restores the treasure_manager patch", function()
            expect(H.mods.patched("treasure_manager")).toEqual({})
        end)

        describe("after the transfer", function()
            beforeEach(function()
                H.fakes.set_random_const(150)
                s:ApplyTransferItemsPostConditions()
            end)

            it("picks a radio frequency in range", function()
                expect(s.logic_state.story.radio_freq).toBeGreaterThan(29)
                expect(s.logic_state.story.radio_freq).toBeLessThan(301)
            end)

            it("registers the stash with the radio", function()
                expect(H.fakes.call_count("item_radio.add_stash")).toBe(1)
            end)

            it("gives the player a note", function()
                expect(H.world.contents("actor")).toContain(
                    "soulslike_rescuers_radio_frequency_note")
            end)

            -- The note is keyed by se_note.id. alife_create_item returns a
            -- SERVER object, so `.id` is a field; if it returned a client
            -- object this table would silently be keyed by a function and
            -- soulslike_note could never look the frequency up.
            it("keys the note data by a numeric id", function()
                local keys = {}
                for k in pairs(s.game_state.note_message_data) do
                    keys[#keys + 1] = type(k)
                end
                expect(keys).toEqual({ "number" })
            end)

            it("records the frequency against the note", function()
                for _, entry in pairs(s.game_state.note_message_data) do
                    expect(entry.freq).toBe(s.logic_state.story.radio_freq)
                    expect(entry.level_name).toBe("zaton")
                end
            end)
        end)
    end)

    describe("the Hidden Stash scenario", function()
        local s, se_stash

        beforeEach(function()
            boot()
            s = scenario("HiddenStashSoulslikeScenarioLogic")
            se_stash = s:CreateStash()
        end)

        it("creates a hidden box", function()
            expect(H.world.created[1].section).toBe("hidden_box")
        end)

        -- The PDA marker (ApplyTransferItemsPostConditions, below) points at
        -- the treasure location, so the stash itself has to live there too.
        it("places it at the treasure, not at the body", function()
            expect(H.world.created[1].container).toBeDefined()
            expect(s.logic_state.treasure_stash_id).toBe(TREASURE_ID)
            local treasure_pos = H.world.server(TREASURE_ID).position
            expect(se_stash.position.x).toBeCloseTo(treasure_pos.x)
            expect(se_stash.position.z).toBeCloseTo(treasure_pos.z)
        end)

        it("forces the stash online", function()
            expect(H.fakes.call_count("alife.set_switch_online")).toBe(1)
            local call = H.fakes.last_call("alife.set_switch_online")
            expect(call[2]).toBe(se_stash.id)
            expect(call[3]).toBe(true)
        end)

        it("registers the stash in the save", function()
            expect(s.game_state.created_stashes[se_stash.id]).toBeDefined()
        end)

        -- Asymmetric with the RF variant on purpose: no radio, so no radio_id
        -- or radio_level to record.
        it("records only the stash id against the treasure", function()
            expect(s.game_state.hidden_stashes[TREASURE_ID])
                .toEqual({ stash_id = se_stash.id })
        end)

        it("restores the treasure_manager patch", function()
            expect(H.mods.patched("treasure_manager")).toEqual({})
        end)

        it("marks the treasure on the PDA afterwards", function()
            s:ApplyTransferItemsPostConditions()
            expect(s.logic_state.story.has_stash_pda_marker).toBe(true)
            expect(H.fakes.last_call("level.map_add_object_spot_ser")[1])
                .toBe(TREASURE_ID)
        end)
    end)

    describe("the NoLoss scenario", function()
        local s

        beforeEach(function()
            boot()
            s = scenario("NoLossSoulslikeScenarioLogic")
            H.world.give("actor", "wpn_ak74", { kind = "weapon" })
            H.world.give("actor", "medkit")
        end)

        it("creates no stash", function()
            expect(s:CreateStash()).toBeNil()
            expect(H.world.created).toEqual({})
        end)

        it("transfers nothing", function()
            s:TransferItems(nil)
            H.tick()
            expect(H.world.contents("actor")).toEqual({ "wpn_ak74", "medkit" })
        end)

        it("refuses every item loss", function()
            expect(s:IsItemLossAllowed(H.world.item_by_section("wpn_ak74"))).toBe(false)
        end)

        it("respawns without a transfer", function()
            s:HandleItemsAndRespawn()
            H.tick()
            expect(H.world.contents("actor")).toEqual({ "wpn_ak74", "medkit" })
            expect(H.fakes.call_count("ChangeLevel")).toBe(1)
        end)

        -- NoLoss overrides TransferItems and IsItemLossAllowed but NOT
        -- TransferAndRespawn, which is what applies the money loss (:533).
        it("still costs the player money", function()
            H.set_actor{ money = 10000 }
            H.fakes.set_random_sequence{ 0.1, 0.5 }
            s:ApplyMoneyLoss()
            expect(db.actor:money()).toBeLessThan(10000)
        end)
    end)

    describe("given no treasure stash is available", function()
        -- The hidden variants bail out early. The restore of the monkey-patch
        -- happens before that return, so it must still be clean.
        for _, class in ipairs{ "RFDetectorSoulslikeScenarioLogic",
                                "HiddenStashSoulslikeScenarioLogic" } do
            describe(class, function()
                local s

                beforeEach(function()
                    boot{ treasure = false }
                    s = scenario(class)
                end)

                it("creates no stash", function()
                    expect(s:CreateStash()).toBeNil()
                end)

                it("does not leak the treasure_manager patch", function()
                    s:CreateStash()
                    expect(H.mods.patched("treasure_manager")).toEqual({})
                end)

                it("respawns the player anyway", function()
                    H.world.give("actor", "bread")
                    s:HandleItemsAndRespawn()
                    H.tick()
                    expect(H.fakes.call_count("ChangeLevel")).toBe(1)
                end)

                it("leaves the player's items alone", function()
                    H.world.give("actor", "bread")
                    s:HandleItemsAndRespawn()
                    H.tick()
                    expect(H.world.contents("actor")).toContain("bread")
                end)
            end)
        end
    end)

    describe("every variant", function()
        local CLASSES = {
            "DefaultSoulslikeScenarioLogic",
            "RFDetectorSoulslikeScenarioLogic",
            "HiddenStashSoulslikeScenarioLogic",
            "NoLossSoulslikeScenarioLogic",
        }

        it("stamps its own scenario id", function()
            local seen = {}
            for _, class in ipairs(CLASSES) do
                boot()
                seen[#seen + 1] = scenario(class).logic_state.scenario_id
            end
            expect(seen).toEqual{
                soulslike.SCENARIOS.Default,
                soulslike.SCENARIOS.RFDetectorStash,
                soulslike.SCENARIOS.HiddenStash,
                soulslike.SCENARIOS.NoLoss,
            }
        end)

        it("round-trips through create_by_id", function()
            for _, class in ipairs(CLASSES) do
                boot()
                local id = scenario(class).logic_state.scenario_id
                local restored = soulslike_scenario_logic_factory.create_by_id(id)
                expect(H.class.is_instance(restored, _G[class])).toBe(true)
            end
        end)

        it("reaches a respawn", function()
            for _, class in ipairs(CLASSES) do
                boot()
                H.world.give("actor", "bread")
                scenario(class):HandleItemsAndRespawn()
                H.tick()
                expect(H.fakes.call_count("ChangeLevel")).toBe(1)
            end
        end)
    end)
end)

return true
