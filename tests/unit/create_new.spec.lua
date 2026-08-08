-- soulslike_scenario_logic_factory.create_new (:141-403)
--
-- A 14-arm first-match-wins tree that decides which scenario the death runs,
-- how much loot is at stake, and who rescues or loots the player. Each arm is
-- distinguished not only by the scenario it pushes but by WHICH finder it calls
-- for the looter, so the specs assert on stub_finders' call counts as well as
-- on the resulting ids.
--
-- strict_vectors stays on throughout: two arms build a vector from
-- spawn_location, and passing nil coordinates is an access violation in a
-- release build (class_rep.cpp:688 with the NDEBUG guard compiled out), not a
-- catchable error.

local H = require("harness.init")
local B = H.builders

local MOD_SCRIPTS = {
    "soulslike_classes", "soulslike", "soulslike_mcm",
    "soulslike_message_factory", "soulslike_scenarios",
    "soulslike_scenario_logic_factory",
}

local factory = nil
local friendly, enemy, enemy_stalker, enemy_mutant

--- Boot with a recorded spawn at the origin and all four finders stubbed.
--- `distance` places the actor that far from the spawn along z.
local function boot(distance)
    H.boot{ load = MOD_SCRIPTS }
    H.fakes.set_random_min()
    H.set_spawn{ level = "zaton", position = { x = 0, y = 0, z = 0 } }
    H.set_actor{ position = { x = 0, y = 0, z = distance or 300 } }

    friendly      = B.make_stalker{ name = "friendly" }
    enemy         = B.make_stalker{ name = "enemy" }
    enemy_stalker = B.make_stalker{ name = "enemy_stalker" }
    enemy_mutant  = B.make_monster{ name = "enemy_mutant" }

    B.stub_finders{
        friendly_stalker = friendly,
        enemy            = enemy,
        enemy_stalker    = enemy_stalker,
        enemy_mutant     = enemy_mutant,
    }

    factory = _G.soulslike_scenario_logic_factory
    return factory
end

--- One hit whose draftsman resolves to `obj`, flagged fatal.
local function fatal_hit_from(obj)
    if obj then H.fakes.register_object(obj) end
    return { B.make_hit{
        power = 100,
        is_fatal = true,
        time = 1000,
        draftsman_id = obj and obj:id() or nil,
    } }
end

local SCENARIOS

