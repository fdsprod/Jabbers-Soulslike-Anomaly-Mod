-- soulslike_mcm's getter contract.
--
-- Every one of the 60-odd getters funnels through get_config
-- (soulslike_mcm.script:939):
--
--   local opt = ui_mcm and ui_mcm.get("soulslike/"..key)
--   if opt == nil then opt = default_when_nil end
--
-- Two things follow, and both matter. A key the player has never touched
-- returns the getter's declared default, which is what a fresh install runs on.
-- And the check is `== nil`, not falsiness, so an explicit `false` is honoured
-- rather than being replaced by a `true` default -- which is the entire point,
-- since most of these defaults ARE true.
--
-- Asserted as tables per category rather than one `it` per getter: sixty
-- one-line specs would be noise, and a table diff names the offender anyway.

local H = require("harness.init")

local MOD_SCRIPTS = { "soulslike_classes", "soulslike", "soulslike_mcm" }

local function boot()
    H.boot{ load = MOD_SCRIPTS }
    H.fakes.set_random_min()
end

--- Call each named getter and collect the results.
local function values_of(names)
    local out = {}
    for _, name in ipairs(names) do
        local fn = soulslike_mcm[name]
        assert(type(fn) == "function", "no such getter: " .. name)
        out[name] = fn()
    end
    return out
end

