-- MCM label analysis: which string id each option resolves to, and how that
-- lines up with the shipped localisation tables.
--
-- Shared by unit/mcm_localization.spec.lua (which asserts) and locals.lua
-- (which reports), so the baselines below exist in exactly one place. Two
-- copies of these lists would drift the first time one is updated.
--
-- THE DERIVATION (ui_mcm.script)
--
--   explicit   node.text
--   derived    "ui_mcm_" .. <full path, "/" replaced by "_">
--   tooltip    <label key> .. "_desc"          (optional; absent = no tooltip)
--   root       "ui_mcm_menu_" .. <root id>
--
-- so { id = "allow_weapon_loss" } in group `items` under root `soulslike`
-- needs ui_mcm_soulslike_items_allow_weapon_loss. game.translate_string
-- returns the raw id on a miss, so a broken entry renders as the string id
-- itself and nothing else reports it.

local M = {}

M.ROOT = "soulslike"

-- Renders nothing, so carries no label.
local NO_LABEL = { line = true, image = true }

-- ---------------------------------------------------------------- baselines
--
-- What is broken TODAY. Recorded rather than fixed so the suite stays green and
-- a NEW break fails loudly. Shrinking a table is the fix; growing one should be
-- a deliberate decision.

--- Node exists, English translation does not.
---
--- DELIBERATELY EMPTY, and it should stay that way. This is the one category
--- a player sees directly: the option renders as the literal string id in the
--- settings menu. Baselining these was a mistake -- it made `run.bat` report
--- PASS while the shipped menu showed
--- `ui_mcm_soulslike_debug_debug_squad_spawns` to anyone who opened it, which
--- is exactly the permanently-green-while-broken failure this suite exists to
--- prevent.
---
--- Add the string to gamedata/configs/text/eng instead. It is four lines and
--- carries no risk; there is no case for accepting one of these.
M.MISSING_ENG = {}

--- Node hardcodes an English sentence instead of a string id. It renders,
--- because translate_string passes unknown input through, but can never be
--- localised. Both of these already HAVE translations sitting unused -- which
--- is why they also appear in M.ORPHAN_ENG -- so deleting the literal would
--- wire them up without writing anything new.
M.LITERAL_TEXT = {
    ["soulslike/hardcore/lose_all_items_on_death"] = true,
    ["soulslike/hardcore/lose_all_items_on_death_desc"] = true,
}

--- Translation exists, node does not. Usually a rename that left the old
--- string behind; here, mostly options that are commented out.
M.ORPHAN_ENG = {
    ["ui_mcm_soulslike_debug_debug_hidden_stashes"] = true,
    ["ui_mcm_soulslike_debug_debug_the_hidden_stash_scenario"] = true,
    ["ui_mcm_soulslike_debug_debug_the_rf_scenario"] = true,
    ["ui_mcm_soulslike_scenarios_hidden_stash_scenario_weight"] = true,
    ["ui_mcm_soulslike_scenarios_rf_detector_scenario_weight"] = true,
    ["ui_mcm_soulslike_scenarios_rf_detector_scenario_weight_desc"] = true,
    ["ui_mcm_soulslike_hardcore_lose_all_items_on_death"] = true,
    ["ui_mcm_soulslike_hardcore_lose_all_items_on_death_desc"] = true,
}