describe("soulslike_scenario_logic_factory.create_new()", function()

    beforeEach(function()
        boot()
        SCENARIOS = _G.soulslike.SCENARIOS
    end)

    describe("given the noloss debug flag", function()
        local function debug_noloss()
            H.fakes.set_mcm("debug/is_enabled", true)
            H.fakes.set_mcm("debug/debug_the_noloss_scenario", true)
            return factory.create_new(fatal_hit_from(enemy_mutant))
        end

        it("forces the NoLoss scenario", function()
            expect(debug_noloss().logic_state.scenario_id).toBe(SCENARIOS.NoLoss)
        end)

        it("puts nothing at stake", function()
            expect(debug_noloss().logic_state.scenario_loot_scalar).toBe(0)
        end)

        it("finds a rescuer", function()
            expect(debug_noloss().logic_state.rescuer_id).toBe(friendly:id())
        end)

        it("assigns no looter", function()
            expect(debug_noloss().logic_state.looter_id).toBeNil()
        end)
    end)

    describe("given the default debug flag", function()
        local function debug_default()
            H.fakes.set_mcm("debug/is_enabled", true)
            H.fakes.set_mcm("debug/debug_the_default_scenario", true)
            return factory.create_new(fatal_hit_from(enemy_mutant))
        end

        it("forces the Default scenario", function()
            expect(debug_default().logic_state.scenario_id).toBe(SCENARIOS.Default)
        end)

        it("puts everything at stake", function()
            expect(debug_default().logic_state.scenario_loot_scalar).toBe(1)
        end)

        it("takes the looter from the generic enemy finder", function()
            debug_default()
            expect(B.finder_count("enemy")).toBe(1)
            expect(B.finder_count("enemy_mutant")).toBe(0)
        end)
    end)

    -- DEAD CODE: debug_the_rf_scenario and debug_the_hidden_stash_scenario
    -- hard-return false (soulslike_mcm.script:1138, :1142) with the real
    -- expression commented out, so these two arms cannot be reached. Those
    -- scenarios are only ever constructed via create_by_id on a save reload.
    describe("DEAD CODE: the rf and hidden-stash debug flags", function()
        it("does not reach the rf arm even with the flag set", function()
            H.fakes.set_mcm("debug/is_enabled", true)
            H.fakes.set_mcm("debug/debug_the_rf_scenario", true)
            local s = factory.create_new(fatal_hit_from(enemy_mutant))
            expect(s.logic_state.scenario_id).never.toBe(SCENARIOS.RFDetectorStash)
        end)

        it("does not reach the hidden-stash arm even with the flag set", function()
            H.fakes.set_mcm("debug/is_enabled", true)
            H.fakes.set_mcm("debug/debug_the_hidden_stash_scenario", true)
            local s = factory.create_new(fatal_hit_from(enemy_mutant))
            expect(s.logic_state.scenario_id).never.toBe(SCENARIOS.HiddenStash)
        end)

        it("keeps the getters hard-returning false", function()
            H.fakes.set_mcm("debug/is_enabled", true)
            H.fakes.set_mcm("debug/debug_the_rf_scenario", true)
            H.fakes.set_mcm("debug/debug_the_hidden_stash_scenario", true)
            expect(soulslike_mcm.debug_the_rf_scenario()).toBe(false)
            expect(soulslike_mcm.debug_the_hidden_stash_scenario()).toBe(false)
        end)
    end)

    describe("given the player died close to their spawn", function()
        it("runs NoLoss at 50 metres", function()
            boot(50)
            local s = factory.create_new(fatal_hit_from(enemy_mutant))
            expect(s.logic_state.scenario_id).toBe(SCENARIOS.NoLoss)
            expect(s.logic_state.scenario_loot_scalar).toBe(0)
        end)

        it("assigns no looter", function()
            boot(50)
            local s = factory.create_new(fatal_hit_from(enemy_mutant))
            expect(s.logic_state.looter_id).toBeNil()
        end)

        it("still finds a rescuer", function()
            boot(50)
            local s = factory.create_new(fatal_hit_from(enemy_mutant))
            expect(s.logic_state.rescuer_id).toBe(friendly:id())
        end)
    end)

    describe("given the player died in the middle band", function()
        it("scales the stake with distance", function()
            boot(125)   -- (125 - 50) / 150 = 0.5
            local s = factory.create_new(fatal_hit_from(enemy_mutant))
            expect(s.logic_state.scenario_loot_scalar).toBeCloseTo(0.5)
        end)

        it("puts nothing at stake just past the close band", function()
            boot(50.001)
            local s = factory.create_new(fatal_hit_from(enemy_mutant))
            expect(s.logic_state.scenario_loot_scalar).toBeCloseTo(0, 0.001)
        end)

        it("puts everything at stake at the far edge", function()
            boot(200)
            local s = factory.create_new(fatal_hit_from(enemy_mutant))
            expect(s.logic_state.scenario_loot_scalar).toBeCloseTo(1)
        end)

        it("falls through past 200 metres", function()
            boot(200.001)
            local s = factory.create_new(fatal_hit_from(enemy_mutant))
            -- The monster arm, not the distance arm.
            expect(B.finder_count("enemy_mutant")).toBe(1)
        end)
    end)

    describe("given the player died indoors", function()
        it("runs NoLoss", function()
            H.fakes.set_level("underground_lab")
            local s = factory.create_new(fatal_hit_from(enemy_mutant))
            expect(s.logic_state.scenario_id).toBe(SCENARIOS.NoLoss)
        end)

        it("records that the death was indoors", function()
            H.fakes.set_level("underground_lab")
            local s = factory.create_new(fatal_hit_from(enemy_mutant))
            expect(s.logic_state.player_died_indoor).toBe(true)
        end)

        it("calls no finder at all", function()
            H.fakes.set_level("underground_lab")
            factory.create_new(fatal_hit_from(enemy_mutant))
            expect(B.finder_count("friendly_stalker")).toBe(0)
            expect(B.finder_count("enemy")).toBe(0)
        end)

        -- CHARACTERIZATION: this arm leaves scenario_loot_scalar at its
        -- initialiser of 1.0 (:157) even though it forces NoLoss, unlike every
        -- other no-loss arm which sets 0. Harmless today because NoLoss's
        -- TransferItems is a no-op, but it is inconsistent and would matter if
        -- the indoor case ever grew a real scenario.
        it("CHARACTERIZATION: leaves the loot scalar at 1.0", function()
            H.fakes.set_level("underground_lab")
            local s = factory.create_new(fatal_hit_from(enemy_mutant))
            expect(s.logic_state.scenario_loot_scalar).toBe(1.0)
        end)
    end)

    describe("given the player killed themselves", function()
        local function suicide()
            return factory.create_new(fatal_hit_from(db.actor))
        end

        it("puts three quarters at stake", function()
            expect(suicide().logic_state.scenario_loot_scalar).toBeCloseTo(0.75)
        end)

        it("records the killer type as self", function()
            expect(suicide().logic_state.killer_type).toBe(soulslike.entity_type.Self)
        end)

        describe("and carries a backpack", function()
            it("can run the Default scenario", function()
                H.fakes.set_ltx("itm_actor_backpack", { kind = "i_backpack" })
                H.world.give("actor", "itm_actor_backpack")
                H.fakes.set_random_const(0.99)   -- weight the roll to Default
                expect(suicide().logic_state.scenario_id).toBe(SCENARIOS.Default)
            end)
        end)

        describe("and carries no backpack", function()
            it("can only run NoLoss", function()
                H.fakes.set_random_const(0.99)
                expect(suicide().logic_state.scenario_id).toBe(SCENARIOS.NoLoss)
            end)
        end)
    end)

    describe("given a friendly stalker killed the player", function()
        -- FIXES: D9. This arm set `rescuer = hit.draftsman`, but
        -- compute_fatal_hit_info builds its aggregate as
        -- {draftsman_type, power, fatal_hit} (:59-65, :81-83) and never puts
        -- `draftsman` on it. The rescuer was therefore always nil, so the
        -- wakeup message fell back to its "it's a mystery" path even though the
        -- mod knew exactly who was standing over the body.
        local function friendly_fire()
            local killer = B.make_stalker{ name = "remorseful", goodwill = 500 }
            local s = factory.create_new(fatal_hit_from(killer))
            return s, killer
        end

        it("runs NoLoss", function()
            local s = friendly_fire()
            expect(s.logic_state.scenario_id).toBe(SCENARIOS.NoLoss)
        end)

        it("puts nothing at stake", function()
            local s = friendly_fire()
            expect(s.logic_state.scenario_loot_scalar).toBe(0.0)
        end)

        it("makes the killer the rescuer", function()
            local s, killer = friendly_fire()
            expect(s.logic_state.rescuer_id).toBe(killer:id())
        end)

        it("assigns no looter", function()
            local s = friendly_fire()
            expect(s.logic_state.looter_id).toBeNil()
        end)

        -- The rescuer comes from the killer, so the finder must not be
        -- consulted -- that is what distinguishes this arm from the enemy one.
        it("does not search for a nearby friendly", function()
            friendly_fire()
            expect(B.finder_count("friendly_stalker")).toBe(0)
        end)

        it("treats exactly neutral goodwill as friendly", function()
            local killer = B.make_stalker{ name = "neutral", goodwill = 0 }
            local s = factory.create_new(fatal_hit_from(killer))
            expect(s.logic_state.scenario_id).toBe(SCENARIOS.NoLoss)
            expect(s.logic_state.rescuer_id).toBe(killer:id())
        end)
    end)

    describe("given an enemy stalker killed the player", function()
        local function murdered()
            local killer = B.make_stalker{ name = "bandit", goodwill = -1000 }
            return factory.create_new(fatal_hit_from(killer)), killer
        end

        it("puts everything at stake", function()
            local s = murdered()
            expect(s.logic_state.scenario_loot_scalar).toBe(1.0)
        end)

        it("takes the looter from the enemy-stalker finder", function()
            murdered()
            expect(B.finder_count("enemy_stalker")).toBe(1)
            expect(B.finder_count("enemy")).toBe(0)
            expect(B.finder_count("enemy_mutant")).toBe(0)
        end)

        it("finds a separate rescuer", function()
            local s = murdered()
            expect(s.logic_state.rescuer_id).toBe(friendly:id())
        end)

        it("records the looter as a stalker", function()
            local s = murdered()
            expect(s.logic_state.looter_type).toBe(soulslike.entity_type.Stalker)
        end)

        it("records the killer", function()
            local s, killer = murdered()
            expect(s.logic_state.killer_id).toBe(killer:id())
            expect(s.logic_state.killer_type).toBe(soulslike.entity_type.Stalker)
        end)
    end)

    describe("given a mutant killed the player", function()
        local function mauled()
            local killer = B.make_monster{ name = "boar" }
            return factory.create_new(fatal_hit_from(killer))
        end

        it("puts everything at stake", function()
            expect(mauled().logic_state.scenario_loot_scalar).toBe(1.0)
        end)

        it("takes the looter from the mutant finder", function()
            mauled()
            expect(B.finder_count("enemy_mutant")).toBe(1)
            expect(B.finder_count("enemy_stalker")).toBe(0)
        end)

        it("records the looter as a monster", function()
            expect(mauled().logic_state.looter_type).toBe(soulslike.entity_type.Monster)
        end)
    end)

    describe("given an anomaly killed the player", function()
        local function burned()
            local killer = B.make_anomaly{ name = "burner" }
            return factory.create_new(fatal_hit_from(killer))
        end

        it("puts a quarter at stake", function()
            expect(burned().logic_state.scenario_loot_scalar).toBeCloseTo(0.25)
        end)

        it("takes the looter from the generic enemy finder", function()
            burned()
            expect(B.finder_count("enemy")).toBe(1)
        end)
    end)

    describe("given the player bled out", function()
        -- No draftsman at all: damage-over-time resolves to the Other bucket.
        local function bled_out()
            return factory.create_new{ B.make_hit{
                power = 50, is_fatal = true, time = 1000,
            } }
        end

        it("puts a quarter at stake", function()
            expect(bled_out().logic_state.scenario_loot_scalar).toBeCloseTo(0.25)
        end)

        it("records no killer", function()
            expect(bled_out().logic_state.killer_id).toBeNil()
        end)

        it("still records the fatal hit type", function()
            expect(bled_out().logic_state.fatal_hit_type).toBeDefined()
        end)
    end)

    describe("given no hits at all", function()
        it("falls through to the catch-all arm", function()
            local s = factory.create_new{}
            expect(s.logic_state.scenario_loot_scalar).toBeCloseTo(0.25)
        end)

        it("leaves the killer unset", function()
            local s = factory.create_new{}
            expect(s.logic_state.killer_type).toBeNil()
        end)

        it("does not raise", function()
            expect(function() factory.create_new{} end).never.toThrow()
        end)
    end)

    describe("first match wins", function()
        it("prefers the close-range arm over the mutant arm", function()
            boot(30)
            local s = factory.create_new(fatal_hit_from(B.make_monster{}))
            expect(s.logic_state.scenario_id).toBe(SCENARIOS.NoLoss)
            expect(B.finder_count("enemy_mutant")).toBe(0)
        end)

        it("prefers the indoor arm over the mutant arm", function()
            H.fakes.set_level("underground_lab")
            factory.create_new(fatal_hit_from(B.make_monster{}))
            expect(B.finder_count("enemy_mutant")).toBe(0)
        end)

        it("prefers a debug flag over everything", function()
            boot(30)
            H.fakes.set_mcm("debug/is_enabled", true)
            H.fakes.set_mcm("debug/debug_the_default_scenario", true)
            local s = factory.create_new(fatal_hit_from(B.make_monster{}))
            expect(s.logic_state.scenario_id).toBe(SCENARIOS.Default)
        end)
    end)

    describe("distance measurement", function()
        it("uses the graph distance when the spawn is on another level", function()
            boot()
            H.set_spawn{ level = "jupiter", position = { x = 0, y = 0, z = 0 } }
            H.fakes.graph_distance = 30      -- inside the close band

            local s = factory.create_new(fatal_hit_from(B.make_monster{}))
            expect(s.logic_state.scenario_id).toBe(SCENARIOS.NoLoss)
            expect(s.logic_state.scenario_loot_scalar).toBe(0)
        end)

        -- FIXES: D6. With no spawn ever recorded, the fallback built a vector
        -- from nil coordinates. That is not a catchable Lua error in a release
        -- build: NDEBUG compiles out luabind's no-matching-overload guard
        -- (config.hpp:81-91), so execution runs off the end of the overload
        -- table (class_rep.cpp:688). An access violation on the death path.
        describe("given no spawn was ever recorded", function()
            beforeEach(function()
                boot()
                soulslike.get_soulslike_state().spawn_location = {
                    level = nil,
                    position = { x = nil, y = nil, z = nil },
                    angle = { x = nil, y = nil, z = nil },
                    level_vertex_id = nil,
                    game_vertex_id = nil,
                }
            end)

            it("does not raise", function()
                expect(function()
                    factory.create_new(fatal_hit_from(B.make_monster{}))
                end).never.toThrow()
            end)

            it("still returns a scenario", function()
                expect(factory.create_new(fatal_hit_from(B.make_monster{}))).toBeDefined()
            end)

            -- Degrading to "far from spawn" is the safe default: it runs the
            -- normal death scenario rather than silently gifting a no-loss.
            it("treats the death as far from spawn", function()
                factory.create_new(fatal_hit_from(B.make_monster{}))
                expect(B.finder_count("enemy_mutant")).toBe(1)
            end)
        end)
    end)

    describe("dying in water", function()
        it("halves the stake", function()
            save_var(db.actor, "grw_in_water", true)
            local s = factory.create_new(fatal_hit_from(B.make_anomaly{}))
            expect(s.logic_state.scenario_loot_scalar).toBeCloseTo(0.125)
        end)

        it("records that the death was in water", function()
            save_var(db.actor, "grw_in_water", true)
            local s = factory.create_new(fatal_hit_from(B.make_anomaly{}))
            expect(s.logic_state.player_died_in_water).toBe(true)
        end)

        it("leaves the stake alone otherwise", function()
            local s = factory.create_new(fatal_hit_from(B.make_anomaly{}))
            expect(s.logic_state.scenario_loot_scalar).toBeCloseTo(0.25)
        end)
    end)

    describe("the applied setters", function()
        it("records the level name", function()
            local s = factory.create_new(fatal_hit_from(B.make_monster{}))
            expect(s.logic_state.story.level_name).toBe("zaton")
        end)

        it("spends exactly one roll on the scenario pick", function()
            local before = H.fakes.random_count()
            factory.create_new(fatal_hit_from(B.make_monster{}))
            expect(H.fakes.random_count() - before).toBe(1)
        end)
    end)
end)

