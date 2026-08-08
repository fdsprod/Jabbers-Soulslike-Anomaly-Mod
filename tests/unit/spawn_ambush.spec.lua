-- SoulslikeScenarioLogic:SpawnAmbush (soulslike_scenarios.script:667-832)
-- and TrackAmbusher (:652-665).
--
-- Two rolls per invocation: a gate roll deciding whether an ambush happens at
-- all, then a weighted pick over the eligible spawn table. Both had defects.
--
-- The spawn tables are module-scope locals reached as upvalues, which is also
-- how the leak spec checks that SpawnAmbush no longer writes bucket bounds
-- onto them.

local H = require("harness.init")
local B = H.builders

local MOD_SCRIPTS = {
    "soulslike_classes", "soulslike", "soulslike_mcm",
    "soulslike_message_factory", "soulslike_scenarios",
}

local mutant_spawns, stalker_spawns

-- Sections are looked up in system.ltx for their class, which maps to a spawn
-- group; only "Squads" takes the squad path (:781).
local MUTANT_CLASS = "SM_BOARW"      -- -> "NPC (Mutant)", non-squad
local SQUAD_CLASS  = "ON_OFF_S"      -- -> "Squads"

local function boot()
    H.boot{ load = MOD_SCRIPTS }

    local fn = _G.SoulslikeScenarioLogic.SpawnAmbush
    mutant_spawns  = H.loader.upvalue(fn, "mutant_spawns")
    stalker_spawns = H.loader.upvalue(fn, "stalker_spawns")

    -- Every mutant section resolves to a non-squad mutant class by default.
    for _, spawn in ipairs(mutant_spawns) do
        H.fakes.set_ltx(spawn.section, { class = MUTANT_CLASS })
    end
    for _, spawn in ipairs(stalker_spawns) do
        H.fakes.set_ltx(spawn.section, { class = SQUAD_CLASS })
    end
end

local DEATH_LOCATION = {
    position = { x = 10, y = 0, z = 20 },
    level_vertex_id = 55,
    game_vertex_id = 66,
}

-- `false` means "no location recorded" and must survive into make_scenario as
-- false; `or` would quietly restore the default.
local function with_death_location(state)
    if state.death_location == nil then
        state.death_location = DEATH_LOCATION
    end
    return state
end

--- A scenario primed for a mutant ambush: monster killer, bait carried, and a
--- recorded death location so the spawn is not skipped by the position guard.
local function mutant_scenario(state)
    state = with_death_location(state or {})
    state.killer_type = soulslike.entity_type.Monster
    if state.has_mutant_bait == nil then state.has_mutant_bait = true end
    return B.make_scenario{ state = state }
end

local function stalker_scenario(state)
    state = with_death_location(state or {})
    state.killer_type = soulslike.entity_type.Stalker
    return B.make_scenario{ state = state }
end

-- The bucket roll is `math.random() * weight_sum`, so specs drive it with a
-- fraction of the total weight rather than a slot out of 100.
local ROLL_STEPS = 100

--- Section spawned for a bucket roll at `fraction` of the total weight, or nil
--- if nothing was selected. The gate roll is pinned to 0 so only the bucket
--- roll varies.
local function section_for_roll(scenario_fn, fraction, state)
    boot()
    local s = scenario_fn(state)
    H.fakes.set_random_sequence{ 0, fraction }
    s:SpawnAmbush()
    return H.world.created[1] and H.world.created[1].section
end