--- English present, Russian absent. A Russian player sees the raw id.
---
--- Tracked work rather than a defect, so `locals.bat` reports it without
--- failing (pass --strict to change that). The list is still asserted, so a
--- newly untranslated string forces a decision: translate it, or record it
--- here deliberately.
M.MISSING_RUS = {
    -- Added with the English strings that fixed the raw-id labels. Left
    -- untranslated rather than machine-guessed: a wrong Russian label is worse
    -- than a tracked gap.
    ["ui_mcm_soulslike_debug_debug_squad_spawns"] = true,
    ["ui_mcm_soulslike_debug_debug_squad_spawns_desc"] = true,
    ["ui_mcm_soulslike_debug_debug_always_spawn_ambush"] = true,
    ["ui_mcm_soulslike_debug_debug_always_spawn_ambush_desc"] = true,
    ["ui_mcm_soulslike_debug_debug_remove_default_scenario"] = true,
    ["ui_mcm_soulslike_ignored_items_other"] = true,

    ["ui_mcm_soulslike_ignored_items_device_pda_0"] = true,
    ["ui_mcm_soulslike_ignored_items_device_pda_4"] = true,
    ["ui_mcm_soulslike_ignored_items_device_pda_getac"] = true,
    ["ui_mcm_soulslike_ignored_items_device_pda_kulon"] = true,
    ["ui_mcm_soulslike_ignored_items_device_pda_milspec"] = true,
    ["ui_mcm_soulslike_ignored_items_other_desc"] = true,
    ["ui_mcm_soulslike_items_artifact_keep_chance"] = true,
    ["ui_mcm_soulslike_items_artifact_keep_chance_desc"] = true,
    ["ui_mcm_soulslike_items_headgear_keep_chance"] = true,
    ["ui_mcm_soulslike_items_headgear_keep_chance_desc"] = true,
    ["ui_mcm_soulslike_items_outfit_keep_chance"] = true,
    ["ui_mcm_soulslike_items_outfit_keep_chance_desc"] = true,
    ["ui_mcm_soulslike_items_weapon_keep_chance"] = true,
    ["ui_mcm_soulslike_items_weapon_keep_chance_desc"] = true,
}

-- ----------------------------------------------------------------- analysis

--- A `text` that is not a string id at all, but a literal sentence.
function M.is_literal(key)
    return not key:match("^ui_") and not key:match("^st_")
end

--- Every labelled node in the tree, with the string id MCM will look up.
--- Each entry: { path, key, explicit, group, id, type }
---
--- Recursive: MCM lets groups nest arbitrarily deep and the storage path
--- traces every ancestor id, so a flat walk would mis-key anything nested.
function M.labels(tree)
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

    walk(tree, M.ROOT)
    return out
end

--- Every string id the tree can ask for, tooltips included. A `<key>_desc` is
--- MCM's optional tooltip for `<key>`, not a node of its own, so it counts as
--- used whenever its owner exists.
function M.used_keys(tree)
    local used = { ["ui_mcm_menu_" .. M.ROOT] = true }

    for _, group in ipairs(tree.gr or {}) do
        used[group.text or ("ui_mcm_menu_" .. tostring(group.id))] = true
    end

    for _, label in ipairs(M.labels(tree)) do
        used[label.key] = true
        used[label.key .. "_desc"] = true
    end

    return used
end

local function sorted(t)
    table.sort(t)
    return t
end