describe("soulslike_scenario_logic_factory.create_by_id()", function()

    beforeEach(function()
        boot()
        SCENARIOS = _G.soulslike.SCENARIOS
    end)

    local CASES = {
        { id = "Default",         class = "DefaultSoulslikeScenarioLogic" },
        { id = "RFDetectorStash", class = "RFDetectorSoulslikeScenarioLogic" },
        { id = "HiddenStash",     class = "HiddenStashSoulslikeScenarioLogic" },
        { id = "NoLoss",          class = "NoLossSoulslikeScenarioLogic" },
    }

    for _, case in ipairs(CASES) do
        describe("given the " .. case.id .. " id", function()
            it("constructs " .. case.class, function()
                local s = factory.create_by_id(SCENARIOS[case.id])
                expect(H.class.is_instance(s, _G[case.class])).toBe(true)
            end)

            it("stamps the scenario id onto the state", function()
                local s = factory.create_by_id(SCENARIOS[case.id])
                expect(s.logic_state.scenario_id).toBe(SCENARIOS[case.id])
            end)
        end)
    end

    describe("given an unrecognised id", function()
        it("falls back to the Default scenario", function()
            local s = factory.create_by_id(9999)
            expect(H.class.is_instance(s, _G.DefaultSoulslikeScenarioLogic)).toBe(true)
        end)
    end)

    describe("given no id at all", function()
        it("falls back to the Default scenario", function()
            expect(factory.create_by_id(nil).logic_state.scenario_id).toBe(SCENARIOS.Default)
        end)
    end)

    describe("given a saved state", function()
        -- The state is forwarded verbatim into __init, which takes the
        -- restore branch and re-reads no MCM (soulslike_scenarios.script:227).
        it("adopts it by reference", function()
            local state = B.make_logic_state{ rank = 4242 }
            local s = factory.create_by_id(SCENARIOS.Default, state)
            expect(s.logic_state).toBe(state)
        end)

        it("does not rebuild the state from MCM", function()
            H.fakes.set_mcm("items/item_loss_scalar", 0.99)
            local state = B.make_logic_state{ item_loss_scalar = 0.2 }
            local s = factory.create_by_id(SCENARIOS.Default, state)
            expect(s.logic_state.item_loss_scalar).toBeCloseTo(0.2)
        end)
    end)
end)

