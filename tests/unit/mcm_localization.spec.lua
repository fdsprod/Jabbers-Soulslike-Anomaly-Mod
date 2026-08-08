-- MCM labels against the localisation tables, in both directions.
--
-- MCM resolves an option's on-screen label like this (ui_mcm.script):
--
--   explicit:  node.text
--   derived:   "ui_mcm_" .. <full path with "/" replaced by "_">
--
-- so a node declared as
--
--   { id = "allow_weapon_loss", type = "check", val = 1, def = true }
--
-- inside group `items` under root `soulslike` needs the string id
-- `ui_mcm_soulslike_items_allow_weapon_loss`. Nothing checks that at load time:
-- game.translate_string returns the raw id on a miss, so a broken entry shows
-- up in the menu as `ui_mcm_soulslike_items_allow_weapon_loss` and nowhere
-- else. Renaming an option id silently breaks its label.
--
-- MCM also looks up an optional tooltip at "<label key>_desc". Absent is fine
-- -- it just means no tooltip -- so those are only checked in the orphan
-- direction, where a stray `_desc` means the option it described is gone.
--
-- BASELINE, not a wishlist. The tables below record what is broken TODAY so
-- the suite stays green and a NEW break fails immediately. Shrinking a baseline
-- table is the fix; growing one should be a deliberate decision.

local H = require("harness.init")

local MOD_SCRIPTS = { "soulslike_classes", "soulslike", "soulslike_mcm" }

local ROOT = "soulslike"

-- Nodes that render rather than store. They still carry a label, so they are
-- checked the same way; only `line` has nothing to show.
local NO_LABEL = { line = true, image = true }

local eng, rus, tree

local function boot()
    H.boot{ load = MOD_SCRIPTS }
    H.fakes.set_random_min()
    tree = soulslike_mcm.on_mcm_load()
    eng = H.loader.load_string_table("eng")
    rus = H.loader.load_string_table("rus")
end

--- Every labelled node, with the string id MCM will actually look up.
--- { path, key, explicit, group, id }
local function labels()
    local out = {}

    local function walk(node, prefix)
        for _, child in ipairs(node.gr or {}) do
            local path = prefix .. "/" .. tostring(child.id)
            if type(child.gr) == "table" then
                walk(child, path)
            elseif not NO_LABEL[child.type] then
                out[#out + 1] = {
                    path     = path,
                    key      = child.text or ("ui_mcm_" .. path:gsub("/", "_")),
                    explicit = child.text ~= nil,
                    group    = prefix:match("([^/]+)$"),
                    id       = child.id,
                    type     = child.type,
                }
            end
        end
    end

    walk(tree, ROOT)
    return out
end

--- A `text` that is not a string id at all, but a literal English sentence.
--- It renders, because translate_string passes unknown input through, but it
--- can never be localised.
local function is_literal(key)
    return not key:match("^ui_") and not key:match("^st_")
end

