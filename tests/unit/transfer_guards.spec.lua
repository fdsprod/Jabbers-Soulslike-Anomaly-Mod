-- The two file-local guards TransferItem consults before moving an item:
-- ignore_list (soulslike_scenarios.script:30-49) and is_equipped (:208-218).
--
-- Neither is exported. Both are reached as upvalues of TransferItem, which is
-- their only caller (:1102, :1109).

local H = require("harness.init")
local B = H.builders

local MOD_SCRIPTS = {
    "soulslike_classes", "soulslike", "soulslike_mcm",
    "soulslike_message_factory", "soulslike_scenarios",
}

local ignore_list, is_equipped

local function boot()
    H.boot{ load = MOD_SCRIPTS }
    H.fakes.set_random_min()

    local transfer = _G.SoulslikeScenarioLogic.TransferItem
    ignore_list = H.loader.upvalue(transfer, "ignore_list")
    is_equipped = H.loader.upvalue(transfer, "is_equipped")
end

describe("ignore_list()", function()

    beforeEach(boot)

    it("is reachable as an upvalue of TransferItem", function()
        expect(ignore_list).toBeType("function")
    end)

    describe("given a section in the known ignore table", function()
        -- Each known section maps to an MCM key whose default is true
        -- (soulslike_mcm.script:1189), so these are protected out of the box.
        it("is ignored by default", function()
            expect(ignore_list("bolt")).toBe(true)
            expect(ignore_list("device_pda")).toBe(true)
            expect(ignore_list("itm_actor_backpack")).toBe(true)
        end)

        it("stops being ignored when its MCM toggle is off", function()
            H.fakes.set_mcm("ignored_items/ignore_bolt", false)
            expect(ignore_list("bolt")).toBe(false)
        end)

        it("does not consult the free-text list for a known section", function()
            H.fakes.set_mcm("ignored_items/ignore_bolt", false)
            H.fakes.set_mcm("ignored_items/other", "bolt")
            -- The table lookup returns early, so the free-text entry never runs.
            expect(ignore_list("bolt")).toBe(false)
        end)
    end)

    describe("given a section only in the free-text 'other' list", function()
        it("matches a single entry", function()
            H.fakes.set_mcm("ignored_items/other", "vodka")
            expect(ignore_list("vodka")).toBe(true)
        end)

        it("matches an entry in a comma-separated list", function()
            H.fakes.set_mcm("ignored_items/other", "bread,vodka,kolbasa")
            expect(ignore_list("vodka")).toBe(true)
        end)

        it("trims surrounding whitespace", function()
            H.fakes.set_mcm("ignored_items/other", "bread ,  vodka  , kolbasa")
            expect(ignore_list("vodka")).toBe(true)
        end)

        it("skips empty entries from a double comma", function()
            H.fakes.set_mcm("ignored_items/other", "bread,,vodka")
            expect(ignore_list("vodka")).toBe(true)
        end)

        it("tolerates a trailing comma", function()
            H.fakes.set_mcm("ignored_items/other", "vodka,")
            expect(ignore_list("vodka")).toBe(true)
        end)

        -- Whole-string equality, not a substring or prefix test.
        it("does not match a prefix of an entry", function()
            H.fakes.set_mcm("ignored_items/other", "vodka")
            expect(ignore_list("vod")).toBe(false)
        end)

        it("does not match a section that merely contains an entry", function()
            H.fakes.set_mcm("ignored_items/other", "medkit")
            expect(ignore_list("medkit_army")).toBe(false)
        end)
    end)

    describe("given an unlisted section", function()
        it("is not ignored", function()
            expect(ignore_list("wpn_ak74")).toBe(false)
        end)

        it("is not ignored when the free-text list is empty", function()
            H.fakes.set_mcm("ignored_items/other", "")
            expect(ignore_list("wpn_ak74")).toBe(false)
        end)
    end)

    describe("CHARACTERIZATION: the known-section list uses bare section names", function()
        -- `bandage` and `medkit` are listed bare, but Anomaly ships variants
        -- (medkit_army, medkit_scientic, bandage_army...). Those take the
        -- free-text path instead, so the shipped toggle does not cover them.
        -- Flagged as a config question rather than fixed here: widening the
        -- table changes which items players keep, which is a balance decision.
        it("protects the bare section", function()
            expect(ignore_list("medkit")).toBe(true)
        end)

        it("does not protect the army variant", function()
            expect(ignore_list("medkit_army")).toBe(false)
        end)
    end)
end)

describe("is_equipped()", function()

    beforeEach(boot)

    it("is reachable as an upvalue of TransferItem", function()
        expect(is_equipped).toBeType("function")
    end)

    describe("given the item occupies a slot", function()
        it("finds it in the first slot", function()
            local knife = B.make_item{ section = "wpn_knife" }
            H.set_actor{ slots = { [1] = knife } }
            expect(is_equipped(knife:id())).toBe(true)
        end)

        it("finds it in the helmet slot", function()
            local helm = B.make_item{ section = "helm_respirator" }
            H.set_actor{ slots = { [12] = helm } }
            expect(is_equipped(helm:id())).toBe(true)
        end)

        -- FIXES: D7. LAST_SLOT is CUSTOM_SLOT_5 = 18 in this build, because
        -- MORE_INVENTORY_SLOTS is defined (build_config_defines.h:15,
        -- inventory_space.h:40). A loop stopping at 12 leaves BACKPACK(13) and
        -- CUSTOM_1..5(14-18) looking unequipped, so those items are wrongly
        -- eligible for loss when keep_equipped_items_on_death is on.
        it("finds it in the backpack slot", function()
            local pack = B.make_item{ section = "itm_actor_backpack" }
            H.set_actor{ slots = { [13] = pack } }
            expect(is_equipped(pack:id())).toBe(true)
        end)

        it("finds it in the last custom slot", function()
            local item = B.make_item{ section = "device_torch" }
            H.set_actor{ slots = { [18] = item } }
            expect(is_equipped(item:id())).toBe(true)
        end)

        it("finds it in every slot from 1 to 18", function()
            for slot = 1, 18 do
                boot()
                local item = B.make_item{ section = "slot_probe" }
                H.set_actor{ slots = { [slot] = item } }
                expect(is_equipped(item:id())).toBe(true)
            end
        end)
    end)

    describe("given the item is not equipped", function()
        it("returns false", function()
            local loose = B.make_item{ section = "medkit" }
            H.set_actor{ slots = { [1] = B.make_item{ section = "wpn_knife" } } }
            expect(is_equipped(loose:id())).toBe(false)
        end)

        it("returns false when no slots are filled at all", function()
            local loose = B.make_item{ section = "medkit" }
            H.set_actor{ slots = {} }
            expect(is_equipped(loose:id())).toBe(false)
        end)
    end)

    describe("given slot 0", function()
        -- Slot 0 is NO_ACTIVE_SLOT and the engine rejects it outright
        -- (Inventory.cpp:658-664), so nothing there can count as equipped.
        it("never reports the item as equipped", function()
            local item = B.make_item{ section = "wpn_knife" }
            H.set_actor{ slots = { [0] = item } }
            expect(is_equipped(item:id())).toBe(false)
        end)
    end)
end)

return true
