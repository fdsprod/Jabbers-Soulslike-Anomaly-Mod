-- Structural walk of on_mcm_load's option tree (soulslike_mcm.script:8-937).
--
-- The tree is a 930-line nested literal that MCM reads at runtime. A malformed
-- node -- a track with no `def`, a group missing `gr`, a typo'd id -- breaks
-- the settings page in-game with no compile-time signal at all, and the getters
-- silently fall back to their defaults so the mod keeps "working" while nothing
-- the player configures takes effect.
--
-- The highest-value check here is the last one: every option's "<group>/<id>"
-- path is cross-referenced against the paths the getters actually read. That
-- catches an orphaned option or a mistyped path, which is the failure mode a
-- literal this size grows over time.

local H = require("harness.init")

local MOD_SCRIPTS = { "soulslike_classes", "soulslike", "soulslike_mcm" }

-- Nodes that render something rather than storing a value. They take no `val`
-- and never appear in a storage path.
local PRESENTATION = {
    slide = true, desc = true, line = true, image = true, title = true,
}

-- MCM's `val` is a REQUIRED type code for the stored value, not a display
-- hint: 0 = string, 1 = boolean, 2 = float. A mismatch does not fail loudly --
-- the option reads and writes through the wrong type, so a track declared
-- val = 1 silently stores a boolean and the slider never persists.
local VAL_STRING, VAL_BOOL, VAL_FLOAT = 0, 1, 2

local REQUIRED_VAL = {
    check    = VAL_BOOL,
    track    = VAL_FLOAT,
    key_bind = VAL_FLOAT,
}

local tree

local function boot()
    H.boot{ load = MOD_SCRIPTS }
    H.fakes.set_random_min()
    tree = soulslike_mcm.on_mcm_load()
end

--- Every group directly under the root.
local function groups()
    return tree.gr or {}
end

--- A node is a group if it carries its own `gr` list.
local function is_group(node)
    return type(node.gr) == "table"
end

--- Walk the whole tree, yielding { path, node, group } for every leaf option.
--- Recursive because MCM allows groups to nest arbitrarily deep and the storage
--- path traces every ancestor id -- a flat walk would mis-key anything nested.
local function options()
    local out = {}

    local function walk(node, prefix, group)
        for _, child in ipairs(node.gr or {}) do
            if is_group(child) then
                walk(child, prefix .. "/" .. tostring(child.id), child)
            else
                out[#out + 1] = {
                    node = child,
                    group = group,
                    path = prefix .. "/" .. tostring(child.id),
                }
            end
        end
    end

    -- The root id is the storage prefix the getters strip, so paths here start
    -- below it: "character/rank_loss_percent", matching get_config's key.
    for _, group in ipairs(groups()) do
        walk(group, tostring(group.id), group)
    end

    return out
end

--- "<group>/<id>" for every value-carrying option in the tree.
local function option_paths()
    local out = {}
    for _, entry in ipairs(options()) do
        if not PRESENTATION[entry.node.type] then
            out[entry.path] = entry.node.type
        end
    end
    return out
end

--- The keys the getters actually read, discovered by driving each getter with
--- a recording ui_mcm rather than by restating them here -- a hand-written list
--- would drift from the module it is meant to check.
local function getter_paths()
    local seen = {}
    local real_get = _G.ui_mcm.get
    _G.ui_mcm.get = function(path)
        seen[path:gsub("^soulslike/", "")] = true
        return real_get(path)
    end

    -- Debug getters short-circuit on is_debug_enabled, so their inner
    -- get_config never runs unless debug is on.
    H.fakes.set_mcm("debug/is_enabled", true)

    for name, fn in pairs(soulslike_mcm) do
        if type(fn) == "function" and name ~= "on_mcm_load" then
            pcall(fn, "ignore_bolt")
        end
    end

    _G.ui_mcm.get = real_get
    return seen
end