local function sorted(set)
    local out = {}
    for v in pairs(set) do out[#out + 1] = v end
    table.sort(out)
    return out
end

-- ---------------------------------------------------------------- baselines

-- Nodes whose label key is not in the English tables. These render as the raw
-- id in the menu right now.
local MISSING_ENG = {
    ["ui_mcm_soulslike_ignored_items_other"] = true,
    ["ui_mcm_soulslike_debug_debug_squad_spawns"] = true,
    ["ui_mcm_soulslike_debug_debug_remove_default_scenario"] = true,
    ["ui_mcm_soulslike_debug_debug_always_spawn_ambush"] = true,
}

-- Nodes carrying a hardcoded English sentence instead of a string id.
-- Both of these already HAVE translations in the tables
-- (ui_mcm_soulslike_hardcore_lose_all_items_on_death and its _desc), which is
-- why they show up as orphans below -- deleting the literal would wire them up.
local LITERAL_TEXT = {
    ["soulslike/hardcore/lose_all_items_on_death"] = true,
    ["soulslike/hardcore/lose_all_items_on_death_desc"] = true,
}

-- Translations with no node to attach to. Everything here belongs to an option
-- that is commented out in the tree, so the string is dead until that option
-- comes back.
local ORPHAN_ENG = {
    ["ui_mcm_soulslike_debug_debug_hidden_stashes"] = true,
    ["ui_mcm_soulslike_debug_debug_the_hidden_stash_scenario"] = true,
    ["ui_mcm_soulslike_debug_debug_the_rf_scenario"] = true,
    ["ui_mcm_soulslike_scenarios_hidden_stash_scenario_weight"] = true,
    ["ui_mcm_soulslike_scenarios_rf_detector_scenario_weight"] = true,
    ["ui_mcm_soulslike_scenarios_rf_detector_scenario_weight_desc"] = true,
    -- Orphaned only because the node hardcodes the English literal above.
    ["ui_mcm_soulslike_hardcore_lose_all_items_on_death"] = true,
    ["ui_mcm_soulslike_hardcore_lose_all_items_on_death_desc"] = true,
}

-- Labels present in English but not Russian: a Russian player sees the raw id.
local MISSING_RUS = {
    ["ui_mcm_soulslike_ignored_items_device_pda_0"] = true,
    ["ui_mcm_soulslike_ignored_items_device_pda_4"] = true,
    ["ui_mcm_soulslike_ignored_items_device_pda_getac"] = true,
    ["ui_mcm_soulslike_ignored_items_device_pda_kulon"] = true,
    ["ui_mcm_soulslike_ignored_items_device_pda_milspec"] = true,
    ["ui_mcm_soulslike_items_artifact_keep_chance"] = true,
    ["ui_mcm_soulslike_items_headgear_keep_chance"] = true,
    ["ui_mcm_soulslike_items_outfit_keep_chance"] = true,
    ["ui_mcm_soulslike_items_weapon_keep_chance"] = true,
    -- The `desc` nodes carrying these ids as their own explicit text.
    ["ui_mcm_soulslike_ignored_items_other_desc"] = true,
    ["ui_mcm_soulslike_items_artifact_keep_chance_desc"] = true,
    ["ui_mcm_soulslike_items_headgear_keep_chance_desc"] = true,
    ["ui_mcm_soulslike_items_outfit_keep_chance_desc"] = true,
    ["ui_mcm_soulslike_items_weapon_keep_chance_desc"] = true,
}

describe("MCM localisation", function()

    beforeEach(boot)

    describe("the string tables", function()
        it("loads the English table", function()
            expect(eng["ui_mcm_menu_soulslike"]).toBe(true)
        end)

        it("loads the Russian table", function()
            expect(rus["ui_mcm_menu_soulslike"]).toBe(true)
        end)

        -- The root has no `text`, so MCM derives ui_mcm_menu_<root_id> for the
        -- entry in the mod list.
        it("has a name for the mod's own menu entry", function()
            expect(eng["ui_mcm_menu_" .. ROOT]).toBe(true)
        end)

        it("finds every group's label", function()
            local missing = {}
            for _, group in ipairs(tree.gr) do
                local key = group.text or ("ui_mcm_menu_" .. tostring(group.id))
                if not eng[key] then missing[#missing + 1] = group.id .. " -> " .. key end
            end
            expect(missing).toEqual({})
        end)
    end)

    describe("every node's label exists in English", function()
        -- The direction that matters most: this is what a player sees.
        it("has no unlisted missing keys", function()
            local broken = {}
            for _, label in ipairs(labels()) do
                if not is_literal(label.key)
                   and not eng[label.key]
                   and not MISSING_ENG[label.key] then
                    broken[#broken + 1] = label.path .. "  ->  " .. label.key
                end
            end
            table.sort(broken)
            expect(broken).toEqual({})
        end)

        -- Guards the baseline itself. If one of these gains a translation the
        -- entry should come off the list, so the next regression is caught.
        it("keeps the known-missing list accurate", function()
            local now_fixed = {}
            for key in pairs(MISSING_ENG) do
                if eng[key] then now_fixed[#now_fixed + 1] = key end
            end
            table.sort(now_fixed)
            expect(now_fixed).toEqual({})
        end)

        it("keeps the known-missing list reachable", function()
            -- A baseline entry naming a node that no longer exists is stale.
            local live = {}
            for _, label in ipairs(labels()) do live[label.key] = true end

            local stale = {}
            for key in pairs(MISSING_ENG) do
                if not live[key] then stale[#stale + 1] = key end
            end
            table.sort(stale)
            expect(stale).toEqual({})
        end)
    end)

    describe("every node's label is a string id", function()
        -- A literal renders, because translate_string passes unknown input
        -- through unchanged, but it can never be translated.
        it("has no unlisted hardcoded English", function()
            local literals = {}
            for _, label in ipairs(labels()) do
                if label.explicit and is_literal(label.key)
                   and not LITERAL_TEXT[label.path] then
                    literals[#literals + 1] = label.path
                end
            end
            table.sort(literals)
            expect(literals).toEqual({})
        end)

        it("keeps the known-literal list accurate", function()
            local live = {}
            for _, label in ipairs(labels()) do
                if label.explicit and is_literal(label.key) then live[label.path] = true end
            end

            local stale = {}
            for path in pairs(LITERAL_TEXT) do
                if not live[path] then stale[#stale + 1] = path end
            end
            table.sort(stale)
            expect(stale).toEqual({})
        end)
    end)

    describe("every translation has a node", function()
        -- The other direction. An orphan is usually a rename: the option moved
        -- and its old string stayed behind, so the new one shows a raw id
        -- while the old translation sits unused.
        --
        -- `<key>_desc` is MCM's optional tooltip for `<key>`, not a node of its
        -- own, so it counts as used when its owner exists.
        local function used_keys()
            local used = {}
            used["ui_mcm_menu_" .. ROOT] = true
            for _, group in ipairs(tree.gr) do
                used[group.text or ("ui_mcm_menu_" .. tostring(group.id))] = true
            end
            for _, label in ipairs(labels()) do
                used[label.key] = true
                used[label.key .. "_desc"] = true
            end
            return used
        end

        it("has no unlisted orphans", function()
            local used = used_keys()
            local orphans = {}

            for id in pairs(eng) do
                if id:match("^ui_mcm_" .. ROOT .. "_")
                   and not used[id] and not ORPHAN_ENG[id] then
                    orphans[#orphans + 1] = id
                end
            end
            table.sort(orphans)
            expect(orphans).toEqual({})
        end)

        it("keeps the known-orphan list accurate", function()
            local used = used_keys()
            local reattached = {}
            for id in pairs(ORPHAN_ENG) do
                if used[id] then reattached[#reattached + 1] = id end
            end
            table.sort(reattached)
            expect(reattached).toEqual({})
        end)

        it("keeps the known-orphan list present in the tables", function()
            local gone = {}
            for id in pairs(ORPHAN_ENG) do
                if not eng[id] then gone[#gone + 1] = id end
            end
            table.sort(gone)
            expect(gone).toEqual({})
        end)
    end)

    describe("Russian parity", function()
        -- Lower severity than a missing English key -- an English speaker never
        -- sees it -- but a Russian player gets the raw id just the same.
        it("has no unlisted untranslated labels", function()
            local untranslated = {}
            for _, label in ipairs(labels()) do
                if not is_literal(label.key)
                   and eng[label.key] and not rus[label.key]
                   and not MISSING_RUS[label.key] then
                    untranslated[#untranslated + 1] = label.path
                end
            end
            table.sort(untranslated)
            expect(untranslated).toEqual({})
        end)

        it("keeps the known-untranslated list accurate", function()
            local now_translated = {}
            for key in pairs(MISSING_RUS) do
                if rus[key] then now_translated[#now_translated + 1] = key end
            end
            table.sort(now_translated)
            expect(now_translated).toEqual({})
        end)

        it("translates every group heading", function()
            local missing = {}
            for _, group in ipairs(tree.gr) do
                local key = group.text or ("ui_mcm_menu_" .. tostring(group.id))
                if eng[key] and not rus[key] then missing[#missing + 1] = group.id end
            end
            expect(missing).toEqual({})
        end)
    end)

    describe("the derivation rule itself", function()
        -- Pins the concatenation, since every assertion above depends on it.
        it("joins root, group and option with underscores", function()
            local found
            for _, label in ipairs(labels()) do
                if label.id == "allow_weapon_loss" then found = label end
            end
            expect(found).toBeDefined()
            expect(found.key).toBe("ui_mcm_soulslike_items_allow_weapon_loss")
        end)

        it("prefers an explicit text over the derived key", function()
            local found
            for _, label in ipairs(labels()) do
                if label.id == "allow_rank_loss" then found = label end
            end
            expect(found.explicit).toBe(true)
            expect(found.key).toBe("ui_mcm_soulslike_character_allow_rank_loss")
        end)

        -- Renaming an option id moves its label key, which is exactly how these
        -- break in practice.
        it("ties the key to the option id", function()
            local by_key = {}
            for _, label in ipairs(labels()) do by_key[label.key] = label.id end
            expect(by_key["ui_mcm_soulslike_ambush_allow_boar_ambush"]).toBe("allow_boar_ambush")
        end)
    end)
end)

return true