describe("soulslike_mcm defaults", function()

    beforeEach(boot)

    describe("given a fresh install with nothing configured", function()

        it("defaults the hardcore options off", function()
            expect(values_of{
                "is_hardcore_save_enabled",
                "override_campfire_hardcore_saves",
                "lose_all_items_on_death",
            }).toEqual{
                is_hardcore_save_enabled = false,
                override_campfire_hardcore_saves = false,
                lose_all_items_on_death = false,
            }
        end)

        it("defaults the item loss scalars", function()
            expect(values_of{
                "get_item_loss_scalar",
                "get_item_condition_loss_percent",
                "get_keep_equipped_items_on_death",
                "ignore_rank_when_computing_item_loss_chance",
                "ignore_rank_when_computing_item_condition_loss",
            }).toEqual{
                get_item_loss_scalar = 0.2,
                get_item_condition_loss_percent = 0.05,
                get_keep_equipped_items_on_death = false,
                ignore_rank_when_computing_item_loss_chance = false,
                ignore_rank_when_computing_item_condition_loss = false,
            }
        end)

        it("defaults every keep chance to a quarter", function()
            expect(values_of{
                "get_keep_artifact_chance", "get_keep_headgear_chance",
                "get_keep_outfit_chance", "get_keep_weapon_chance",
            }).toEqual{
                get_keep_artifact_chance = 0.25,
                get_keep_headgear_chance = 0.25,
                get_keep_outfit_chance   = 0.25,
                get_keep_weapon_chance   = 0.25,
            }
        end)

        it("permits every category of loss", function()
            expect(values_of{
                "allow_weapon_loss", "allow_artifact_loss", "allow_outfit_loss",
                "allow_headgear_loss", "allow_toolkit_loss",
            }).toEqual{
                allow_weapon_loss   = true,
                allow_artifact_loss = true,
                allow_outfit_loss   = true,
                allow_headgear_loss = true,
                allow_toolkit_loss  = true,
            }
        end)

        it("defaults every per-type loss chance to certain", function()
            expect(values_of{
                "get_outfit_loss_chance", "get_weapon_loss_chance",
                "get_artefact_loss_chance", "get_headgear_loss_chance",
                "get_toolkit_loss_chance", "get_other_loss_chance",
            }).toEqual{
                get_outfit_loss_chance   = 1.0,
                get_weapon_loss_chance   = 1.0,
                get_artefact_loss_chance = 1.0,
                get_headgear_loss_chance = 1.0,
                get_toolkit_loss_chance  = 1.0,
                get_other_loss_chance    = 1.0,
            }
        end)

        it("defaults every per-type condition loss chance to certain", function()
            expect(values_of{
                "get_outfit_condition_loss_chance",
                "get_weapon_condition_loss_chance",
                "get_artefact_condition_loss_chance",
                "get_headgear_condition_loss_chance",
            }).toEqual{
                get_outfit_condition_loss_chance   = 1.0,
                get_weapon_condition_loss_chance   = 1.0,
                get_artefact_condition_loss_chance = 1.0,
                get_headgear_condition_loss_chance = 1.0,
            }
        end)

        it("defaults the character penalties", function()
            expect(values_of{
                "get_health_loss_percent", "rank_loss_percent",
                "rep_loss_percent", "allow_nighttime_respawn",
                "allow_rank_loss", "allow_rep_loss",
            }).toEqual{
                get_health_loss_percent = 0.75,
                rank_loss_percent = 0.02,
                rep_loss_percent = 0.05,
                allow_nighttime_respawn = true,
                allow_rank_loss = true,
                allow_rep_loss = true,
            }
        end)

        it("defaults the money penalties", function()
            expect(values_of{
                "allow_money_loss", "get_money_loss_chance",
                "get_money_loss_max_percent",
            }).toEqual{
                allow_money_loss = true,
                get_money_loss_chance = 0.5,
                get_money_loss_max_percent = 0.10,
            }
        end)

        it("defaults the ambush chances to a quarter", function()
            expect(values_of{
                "mutant_ambush_chance", "stalker_ambush_chance",
            }).toEqual{
                mutant_ambush_chance = 0.25,
                stalker_ambush_chance = 0.25,
            }
        end)

        it("permits every ambush type", function()
            expect(values_of{
                "allow_boar_ambush", "allow_flesh_ambush", "allow_dogs_ambush",
                "allow_cats_ambush", "allow_snorks_ambush",
                "allow_bloodsucker_ambush", "allow_burer_ambush",
                "allow_chimera_ambush", "allow_controller_ambush",
                "allow_stalker_novice_ambush", "allow_stalker_advanced_ambush",
                "allow_stalker_veteran_ambush", "allow_stalker_sniper_ambush",
            }).toEqual{
                allow_boar_ambush = true, allow_flesh_ambush = true,
                allow_dogs_ambush = true, allow_cats_ambush = true,
                allow_snorks_ambush = true, allow_bloodsucker_ambush = true,
                allow_burer_ambush = true, allow_chimera_ambush = true,
                allow_controller_ambush = true,
                allow_stalker_novice_ambush = true,
                allow_stalker_advanced_ambush = true,
                allow_stalker_veteran_ambush = true,
                allow_stalker_sniper_ambush = true,
            }
        end)

        it("defaults the scenario options", function()
            expect(values_of{
                "are_looter_npcs_marked", "nearby_dead_stalker_scenario_weight",
            }).toEqual{
                are_looter_npcs_marked = false,
                nearby_dead_stalker_scenario_weight = 0.10,
            }
        end)

        it("defaults every debug flag off", function()
            expect(values_of{
                "is_debug_enabled", "show_debug_tips", "debug_hidden_stashes",
                "debug_squad_spawns", "debug_item_loss",
                "debug_remove_default_scenario", "debug_the_tarkov_looter",
                "debug_always_spawn_ambush",
            }).toEqual{
                is_debug_enabled = false, show_debug_tips = false,
                debug_hidden_stashes = false, debug_squad_spawns = false,
                debug_item_loss = false, debug_remove_default_scenario = false,
                debug_the_tarkov_looter = false, debug_always_spawn_ambush = false,
            }
        end)

        it("protects every named item by default", function()
            expect(soulslike_mcm.is_ignored("ignore_bolt")).toBe(true)
            expect(soulslike_mcm.is_ignored("ignore_medkit")).toBe(true)
        end)

        it("defaults the free-text ignore list to empty", function()
            expect(soulslike_mcm.get_ignored_other()).toBe("")
        end)
    end)

    describe("given a configured value", function()

        it("returns it instead of the default", function()
            H.fakes.set_mcm("items/item_loss_scalar", 0.9)
            expect(soulslike_mcm.get_item_loss_scalar()).toBeCloseTo(0.9)
        end)

        -- The check is `opt == nil`, not `not opt`. With `not opt`, every one
        -- of the dozen true-by-default toggles would be impossible to turn off:
        -- setting false would fall straight back to the default.
        it("honours an explicit false over a true default", function()
            H.fakes.set_mcm("items/allow_weapon_loss", false)
            expect(soulslike_mcm.allow_weapon_loss()).toBe(false)
        end)

        it("honours an explicit zero over a non-zero default", function()
            H.fakes.set_mcm("ambush/mutant_ambush_chance", 0)
            expect(soulslike_mcm.mutant_ambush_chance()).toBe(0)
        end)

        it("honours an explicit false for every allow_ toggle", function()
            local names = {
                "allow_weapon_loss", "allow_artifact_loss", "allow_outfit_loss",
                "allow_headgear_loss", "allow_nighttime_respawn",
                "allow_rank_loss", "allow_rep_loss", "allow_money_loss",
                "allow_boar_ambush", "allow_flesh_ambush", "allow_dogs_ambush",
                "allow_cats_ambush", "allow_snorks_ambush",
                "allow_bloodsucker_ambush", "allow_burer_ambush",
                "allow_chimera_ambush", "allow_controller_ambush",
                "allow_stalker_novice_ambush", "allow_stalker_advanced_ambush",
                "allow_stalker_veteran_ambush", "allow_stalker_sniper_ambush",
            }
            -- Keys are not derivable from the getter names (allow_toolkit_loss
            -- reads items/allow_tool_loss), so set every plausible path and
            -- assert the effect rather than the wiring.
            for _, group in ipairs{ "items", "character", "ambush" } do
                for _, name in ipairs(names) do
                    H.fakes.set_mcm(group .. "/" .. name, false)
                end
            end

            local still_true = {}
            for _, name in ipairs(names) do
                if soulslike_mcm[name]() ~= false then
                    still_true[#still_true + 1] = name
                end
            end
            expect(still_true).toEqual({})
        end)

        it("lets an item be un-protected", function()
            H.fakes.set_mcm("ignored_items/ignore_bolt", false)
            expect(soulslike_mcm.is_ignored("ignore_bolt")).toBe(false)
        end)
    end)

    describe("the debug gate", function()
        -- Every debug getter is `is_debug_enabled() and get_config(...)`, so
        -- the master switch overrides each sub-flag rather than sitting
        -- alongside it.
        it("keeps sub-flags off while debug is disabled", function()
            H.fakes.set_mcm("debug/debug_squad_spawns", true)
            H.fakes.set_mcm("debug/debug_item_loss", true)
            expect(soulslike_mcm.debug_squad_spawns()).toBe(false)
            expect(soulslike_mcm.debug_item_loss()).toBe(false)
        end)

        it("lets them through once debug is enabled", function()
            H.fakes.set_mcm("debug/is_enabled", true)
            H.fakes.set_mcm("debug/debug_squad_spawns", true)
            expect(soulslike_mcm.debug_squad_spawns()).toBe(true)
        end)
    end)

    describe("DEAD CODE: the scattered stash weight", function()
        -- Hard-returns 0.0 with the real get_config call commented out
        -- (:986-988). Unlike RF Detector/Hidden Stash, this scenario has no
        -- SCENARIOS enum entry and nothing in the factory ever reads it --
        -- out of scope for the RF Detector/Hidden Stash re-enable.
        it("keeps the weight at zero whatever is configured", function()
            H.fakes.set_mcm("scenarios/scattered_stash_scenario_weight", 1.0)
            expect(soulslike_mcm.scattered_stash_scenario_weight()).toBe(0.0)
        end)
    end)

    describe("the RF Detector and Hidden Stash scenario options", function()
        it("weight defaults to 0.10 with its enable flag left at the default", function()
            expect(soulslike_mcm.rf_detector_scenario_weight()).toBeCloseTo(0.10)
            expect(soulslike_mcm.hidden_stash_scenario_weight()).toBeCloseTo(0.10)
        end)

        it("reads the configured weight when enabled", function()
            H.fakes.set_mcm("scenarios/enable_rf_detector_scenario", true)
            H.fakes.set_mcm("scenarios/rf_detector_scenario_weight", 0.5)
            H.fakes.set_mcm("scenarios/enable_hidden_stash_scenario", true)
            H.fakes.set_mcm("scenarios/hidden_stash_scenario_weight", 0.75)

            expect(soulslike_mcm.rf_detector_scenario_weight()).toBeCloseTo(0.5)
            expect(soulslike_mcm.hidden_stash_scenario_weight()).toBeCloseTo(0.75)
        end)

        it("forces the weight to zero when its enable flag is off", function()
            H.fakes.set_mcm("scenarios/enable_rf_detector_scenario", false)
            H.fakes.set_mcm("scenarios/rf_detector_scenario_weight", 0.5)
            H.fakes.set_mcm("scenarios/enable_hidden_stash_scenario", false)
            H.fakes.set_mcm("scenarios/hidden_stash_scenario_weight", 0.75)

            expect(soulslike_mcm.rf_detector_scenario_weight()).toBe(0.0)
            expect(soulslike_mcm.hidden_stash_scenario_weight()).toBe(0.0)
        end)

        it("reads the debug scenario flags when debug is on", function()
            H.fakes.set_mcm("debug/is_enabled", true)
            H.fakes.set_mcm("debug/debug_the_rf_scenario", true)
            H.fakes.set_mcm("debug/debug_the_hidden_stash_scenario", true)

            expect(soulslike_mcm.debug_the_rf_scenario()).toBe(true)
            expect(soulslike_mcm.debug_the_hidden_stash_scenario()).toBe(true)
        end)

        it("ignores the debug scenario flags when debug is off", function()
            H.fakes.set_mcm("debug/is_enabled", false)
            H.fakes.set_mcm("debug/debug_the_rf_scenario", true)
            H.fakes.set_mcm("debug/debug_the_hidden_stash_scenario", true)

            expect(soulslike_mcm.debug_the_rf_scenario()).toBe(false)
            expect(soulslike_mcm.debug_the_hidden_stash_scenario()).toBe(false)
        end)
    end)

    describe("given ui_mcm is not installed at all", function()
        -- get_config guards with `ui_mcm and ...`, so a player without the MCM
        -- framework gets every declared default rather than a nil-index crash.
        beforeEach(function()
            H.boot{ load = MOD_SCRIPTS }
            H.fakes.set_random_min()
            _G.ui_mcm = nil
        end)

        it("still returns the defaults", function()
            expect(soulslike_mcm.get_item_loss_scalar()).toBeCloseTo(0.2)
            expect(soulslike_mcm.allow_weapon_loss()).toBe(true)
        end)

        it("does not raise", function()
            expect(function() soulslike_mcm.is_hardcore_save_enabled() end)
                .never.toThrow()
        end)
    end)
end)

return true