describe("find_backpack()", function()

    local find_backpack

    beforeEach(function()
        boot()
        find_backpack = H.loader.upvalue(
            _G.soulslike_scenario_logic_factory.create_new, "find_backpack")
        H.fakes.set_ltx("itm_actor_backpack", { kind = "i_backpack" })
    end)

    it("is reachable as an upvalue of create_new", function()
        expect(find_backpack).toBeType("function")
    end)

    describe("given the actor carries a backpack", function()
        it("finds it", function()
            H.world.give("actor", "itm_actor_backpack")
            expect(find_backpack()).toBe(true)
        end)

        it("finds it among other items", function()
            H.world.give("actor", "medkit")
            H.world.give("actor", "itm_actor_backpack")
            H.world.give("actor", "bread")
            expect(find_backpack()).toBe(true)
        end)

        -- The inner callback reassigns has_backpack for every item, so it only
        -- reports true because it stops on the first match (:94).
        it("stops iterating at the backpack", function()
            H.world.give("actor", "itm_actor_backpack")
            H.world.give("actor", "medkit")
            expect(find_backpack()).toBe(true)
        end)
    end)

    describe("given the actor carries no backpack", function()
        it("returns false", function()
            H.world.give("actor", "medkit")
            expect(find_backpack()).toBe(false)
        end)

        it("returns false on an empty inventory", function()
            expect(find_backpack()).toBe(false)
        end)
    end)
end)

return true
