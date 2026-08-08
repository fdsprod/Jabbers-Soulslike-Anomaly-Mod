-- MCM labels against the localisation tables, in both directions.
--
-- MCM derives an option's on-screen label from its path when the node has no
-- explicit `text`: "ui_mcm_" plus the path with "/" replaced by "_". So
--
--   { id = "allow_weapon_loss", type = "check", val = 1, def = true }
--
-- in group `items` under root `soulslike` needs the string id
-- `ui_mcm_soulslike_items_allow_weapon_loss`. Nothing validates that at load
-- time: game.translate_string returns the raw id on a miss, so a broken entry
-- shows in the menu as the literal string id and nowhere else. Renaming an
-- option id silently breaks its label.
--
-- Checking both directions is what makes a rename obvious -- the new id has no
-- translation AND the old translation is orphaned, so one mistake fails two
-- assertions that point at each other.
--
-- The derivation, the analysis and the baselines all live in
-- harness/mcm_labels.lua, shared with locals.lua so there is one copy. Run
-- `locals.bat` for the same findings as a readable report.

local H = require("harness.init")
local labels = require("harness.mcm_labels")

local MOD_SCRIPTS = { "soulslike_classes", "soulslike", "soulslike_mcm" }

local result, tree, eng, rus

local function boot()
    H.boot{ load = MOD_SCRIPTS }
    H.fakes.set_random_min()
    eng = H.loader.load_string_table("eng")
    rus = H.loader.load_string_table("rus")
    result, tree = labels.inspect()
end

describe("MCM localisation", function()

    beforeEach(boot)

    describe("the string tables", function()
        it("loads the English table", function()
            expect(eng["ui_mcm_menu_soulslike"]).toBe(true)
        end)

        it("loads the Russian table", function()
            expect(rus["ui_mcm_menu_soulslike"]).toBe(true)
        end)

        -- The root carries no `text`, so MCM derives ui_mcm_menu_<root id> for
        -- the mod's entry in the settings list.
        it("names the mod's own menu entry", function()
            expect(eng["ui_mcm_menu_" .. labels.ROOT]).toBe(true)
        end)

        it("finds every option in the tree", function()
            expect(#labels.labels(tree)).toBeGreaterThan(0)
        end)
    end)

    describe("every node's label exists in English", function()
        -- The direction that matters most: this is what a player sees.
        it("has no new missing keys", function()
            expect(result.missing_eng.new).toEqual({})
        end)

        it("translates every group heading", function()
            expect(result.groups).toEqual({})
        end)
    end)

    describe("every node's label is a string id", function()
        -- A literal renders, since translate_string passes unknown input
        -- through unchanged, but it can never be translated.
        it("has no new hardcoded English", function()
            expect(result.literal.new).toEqual({})
        end)
    end)

    describe("every translation has a node", function()
        -- An orphan is usually a rename: the option moved and its old string
        -- stayed behind, so the new one shows a raw id while the old
        -- translation sits unused.
        it("has no new orphans", function()
            expect(result.orphan.new).toEqual({})
        end)
    end)

    describe("Russian parity", function()
        -- Lower severity than a missing English key -- an English speaker never
        -- sees it -- but a Russian player gets the raw id just the same.
        it("has no newly untranslated labels", function()
            expect(result.missing_rus.new).toEqual({})
        end)
    end)

    describe("the baselines", function()
        -- A baseline entry that no longer describes reality is worse than a
        -- plain break: it masks the next regression in that slot. Deleting a
        -- stale entry is the fix, never updating it to match.
        it("all still describe reality", function()
            expect(result.stale).toEqual({})
        end)

        it("account for everything currently broken", function()
            local known = #result.missing_eng.known + #result.literal.known
                        + #result.orphan.known + #result.missing_rus.known
            expect(known).toBeGreaterThan(0)
        end)
    end)

    describe("the derivation rule itself", function()
        -- Pins the concatenation, since every assertion above depends on it.
        local function label_for(id)
            for _, label in ipairs(labels.labels(tree)) do
                if label.id == id then return label end
            end
        end

        it("joins root, group and option with underscores", function()
            expect(label_for("allow_weapon_loss").key)
                .toBe("ui_mcm_soulslike_items_allow_weapon_loss")
        end)

        it("prefers an explicit text over the derived key", function()
            local found = label_for("allow_rank_loss")
            expect(found.explicit).toBe(true)
            expect(found.key).toBe("ui_mcm_soulslike_character_allow_rank_loss")
        end)

        -- Renaming an option id moves its label key, which is exactly how these
        -- break in practice.
        it("ties the key to the option id", function()
            expect(label_for("allow_boar_ambush").key)
                .toBe("ui_mcm_soulslike_ambush_allow_boar_ambush")
        end)

        -- A tooltip is looked up at "<label key>_desc" and is optional, so it
        -- must not be reported as an orphan when its owner exists.
        it("treats a _desc as belonging to its option", function()
            local used = labels.used_keys(tree)
            expect(used["ui_mcm_soulslike_items_allow_weapon_loss_desc"]).toBe(true)
        end)

        it("counts a rendering-only node as having no label", function()
            for _, label in ipairs(labels.labels(tree)) do
                expect(label.type).never.toBe("line")
            end
        end)
    end)
end)

return true