describe("SoulslikeScenarioLogic:SpawnAmbush()", function()

    beforeEach(boot)

    describe("the gate roll", function()

        describe("given a monster killer carrying bait and a passing roll", function()
            it("spawns something", function()
                local s = mutant_scenario()
                H.fakes.set_random_sequence{ 0.1, 0.5 }
                s:SpawnAmbush()
                expect(H.world.created).toHaveLength(1)
            end)
        end)

        describe("given the roll fails", function()
            it("spawns nothing", function()
                local s = mutant_scenario()
                H.fakes.set_random_sequence{ 0.99 }
                s:SpawnAmbush()
                expect(H.world.created).toHaveLength(0)
            end)

            it("spends only the gate roll", function()
                local s = mutant_scenario()
                H.fakes.set_random_sequence{ 0.99 }
                local before = H.fakes.random_count()
                s:SpawnAmbush()
                expect(H.fakes.random_count() - before).toBe(1)
            end)
        end)

        -- FIXES: D4. The gate used math.random(0, 100) -- 101 discrete outcomes
        -- -- compared against chance*100, so the configured 0.25 actually meant
        -- 25/101. Every other chance roll in the file is a float compared
        -- directly against the chance, and this now matches.
        describe("given the roll lands exactly on the configured chance", function()
            it("does not ambush, because the comparison is `<`", function()
                local s = mutant_scenario{ mutant_ambush_chance = 0.25 }
                H.fakes.set_random_sequence{ 0.25 }
                s:SpawnAmbush()
                expect(H.world.created).toHaveLength(0)
            end)

            it("ambushes just below the chance", function()
                local s = mutant_scenario{ mutant_ambush_chance = 0.25 }
                H.fakes.set_random_sequence{ 0.2499, 0.5 }
                s:SpawnAmbush()
                expect(H.world.created).toHaveLength(1)
            end)
        end)

        describe("given a chance of zero", function()
            it("never ambushes, even on the lowest roll", function()
                local s = mutant_scenario{ mutant_ambush_chance = 0 }
                H.fakes.set_random_sequence{ 0 }
                s:SpawnAmbush()
                expect(H.world.created).toHaveLength(0)
            end)
        end)

        describe("given a chance of one", function()
            it("always ambushes, even on the highest roll", function()
                local s = mutant_scenario{ mutant_ambush_chance = 1.0 }
                H.fakes.set_random_sequence{ 0.9999, 0.5 }
                s:SpawnAmbush()
                expect(H.world.created).toHaveLength(1)
            end)
        end)

        describe("given a monster killer but no bait", function()
            it("spawns nothing", function()
                local s = mutant_scenario{ has_mutant_bait = false }
                H.fakes.set_random_sequence{ 0 }
                s:SpawnAmbush()
                expect(H.world.created).toHaveLength(0)
            end)
        end)

        describe("given debug_always_spawn_ambush", function()
            it("forces the ambush regardless of the roll", function()
                H.fakes.set_mcm("debug/is_enabled", true)
                H.fakes.set_mcm("debug/debug_always_spawn_ambush", true)
                local s = mutant_scenario()
                H.fakes.set_random_sequence{ 0.99, 0.5 }
                s:SpawnAmbush()
                expect(H.world.created).toHaveLength(1)
            end)
        end)

        describe("given a stalker killer that cannot be resolved", function()
            it("spawns nothing", function()
                local s = stalker_scenario{ killer_id = 4242 }
                H.fakes.set_random_sequence{ 0 }
                s:SpawnAmbush()
                expect(H.world.created).toHaveLength(0)
            end)
        end)

        describe("given no killer type at all", function()
            it("spawns nothing", function()
                local s = B.make_scenario{}
                H.fakes.set_random_sequence{ 0 }
                s:SpawnAmbush()
                expect(H.world.created).toHaveLength(0)
            end)
        end)
    end)

    describe("bucket selection", function()

        -- FIXES: D1. The buckets were built by accumulating a FLOORED running
        -- max, so truncation compounded and the last bucket ended below 100 --
        -- at the defaults it ended at 96, leaving rolls 97-100 matching nothing
        -- and SpawnAmbush returning silently with no ambush and no debug tip.
        describe("given the full default mutant table", function()
            it("selects a section across the whole roll range", function()
                local missed = {}
                for i = 0, ROLL_STEPS - 1 do
                    local fraction = i / ROLL_STEPS
                    if not section_for_roll(mutant_scenario, fraction) then
                        missed[#missed + 1] = fraction
                    end
                end
                expect(missed).toEqual({})
            end)

            -- math.random() is [0,1), so the highest reachable roll sits just
            -- below the total weight. That is exactly where the old floored
            -- buckets left a dead zone.
            it("selects a section just below the top of the range", function()
                expect(section_for_roll(mutant_scenario, 0.99999)).toBeDefined()
            end)

            it("selects a section on a roll of zero", function()
                expect(section_for_roll(mutant_scenario, 0)).toBeDefined()
            end)
        end)

        -- FIXES: D2. Once a bucket's share fell below 1 after flooring, its min
        -- exceeded its max and it became permanently unreachable. At the
        -- defaults that was every rare mutant -- bloodsucker, burer, chimera,
        -- controller and the two weak variants all had min=97 > max=96, so
        -- their configured weights were decorative.
        describe("given the rare mutants are enabled", function()
            -- Probing each entry at the midpoint of its OWN bucket rather than
            -- sampling a fixed grid: the rarest entry is 0.01 of a 4.98 total,
            -- roughly 0.2% of the range, which a 1/100 grid steps straight over.
            -- Every entry must be selectable at the middle of its own share.
            local function bucket_midpoints()
                local total = 0
                for _, spawn in ipairs(mutant_spawns) do
                    total = total + spawn.weight
                end

                local out, lower = {}, 0
                for _, spawn in ipairs(mutant_spawns) do
                    out[#out + 1] = {
                        section  = spawn.section,
                        fraction = (lower + spawn.weight / 2) / total,
                    }
                    lower = lower + spawn.weight
                end
                return out
            end

            it("can select each rare mutant", function()
                local rare = {
                    simulation_bloodsucker = true, simulation_burer1 = true,
                    simulation_chimera = true, simulation_bloodsucker_2weak = true,
                    simulation_chimera_2weak = true, simulation_controller = true,
                }

                local unreachable = {}
                for _, probe in ipairs(bucket_midpoints()) do
                    if rare[probe.section] then
                        if section_for_roll(mutant_scenario, probe.fraction)
                           ~= probe.section then
                            unreachable[#unreachable + 1] = probe.section
                        end
                    end
                end
                expect(unreachable).toEqual({})
            end)

            it("can select every entry in the table", function()
                local unreachable = {}
                for _, probe in ipairs(bucket_midpoints()) do
                    if section_for_roll(mutant_scenario, probe.fraction)
                       ~= probe.section then
                        unreachable[#unreachable + 1] = probe.section
                    end
                end
                expect(unreachable).toEqual({})
            end)

            -- Weights should now be proportional rather than decorative: a
            -- bucket's width must track its declared weight.
            it("gives each entry a share proportional to its weight", function()
                local probes = bucket_midpoints()
                local boar = probes[1]          -- weight 1.00
                local controller = probes[#probes]

                expect(section_for_roll(mutant_scenario, boar.fraction))
                    .toBe(boar.section)
                expect(section_for_roll(mutant_scenario, controller.fraction))
                    .toBe(controller.section)
            end)
        end)

        describe("given only one mutant type is enabled", function()
            local ONLY_SNORK = {
                allow_boar_ambush = false, allow_flesh_ambush = false,
                allow_dogs_ambush = false, allow_cats_ambush = false,
                allow_bloodsucker_ambush = false, allow_burer_ambush = false,
                allow_chimera_ambush = false, allow_controller_ambush = false,
            }

            it("selects it on the lowest roll", function()
                expect(section_for_roll(mutant_scenario, 0, ONLY_SNORK))
                    .toBe("simulation_snork")
            end)

            it("selects it just below the top of the range", function()
                expect(section_for_roll(mutant_scenario, 0.99999, ONLY_SNORK))
                    .toBe("simulation_snork")
            end)
        end)

        describe("given a disabled mutant type", function()
            it("is never selected at any roll", function()
                local seen = {}
                for i = 0, ROLL_STEPS - 1 do
                    local sec = section_for_roll(mutant_scenario, i / ROLL_STEPS,
                                                 { allow_snorks_ambush = false })
                    if sec then seen[sec] = true end
                end
                expect(seen["simulation_snork"]).toBeNil()
            end)
        end)

        describe("given every mutant type is disabled", function()
            it("spawns nothing", function()
                local s = mutant_scenario{
                    allow_boar_ambush = false, allow_flesh_ambush = false,
                    allow_dogs_ambush = false, allow_cats_ambush = false,
                    allow_snorks_ambush = false, allow_bloodsucker_ambush = false,
                    allow_burer_ambush = false, allow_chimera_ambush = false,
                    allow_controller_ambush = false,
                }
                H.fakes.set_random_sequence{ 0 }
                s:SpawnAmbush()
                expect(H.world.created).toHaveLength(0)
            end)

            it("does not spend the bucket roll", function()
                local s = mutant_scenario{
                    allow_boar_ambush = false, allow_flesh_ambush = false,
                    allow_dogs_ambush = false, allow_cats_ambush = false,
                    allow_snorks_ambush = false, allow_bloodsucker_ambush = false,
                    allow_burer_ambush = false, allow_chimera_ambush = false,
                    allow_controller_ambush = false,
                }
                H.fakes.set_random_sequence{ 0 }
                local before = H.fakes.random_count()
                s:SpawnAmbush()
                expect(H.fakes.random_count() - before).toBe(1)
            end)
        end)

        it("spends exactly two rolls on a successful ambush", function()
            local s = mutant_scenario()
            H.fakes.set_random_sequence{ 0, 0.5 }
            local before = H.fakes.random_count()
            s:SpawnAmbush()
            expect(H.fakes.random_count() - before).toBe(2)
        end)

        -- FIXES: D3. table.insert put REFERENCES to the module-scope spawn
        -- descriptors into the working list, so writing value.min/value.max
        -- mutated the shared tables permanently. Harmless only by luck -- the
        -- bounds were always recomputed before use -- but it made a supposedly
        -- constant table carry per-call state.
        describe("the module-scope spawn tables", function()
            it("are not mutated by a spawn", function()
                local s = mutant_scenario()
                H.fakes.set_random_sequence{ 0, 0.5 }
                s:SpawnAmbush()

                local polluted = {}
                for _, spawn in ipairs(mutant_spawns) do
                    if spawn.min ~= nil or spawn.max ~= nil then
                        polluted[#polluted + 1] = spawn.section
                    end
                end
                expect(polluted).toEqual({})
            end)

            it("keep only their declared keys", function()
                local s = mutant_scenario()
                H.fakes.set_random_sequence{ 0, 0.5 }
                s:SpawnAmbush()

                local keys = {}
                for k in pairs(mutant_spawns[1]) do keys[#keys + 1] = k end
                table.sort(keys)
                expect(keys).toEqual({ "section", "type", "weight" })
            end)

            it("give the same selection across repeated calls", function()
                local first = section_for_roll(mutant_scenario, 50)

                boot()
                local s = mutant_scenario{ allow_snorks_ambush = false }
                H.fakes.set_random_sequence{ 0, 0.5 }
                s:SpawnAmbush()

                -- A narrower table on the second call must not leave stale
                -- bounds that change what the first configuration selects.
                expect(section_for_roll(mutant_scenario, 50)).toBe(first)
            end)
        end)
    end)

    describe("stalker ambushes", function()

        local function with_killer(community, state)
            boot()
            local killer = H.world.spawn_se_npc{ kind = "stalker", community = community }
            state = state or {}
            state.killer_id = killer.id
            return stalker_scenario(state), killer
        end

        describe("given a killer of a given community", function()
            it("only selects squads of that community", function()
                local seen = {}
                for i = 0, ROLL_STEPS - 1 do
                    boot()
                    local killer = H.world.spawn_se_npc{ kind = "stalker", community = "bandit" }
                    local s = stalker_scenario{ killer_id = killer.id }
                    H.fakes.set_random_sequence{ 0, i / ROLL_STEPS }
                    s:SpawnAmbush()
                    local made = H.world.created[1]
                    if made then seen[made.section] = true end
                end

                for section in pairs(seen) do
                    expect(section).toContain("bandit")
                end
            end)
        end)

        -- FIXES: D10. Advanced, Veteran and Sniper all had the value 2 in
        -- stalker_spawn_type, and the filter tested `== Advanced` first, so
        -- enabling any one of the three admitted all of them. The veteran and
        -- sniper MCM toggles could never gate anything independently.
        describe("given only the novice toggle is on", function()
            local NOVICE_ONLY = {
                allow_stalker_advanced_ambush = false,
                allow_stalker_veteran_ambush  = false,
                allow_stalker_sniper_ambush   = false,
            }

            it("never selects an advanced squad", function()
                local seen = {}
                for i = 0, ROLL_STEPS - 1 do
                    boot()
                    local killer = H.world.spawn_se_npc{ kind = "stalker", community = "stalker" }
                    local s = stalker_scenario{
                        killer_id = killer.id,
                        allow_stalker_advanced_ambush = false,
                        allow_stalker_veteran_ambush  = false,
                        allow_stalker_sniper_ambush   = false,
                    }
                    H.fakes.set_random_sequence{ 0, i / ROLL_STEPS }
                    s:SpawnAmbush()
                    if H.world.created[1] then seen[H.world.created[1].section] = true end
                end
                expect(seen["stalker_sim_squad_advanced"]).toBeNil()
                expect(seen["stalker_sim_squad_veteran"]).toBeNil()
            end)
        end)

        describe("given only the veteran toggle is on", function()
            it("never selects an advanced squad", function()
                local seen = {}
                for i = 0, ROLL_STEPS - 1 do
                    boot()
                    local killer = H.world.spawn_se_npc{ kind = "stalker", community = "stalker" }
                    local s = stalker_scenario{
                        killer_id = killer.id,
                        allow_stalker_novice_ambush   = false,
                        allow_stalker_advanced_ambush = false,
                        allow_stalker_sniper_ambush   = false,
                    }
                    H.fakes.set_random_sequence{ 0, i / ROLL_STEPS }
                    s:SpawnAmbush()
                    if H.world.created[1] then seen[H.world.created[1].section] = true end
                end
                expect(seen["stalker_sim_squad_advanced"]).toBeNil()
                expect(seen["stalker_sim_squad_veteran"]).toBe(true)
            end)
        end)

        describe("given only the sniper toggle is on", function()
            it("selects only the sniper squad", function()
                local seen = {}
                for i = 0, ROLL_STEPS - 1 do
                    boot()
                    local killer = H.world.spawn_se_npc{ kind = "stalker", community = "army" }
                    local s = stalker_scenario{
                        killer_id = killer.id,
                        allow_stalker_novice_ambush   = false,
                        allow_stalker_advanced_ambush = false,
                        allow_stalker_veteran_ambush  = false,
                    }
                    H.fakes.set_random_sequence{ 0, i / ROLL_STEPS }
                    s:SpawnAmbush()
                    if H.world.created[1] then seen[H.world.created[1].section] = true end
                end
                expect(seen).toEqual({ army_sim_squad_sniper = true })
            end)
        end)

        describe("given a community with no matching squads", function()
            it("spawns nothing", function()
                local s = with_killer("zombied")
                H.fakes.set_random_sequence{ 0 }
                s:SpawnAmbush()
                expect(H.world.created).toHaveLength(0)
            end)
        end)
    end)

    describe("spawning", function()

        describe("given a non-squad section", function()
            it("creates the object at the death location", function()
                local s = mutant_scenario()
                H.fakes.set_random_sequence{ 0, 0.5 }
                s:SpawnAmbush()
                expect(H.world.created).toHaveLength(1)
            end)

            it("tracks the ambusher with both vertex ids", function()
                local s = mutant_scenario()
                H.fakes.set_random_sequence{ 0, 0.5 }
                s:SpawnAmbush()

                local id = H.world.created[1].id
                local tracked = s.game_state.tracked_ambushers[id]
                expect(tracked.level_vertex_id).toBe(55)
                expect(tracked.game_vertex_id).toBe(66)
            end)

            it("records the stance constants", function()
                local s = mutant_scenario()
                H.fakes.set_random_sequence{ 0, 0.5 }
                s:SpawnAmbush()

                local tracked = s.game_state.tracked_ambushers[H.world.created[1].id]
                expect(tracked.mental_state).toBe(anim.look_around)
                expect(tracked.body_state).toBe(move.standing)
                expect(tracked.movement_type).toBe(move.stand)
                expect(tracked.sight_type).toBe(look.search)
            end)
        end)

        describe("given a squad section", function()
            beforeEach(function()
                H.world.squads["stalker_sim_squad_novice"] = {
                    { kind = "stalker", section = "sim_default_stalker_1" },
                    { kind = "stalker", section = "sim_default_stalker_2" },
                }
            end)

            local function spawn_squad()
                local killer = H.world.spawn_se_npc{ kind = "stalker", community = "stalker" }
                local s = stalker_scenario{
                    killer_id = killer.id,
                    allow_stalker_advanced_ambush = false,
                    allow_stalker_veteran_ambush  = false,
                    allow_stalker_sniper_ambush   = false,
                }
                H.fakes.set_random_sequence{ 0, 0.5 }
                s:SpawnAmbush()
                return s
            end

            it("creates the npcs", function()
                spawn_squad()
                expect(H.fakes.call_count("se.create_npc")).toBe(1)
            end)

            it("sets up each member with the simulation board", function()
                spawn_squad()
                expect(H.fakes.call_count("setup_squad_and_group")).toBe(2)
            end)

            it("announces each member's creation", function()
                spawn_squad()
                expect(H.dispatch.sends_of("squad_on_npc_creation")).toHaveLength(2)
            end)

            it("tracks every member", function()
                local s = spawn_squad()
                local n = 0
                for _ in pairs(s.game_state.tracked_ambushers) do n = n + 1 end
                expect(n).toBe(2)
            end)

            -- CHARACTERIZATION: the squad call passes 6 args where the
            -- non-squad call passes 8 (:796-802 vs :811-819), so squad members
            -- are tracked with nil vertex ids. Left as-is: the consumer places
            -- them by desired_position, which is supplied, and the squad's own
            -- placement comes from the simulation board.
            it("CHARACTERIZATION: leaves member vertex ids nil", function()
                local s = spawn_squad()
                for _, tracked in pairs(s.game_state.tracked_ambushers) do
                    expect(tracked.level_vertex_id).toBeNil()
                    expect(tracked.game_vertex_id).toBeNil()
                end
            end)
        end)

        describe("given no death location was recorded", function()
            -- The position guard at :770 saves this call from building a vector
            -- out of nils, which the engine would hard-crash on.
            it("spawns nothing", function()
                local s = mutant_scenario{ death_location = false }
                H.fakes.set_random_sequence{ 0, 0.5 }
                s:SpawnAmbush()
                expect(H.world.created).toHaveLength(0)
            end)

            it("does not raise", function()
                local s = mutant_scenario{ death_location = false }
                H.fakes.set_random_sequence{ 0, 0.5 }
                expect(function() s:SpawnAmbush() end).never.toThrow()
            end)

            it("still spends both rolls", function()
                local s = mutant_scenario{ death_location = false }
                H.fakes.set_random_sequence{ 0, 0.5 }
                local before = H.fakes.random_count()
                s:SpawnAmbush()
                expect(H.fakes.random_count() - before).toBe(2)
            end)
        end)

        describe("given an unknown spawn class", function()
            it("still spawns, on the non-squad path", function()
                for _, spawn in ipairs(mutant_spawns) do
                    H.fakes.set_ltx(spawn.section, { class = "NOT_A_CLASS" })
                end
                local s = mutant_scenario()
                H.fakes.set_random_sequence{ 0, 0.5 }
                s:SpawnAmbush()
                expect(H.world.created).toHaveLength(1)
            end)
        end)

        describe("given debug_squad_spawns", function()
            it("adds a map spot for the spawn", function()
                H.fakes.set_mcm("debug/is_enabled", true)
                H.fakes.set_mcm("debug/debug_squad_spawns", true)
                local s = mutant_scenario()
                H.fakes.set_random_sequence{ 0, 0.5 }
                s:SpawnAmbush()
                expect(H.fakes.call_count("level.map_add_object_spot_ser")).toBe(1)
            end)
        end)
    end)
end)

describe("SoulslikeScenarioLogic:TrackAmbusher()", function()

    beforeEach(boot)

    it("creates the collection on first use", function()
        local s = B.make_scenario{}
        s.game_state.tracked_ambushers = nil
        s:TrackAmbusher(1, "a", "b", "c", "d", { x = 1, y = 2, z = 3 }, 4, 5)
        expect(s.game_state.tracked_ambushers).toBeDefined()
    end)

    it("records every field", function()
        local s = B.make_scenario{}
        s:TrackAmbusher(7, "mental", "body", "move", "sight", { x = 1, y = 2, z = 3 }, 4, 5)
        expect(s.game_state.tracked_ambushers[7]).toEqual{
            mental_state = "mental", body_state = "body",
            movement_type = "move", sight_type = "sight",
            position = { x = 1, y = 2, z = 3 },
            level_vertex_id = 4, game_vertex_id = 5,
        }
    end)

    it("overwrites an existing entry for the same id", function()
        local s = B.make_scenario{}
        s:TrackAmbusher(7, "first", nil, nil, nil, {}, nil, nil)
        s:TrackAmbusher(7, "second", nil, nil, nil, {}, nil, nil)
        expect(s.game_state.tracked_ambushers[7].mental_state).toBe("second")
    end)

    it("keeps separate entries per id", function()
        local s = B.make_scenario{}
        s:TrackAmbusher(1, "a", nil, nil, nil, {}, nil, nil)
        s:TrackAmbusher(2, "b", nil, nil, nil, {}, nil, nil)
        expect(s.game_state.tracked_ambushers[1].mental_state).toBe("a")
        expect(s.game_state.tracked_ambushers[2].mental_state).toBe("b")
    end)
end)

-- FIXES: D12. npc_on_net_spawn is the only consumer of tracked_ambushers, and
-- its registration was commented out (soulslike.script:964) while nothing else
-- referenced it. So no ambusher ever took its stance, and the table grew in
-- every save forever -- it was not even in the migration schema, so old saves
-- never had it repaired.
describe("ambusher stance handover", function()

    local function boot_with_mode()
        H.boot{ load = MOD_SCRIPTS, soulslike_mode = true }
        H.fakes.set_random_min()
        soulslike.on_game_start()
    end

    beforeEach(boot_with_mode)

    describe("the callback registration", function()
        it("is registered on game start", function()
            expect(H.dispatch.handler_count("npc_on_net_spawn")).toBe(1)
        end)
    end)

    describe("given a tracked stalker net-spawns", function()
        local npc

        beforeEach(function()
            npc = B.make_stalker{ id = 5150 }
            soulslike.get_soulslike_state().tracked_ambushers = {
                [5150] = {
                    mental_state = anim.look_around,
                    body_state = move.standing,
                    movement_type = move.stand,
                    sight_type = look.search,
                    position = { x = 1, y = 2, z = 3 },
                    level_vertex_id = 4,
                    game_vertex_id = 5,
                },
            }
            SendScriptCallback("npc_on_net_spawn", npc, nil)
        end)

        it("applies the recorded stance", function()
            expect(npc.applied.mental_state).toBe(anim.look_around)
            expect(npc.applied.body_state).toBe(move.standing)
            expect(npc.applied.movement_type).toBe(move.stand)
            expect(npc.applied.sight_type).toBe(look.search)
        end)

        it("points it at the recorded position", function()
            -- A vector object, not a plain table: the handler rebuilds one via
            -- vector():set (soulslike.script:927).
            local pos = npc.applied.desired_position
            expect(pos.x).toBe(1)
            expect(pos.y).toBe(2)
            expect(pos.z).toBe(3)
            expect(npc.applied.desired_direction).toBe(true)
        end)

        -- The whole point of consuming the entry: without this the table is
        -- append-only and every death adds to it permanently.
        it("clears the entry", function()
            expect(soulslike.get_soulslike_state().tracked_ambushers[5150]).toBeNil()
        end)
    end)

    describe("given a tracked squad member with no position", function()
        -- Squad members are tracked with only 6 of the 8 fields
        -- (soulslike_scenarios.script:796-802), so position is an empty table
        -- and the vertex ids are nil. Posing them would build a vector out of
        -- nils, which the engine hard-crashes on.
        local npc

        beforeEach(function()
            npc = B.make_stalker{ id = 5151 }
            soulslike.get_soulslike_state().tracked_ambushers = {
                [5151] = {
                    mental_state = anim.look_around,
                    body_state = move.standing,
                    movement_type = move.stand,
                    sight_type = look.search,
                    position = {},
                },
            }
        end)

        it("does not raise", function()
            expect(function()
                SendScriptCallback("npc_on_net_spawn", npc, nil)
            end).never.toThrow()
        end)

        it("still applies the stance", function()
            SendScriptCallback("npc_on_net_spawn", npc, nil)
            expect(npc.applied.mental_state).toBe(anim.look_around)
        end)

        it("does not set a desired position", function()
            SendScriptCallback("npc_on_net_spawn", npc, nil)
            expect(npc.applied.desired_position).toBeNil()
        end)

        it("still clears the entry", function()
            SendScriptCallback("npc_on_net_spawn", npc, nil)
            expect(soulslike.get_soulslike_state().tracked_ambushers[5151]).toBeNil()
        end)
    end)

    describe("given a tracked mutant net-spawns", function()
        -- The stance setters are stalker-only, but SpawnAmbush tracks mutants
        -- too. The entry must still be consumed or mutants leak forever.
        local mutant

        beforeEach(function()
            mutant = B.make_monster{ id = 5152 }
            soulslike.get_soulslike_state().tracked_ambushers = {
                [5152] = { position = { x = 1, y = 2, z = 3 } },
            }
            SendScriptCallback("npc_on_net_spawn", mutant, nil)
        end)

        it("clears the entry", function()
            expect(soulslike.get_soulslike_state().tracked_ambushers[5152]).toBeNil()
        end)

        it("does not apply stalker-only stance setters to it", function()
            expect(mutant.applied.mental_state).toBeNil()
        end)
    end)

    describe("given an untracked npc net-spawns", function()
        it("leaves other entries alone", function()
            soulslike.get_soulslike_state().tracked_ambushers = { [1] = { position = {} } }
            SendScriptCallback("npc_on_net_spawn", B.make_stalker{ id = 999 }, nil)
            expect(soulslike.get_soulslike_state().tracked_ambushers[1]).toBeDefined()
        end)

        it("does not raise", function()
            expect(function()
                SendScriptCallback("npc_on_net_spawn", B.make_stalker{ id = 999 }, nil)
            end).never.toThrow()
        end)
    end)

    describe("given soulslike mode is off", function()
        it("ignores the spawn entirely", function()
            H.boot{ load = MOD_SCRIPTS }
            H.fakes.set_random_min()
            soulslike.on_game_start()

            local npc = B.make_stalker{ id = 5153 }
            soulslike.get_soulslike_state().tracked_ambushers = {
                [5153] = { position = { x = 1, y = 2, z = 3 } },
            }
            SendScriptCallback("npc_on_net_spawn", npc, nil)
            expect(soulslike.get_soulslike_state().tracked_ambushers[5153]).toBeDefined()
        end)
    end)

    describe("the save schema", function()
        -- Added to get_soulslike_state so a save written before the consumer
        -- existed gets the collection repaired on load, rather than the
        -- handler having to nil-guard it forever.
        it("creates tracked_ambushers on a fresh save", function()
            expect(soulslike.get_soulslike_state().tracked_ambushers).toEqual({})
        end)

        it("repairs a save that predates it", function()
            H.boot{
                load = MOD_SCRIPTS,
                soulslike_mode = true,
                state = { created_stashes = {}, hidden_stashes = {} },
            }
            expect(soulslike.get_soulslike_state().tracked_ambushers).toEqual({})
        end)

        it("does not clobber an existing collection", function()
            H.boot{
                load = MOD_SCRIPTS,
                soulslike_mode = true,
                state = { tracked_ambushers = { [7] = { position = {} } } },
            }
            expect(soulslike.get_soulslike_state().tracked_ambushers[7]).toBeDefined()
        end)
    end)

    describe("across repeated ambushes", function()
        it("does not accumulate entries once each is consumed", function()
            local state = soulslike.get_soulslike_state()
            for i = 1, 5 do
                local npc = B.make_stalker{ id = 6000 + i }
                state.tracked_ambushers[6000 + i] = {
                    mental_state = anim.look_around,
                    position = { x = 1, y = 2, z = 3 },
                }
                SendScriptCallback("npc_on_net_spawn", npc, nil)
            end

            local remaining = 0
            for _ in pairs(state.tracked_ambushers) do remaining = remaining + 1 end
            expect(remaining).toBe(0)
        end)
    end)
end)

return true