describe("soulslike_mcm.on_mcm_load()", function()

    beforeEach(boot)

    describe("the root", function()
        it("is identified as soulslike", function()
            expect(tree.id).toBe("soulslike")
        end)

        it("carries groups", function()
            expect(#groups()).toBeGreaterThan(0)
        end)
    end)

    describe("every group", function()
        it("has an id", function()
            local bad = {}
            for i, group in ipairs(groups()) do
                if type(group.id) ~= "string" or group.id == "" then
                    bad[#bad + 1] = i
                end
            end
            expect(bad).toEqual({})
        end)

        it("has a display text", function()
            local bad = {}
            for _, group in ipairs(groups()) do
                if type(group.text) ~= "string" then bad[#bad + 1] = group.id end
            end
            expect(bad).toEqual({})
        end)

        it("has its own option list", function()
            local bad = {}
            for _, group in ipairs(groups()) do
                if type(group.gr) ~= "table" then bad[#bad + 1] = group.id end
            end
            expect(bad).toEqual({})
        end)

        it("has a unique id", function()
            local seen, dupes = {}, {}
            for _, group in ipairs(groups()) do
                if seen[group.id] then dupes[#dupes + 1] = group.id end
                seen[group.id] = true
            end
            expect(dupes).toEqual({})
        end)
    end)

    describe("every option", function()
        it("has an id", function()
            local bad = {}
            for _, entry in ipairs(options()) do
                if type(entry.node.id) ~= "string" or entry.node.id == "" then
                    bad[#bad + 1] = entry.group.id
                end
            end
            expect(bad).toEqual({})
        end)

        it("has a type", function()
            local bad = {}
            for _, entry in ipairs(options()) do
                if type(entry.node.type) ~= "string" then
                    bad[#bad + 1] = entry.path
                end
            end
            expect(bad).toEqual({})
        end)

        -- `val` is the stored-value type code and it is required on every
        -- interactive option. Without it the read/write path has no type to
        -- work through and the setting does not persist.
        it("declares a val type code", function()
            local bad = {}
            for _, entry in ipairs(options()) do
                if not PRESENTATION[entry.node.type]
                   and type(entry.node.val) ~= "number" then
                    bad[#bad + 1] = entry.path
                end
            end
            expect(bad).toEqual({})
        end)

        -- FIXES: D13. The free-text ignore list declared val = '' -- reading
        -- `val` as an initial value rather than a type code. Not a recognised
        -- code, so the box could not round-trip through axr_options.ltx and
        -- get_ignored_other() always saw its '' default: whatever the player
        -- typed there protected nothing.
        it("declares a val the framework recognises", function()
            local bad = {}
            for _, entry in ipairs(options()) do
                local val = entry.node.val
                if not PRESENTATION[entry.node.type]
                   and val ~= VAL_STRING and val ~= VAL_BOOL and val ~= VAL_FLOAT then
                    bad[#bad + 1] = entry.path .. " (val " .. tostring(val) .. ")"
                end
            end
            expect(bad).toEqual({})
        end)

        -- The high-value one. A mismatch is silent: a track with val = 1
        -- stores a boolean, so the slider reads back as true/false and the
        -- configured number never reaches the getter.
        it("declares a val matching its type", function()
            local bad = {}
            for _, entry in ipairs(options()) do
                local want = REQUIRED_VAL[entry.node.type]
                if want and entry.node.val ~= want then
                    bad[#bad + 1] = string.format("%s (%s wants val %d, got %s)",
                        entry.path, entry.node.type, want, tostring(entry.node.val))
                end
            end
            expect(bad).toEqual({})
        end)

        it("declares a default, since none of them use cmd", function()
            local bad = {}
            for _, entry in ipairs(options()) do
                if not PRESENTATION[entry.node.type]
                   and entry.node.def == nil and entry.node.cmd == nil then
                    bad[#bad + 1] = entry.path
                end
            end
            expect(bad).toEqual({})
        end)

        it("uses only types this tree is built from", function()
            local KNOWN = {
                check = true, track = true, input = true,
                slide = true, desc = true,
            }
            local unexpected = {}
            for _, entry in ipairs(options()) do
                if not KNOWN[entry.node.type] then
                    unexpected[#unexpected + 1] = entry.path ..
                        " (" .. tostring(entry.node.type) .. ")"
                end
            end
            -- Not a prohibition on new types -- a new one just needs its own
            -- required-field assertions adding below before it lands.
            expect(unexpected).toEqual({})
        end)

        -- Paths are the storage keys, so a collision means two controls writing
        -- over each other in axr_options.ltx.
        it("has a unique storage path", function()
            local seen, dupes = {}, {}
            for _, entry in ipairs(options()) do
                if seen[entry.path] then dupes[#dupes + 1] = entry.path end
                seen[entry.path] = true
            end
            expect(dupes).toEqual({})
        end)
    end)

    describe("every slide and image option", function()
        it("declares the texture to link", function()
            local bad = {}
            for _, entry in ipairs(options()) do
                local t = entry.node.type
                if (t == "slide" or t == "image") and type(entry.node.link) ~= "string" then
                    bad[#bad + 1] = entry.path
                end
            end
            expect(bad).toEqual({})
        end)
    end)

    describe("every desc and title option", function()
        it("declares the string id to display", function()
            local bad = {}
            for _, entry in ipairs(options()) do
                local t = entry.node.type
                if (t == "desc" or t == "title") and type(entry.node.text) ~= "string" then
                    bad[#bad + 1] = entry.path
                end
            end
            expect(bad).toEqual({})
        end)
    end)

    describe("every track option", function()
        local function tracks()
            local out = {}
            for _, entry in ipairs(options()) do
                if entry.node.type == "track" then
                    out[#out + 1] = { path = entry.path, node = entry.node }
                end
            end
            return out
        end

        it("declares min, max, step and def", function()
            local bad = {}
            for _, t in ipairs(tracks()) do
                for _, key in ipairs{ "min", "max", "step", "def" } do
                    if type(t.node[key]) ~= "number" then
                        bad[#bad + 1] = t.path .. "." .. key
                    end
                end
            end
            expect(bad).toEqual({})
        end)

        -- A default outside its own slider cannot be restored by "reset to
        -- default", and the slider snaps somewhere else the moment it is moved.
        it("keeps its default inside its range", function()
            local bad = {}
            for _, t in ipairs(tracks()) do
                local n = t.node
                if n.def < n.min or n.def > n.max then
                    bad[#bad + 1] = string.format("%s (def %s not in [%s, %s])",
                        t.path, tostring(n.def), tostring(n.min), tostring(n.max))
                end
            end
            expect(bad).toEqual({})
        end)

        it("declares a range with room in it", function()
            local bad = {}
            for _, t in ipairs(tracks()) do
                if t.node.min >= t.node.max then bad[#bad + 1] = t.path end
            end
            expect(bad).toEqual({})
        end)

        it("declares a positive step", function()
            local bad = {}
            for _, t in ipairs(tracks()) do
                if t.node.step <= 0 then bad[#bad + 1] = t.path end
            end
            expect(bad).toEqual({})
        end)
    end)

    describe("every check option", function()
        it("declares a boolean default", function()
            local bad = {}
            for _, entry in ipairs(options()) do
                if entry.node.type == "check" and type(entry.node.def) ~= "boolean" then
                    bad[#bad + 1] = entry.path
                end
            end
            expect(bad).toEqual({})
        end)
    end)

    describe("every list and radio option", function()
        -- radio_h and radio_v are the framework's names; a bare "radio" would
        -- never render.
        it("declares its content", function()
            local bad = {}
            for _, entry in ipairs(options()) do
                local t = entry.node.type
                if (t == "list" or t == "radio_h" or t == "radio_v")
                   and type(entry.node.content) ~= "table" then
                    bad[#bad + 1] = entry.path
                end
            end
            expect(bad).toEqual({})
        end)

        it("does not use the non-existent bare 'radio' type", function()
            local bad = {}
            for _, entry in ipairs(options()) do
                if entry.node.type == "radio" then bad[#bad + 1] = entry.path end
            end
            expect(bad).toEqual({})
        end)
    end)

    describe("the tree against the getters", function()
        -- The cross-check. An option present in the tree but read by nobody is
        -- a control that does nothing; a key read by a getter but absent from
        -- the tree is a setting the player cannot reach.

        -- DEAD CODE. Two getters read keys that the tree does not declare, so
        -- neither can ever be anything but its default. Both belong to the
        -- disabled scenario cluster and are listed rather than ignored, so
        -- re-enabling that cluster surfaces them as part of the work.
        --
        --   debug/debug_hidden_stashes
        --     Tree entry commented out at soulslike_mcm.script:872. Its only
        --     consumer is RFDetectorSoulslikeScenarioLogic
        --     :ApplyTransferItemsPostConditions (soulslike_scenarios.script
        --     :1473), and that scenario is unreachable through create_new --
        --     its weight and debug flag both hard-return zero/false.
        --
        --   scenarios/nearby_dead_stalker_scenario_weight
        --     Getter defined at soulslike_mcm.script:973 and called by nothing
        --     at all: a scenario that was never built.
        local KNOWN_UNREACHABLE = {
            ["debug/debug_hidden_stashes"] = true,
            ["scenarios/nearby_dead_stalker_scenario_weight"] = true,
        }

        it("declares an option for every key the getters read", function()
            local declared = option_paths()
            local missing = {}

            for path in pairs(getter_paths()) do
                -- The free-text ignore list and the per-item ignore toggles are
                -- built dynamically from the item table, not declared inline.
                local is_ignored_entry = path:match("^ignored_items/")
                if not declared[path] and not is_ignored_entry
                   and not KNOWN_UNREACHABLE[path] then
                    missing[#missing + 1] = path
                end
            end

            table.sort(missing)
            expect(missing).toEqual({})
        end)

        it("keeps the known-unreachable options unreachable", function()
            -- If one of these gains a tree entry, it is no longer an exception
            -- and should come off the list above.
            local declared = option_paths()
            local now_reachable = {}
            for path in pairs(KNOWN_UNREACHABLE) do
                if declared[path] then now_reachable[#now_reachable + 1] = path end
            end
            expect(now_reachable).toEqual({})
        end)

        it("reads every option it declares", function()
            local read = getter_paths()
            local orphans = {}

            for path in pairs(option_paths()) do
                if not read[path] and not path:match("^ignored_items/") then
                    orphans[#orphans + 1] = path
                end
            end

            table.sort(orphans)
            expect(orphans).toEqual({})
        end)
    end)

    describe("re-entrancy", function()
        -- MCM calls this again whenever the settings page is reopened.
        it("returns an equivalent tree on a second call", function()
            local first = soulslike_mcm.on_mcm_load()
            local second = soulslike_mcm.on_mcm_load()
            expect(#second.gr).toBe(#first.gr)
        end)

        it("does not accumulate groups", function()
            local before = #tree.gr
            soulslike_mcm.on_mcm_load()
            expect(#soulslike_mcm.on_mcm_load().gr).toBe(before)
        end)
    end)
end)

return true