--- Full comparison of the tree against the string tables.
---
--- Each result list is split into `new` (not in the baseline -- a regression)
--- and `known` (in the baseline -- already accounted for). Only `new` should
--- ever be non-empty on a clean tree.
function M.analyse(tree, eng, rus)
    local r = {
        missing_eng = { new = {}, known = {} },
        literal     = { new = {}, known = {} },
        orphan      = { new = {}, known = {} },
        missing_rus = { new = {}, known = {} },
        stale       = {},   -- baseline entries that no longer describe reality
        groups      = {},   -- group headings with no translation
    }

    for _, group in ipairs(tree.gr or {}) do
        local key = group.text or ("ui_mcm_menu_" .. tostring(group.id))
        if not eng[key] then
            r.groups[#r.groups + 1] = tostring(group.id) .. "  ->  " .. key
        end
    end

    local live_keys, live_literals = {}, {}

    for _, label in ipairs(M.labels(tree)) do
        local literal = label.explicit and M.is_literal(label.key)

        if literal then
            live_literals[label.path] = true
            local bucket = M.LITERAL_TEXT[label.path] and "known" or "new"
            table.insert(r.literal[bucket], label.path)
        else
            live_keys[label.key] = true

            if not eng[label.key] then
                local bucket = M.MISSING_ENG[label.key] and "known" or "new"
                table.insert(r.missing_eng[bucket], label.path .. "  ->  " .. label.key)
            end

            -- Checked independently of English, not as an elseif: a label
            -- missing from BOTH tables is missing from Russian too, and
            -- chaining these would report only the English gap and quietly
            -- understate the translation debt.
            if not rus[label.key] then
                local bucket = M.MISSING_RUS[label.key] and "known" or "new"
                table.insert(r.missing_rus[bucket], label.path .. "  ->  " .. label.key)
            end
        end
    end

    local used = M.used_keys(tree)
    for id in pairs(eng) do
        if id:match("^ui_mcm_" .. M.ROOT .. "_") and not used[id] then
            local bucket = M.ORPHAN_ENG[id] and "known" or "new"
            table.insert(r.orphan[bucket], id)
        end
    end

    -- A baseline entry that no longer describes reality is worse than useless:
    -- it masks the next regression in that slot.
    for key in pairs(M.MISSING_ENG) do
        if eng[key] then
            table.insert(r.stale, "MISSING_ENG  " .. key .. "  (now translated)")
        elseif not live_keys[key] then
            table.insert(r.stale, "MISSING_ENG  " .. key .. "  (no such node)")
        end
    end
    for path in pairs(M.LITERAL_TEXT) do
        if not live_literals[path] then
            table.insert(r.stale, "LITERAL_TEXT " .. path .. "  (no longer a literal)")
        end
    end
    for id in pairs(M.ORPHAN_ENG) do
        if used[id] then
            table.insert(r.stale, "ORPHAN_ENG   " .. id .. "  (now attached to a node)")
        elseif not eng[id] then
            table.insert(r.stale, "ORPHAN_ENG   " .. id .. "  (no longer in the tables)")
        end
    end
    for key in pairs(M.MISSING_RUS) do
        if rus[key] then
            table.insert(r.stale, "MISSING_RUS  " .. key .. "  (now translated)")
        end
    end

    for _, group in pairs{ r.missing_eng, r.literal, r.orphan, r.missing_rus } do
        sorted(group.new)
        sorted(group.known)
    end
    sorted(r.stale)
    sorted(r.groups)

    return r
end

--- Whole-table parity between two languages, independent of the MCM tree.
---
--- The label scan only sees ids the option tree asks for, which misses every
--- message, item name and menu string. This compares the tables outright, so a
--- translation gap anywhere is visible.
---
--- Returns { only_a, only_b }, both sorted.
function M.parity(a, b)
    local only_a, only_b = {}, {}
    for id in pairs(a) do if not b[id] then only_a[#only_a + 1] = id end end
    for id in pairs(b) do if not a[id] then only_b[#only_b + 1] = id end end
    return { only_a = sorted(only_a), only_b = sorted(only_b) }
end

--- Load both string tables and analyse in one call. `tree` defaults to the
--- live on_mcm_load() output.
---
--- NOTE ON ENCODING: the Russian tables ship as windows-1251, not UTF-8
--- (Cyrillic occupies 0xC0-0xFF as single bytes). Everything here compares
--- string *ids*, which are ASCII, so the encoding never matters. Anything that
--- starts reading the <text> bodies has to decode first.
function M.inspect(tree)
    local loader = require("harness.loader")
    tree = tree or _G.soulslike_mcm.on_mcm_load()

    local eng = loader.load_string_table("eng")
    local rus = loader.load_string_table("rus")

    local result = M.analyse(tree, eng, rus)

    local parity = M.parity(eng, rus)
    result.parity = { only_eng = parity.only_a, only_rus = parity.only_b }
    result.counts = { eng = 0, rus = 0 }
    for _ in pairs(eng) do result.counts.eng = result.counts.eng + 1 end
    for _ in pairs(rus) do result.counts.rus = result.counts.rus + 1 end

    return result, tree
end

return M
