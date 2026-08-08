-- soulslike_message_factory.create (soulslike_message_factory.script:133).
--
-- Builds the rescuer's wake-up note by concatenating optional clauses. Fully
-- exported and near-pure: with game.translate_string as identity and
-- math.random pinned, the output is exactly the sequence of string ids, so
-- clause presence and ordering are directly assertable.

local H = require("harness.init")
local fakes = H.fakes

describe("soulslike_message_factory.create()", function()

    beforeEach(function()
        H.boot{ load = { "soulslike_classes", "soulslike",
                         "soulslike_message_factory" } }
        fakes.set_random_const(1)   -- always the first variant of each set
    end)

    local RESCUER = true            -- only truthiness is checked

    local function create(rescuer, params)
        return soulslike_message_factory.create(rescuer, params or {})
    end

    describe("given a rescuer", function()

        describe("and no optional flags", function()
            it("opens with the initial message", function()
                expect(create(RESCUER, {})).toContain("st_soulslike_rescuer_initial_1")
            end)

            it("closes with the stay-safe message", function()
                expect(create(RESCUER, {})).toContain("st_soulslike_rescuer_stay_safe_1")
            end)
        end)

        describe("and every optional flag set", function()
            local function full()
                return create(RESCUER, {
                    gave_food_or_water   = true,
                    enemy                = { name = "V", community = "bandit" },
                    has_pda_marker       = true,
                    has_stash_pda_marker = true,
                    radio_freq           = "121.5",
                    items_were_lost      = true,
                    looter_type          = soulslike.entity_type.Stalker,
                })
            end

            it("emits the clauses in the documented order", function()
                local expected = {
                    "st_soulslike_rescuer_initial_1",
                    "st_soulslike_rescuer_food_1",
                    "st_soulslike_rescuer_enemy_looter_1",
                    "st_soulslike_rescuer_pda_1",
                    "st_soulslike_hidden_stash_1",
                    "st_soulslike_rescuer_radio_freq_1",
                    "st_soulslike_rescuer_used_items_1",
                    "st_soulslike_rescuer_stay_safe_1",
                }
                local msg, pos = full(), 0
                for _, frag in ipairs(expected) do
                    local at = msg:find(frag, pos + 1, true)
                    expect(at).toBeDefined()
                    pos = at
                end
            end)

            it("always terminates with stay-safe", function()
                local msg = full()
                local closer = "st_soulslike_rescuer_stay_safe_1"
                expect(msg:sub(-#closer)).toBe(closer)
            end)
        end)

        describe("and the death happened indoors", function()
            it("uses the indoor opener", function()
                local msg = create(RESCUER, { player_died_indoor = true,
                                              level_name = "labx8" })
                expect(msg).toContain("st_soulslike_rescuer_indoor_1")
            end)

            it("omits the standard opener", function()
                local msg = create(RESCUER, { player_died_indoor = true,
                                              level_name = "labx8" })
                expect(msg).never.toContain("st_soulslike_rescuer_initial_1")
            end)
        end)

        describe("and gave_food_or_water is set", function()
            it("includes the food clause", function()
                expect(create(RESCUER, { gave_food_or_water = true }))
                    .toContain("st_soulslike_rescuer_food_1")
            end)
        end)

        describe("and gave_food_or_water is unset", function()
            it("omits the food clause", function()
                expect(create(RESCUER, {})).never.toContain("st_soulslike_rescuer_food_1")
            end)
        end)

        describe("and has_pda_marker is set", function()
            it("includes the pda clause", function()
                expect(create(RESCUER, { has_pda_marker = true }))
                    .toContain("st_soulslike_rescuer_pda_1")
            end)
        end)

        describe("and has_stash_pda_marker is set", function()
            it("includes the hidden-stash clause", function()
                expect(create(RESCUER, { has_stash_pda_marker = true }))
                    .toContain("st_soulslike_hidden_stash_1")
            end)
        end)

        describe("and radio_freq is set", function()
            it("includes the radio clause", function()
                expect(create(RESCUER, { radio_freq = "121.5" }))
                    .toContain("st_soulslike_rescuer_radio_freq_1")
            end)
        end)

        describe("and a plain looter took the items", function()
            it("uses the enemy-looter clause", function()
                expect(create(RESCUER, { enemy = { name = "Vasya", community = "bandit" } }))
                    .toContain("st_soulslike_rescuer_enemy_looter_1")
            end)
        end)

        describe("and the looter has tarkov_experience", function()
            local params = { enemy = { name = "Vasya", community = "bandit",
                                       tarkov_experience = true } }

            it("uses the tarkov clause", function()
                expect(create(RESCUER, params))
                    .toContain("st_soulslike_rescuer_enemy_tarkov_looter_1")
            end)

            it("omits the plain enemy-looter clause", function()
                expect(create(RESCUER, params))
                    .never.toContain("st_soulslike_rescuer_enemy_looter_1")
            end)
        end)

        describe("and items were lost to a monster", function()
            local params = { items_were_lost = true,
                             looter_type = 2 }   -- entity_type.Monster

            it("uses the monster-looter clause", function()
                expect(create(RESCUER, params))
                    .toContain("st_soulslike_rescuer_monster_looter_1")
            end)

            it("omits the used-items clause", function()
                expect(create(RESCUER, params))
                    .never.toContain("st_soulslike_rescuer_used_items_1")
            end)
        end)

        describe("and items were lost to a stalker", function()
            it("uses the used-items clause", function()
                expect(create(RESCUER, { items_were_lost = true,
                                         looter_type = 1 }))   -- Stalker
                    .toContain("st_soulslike_rescuer_used_items_1")
            end)
        end)

        describe("and items were lost with no looter_type", function()
            it("falls back to the used-items clause", function()
                -- The branch tests `looter_type == Monster`, so nil takes the
                -- else arm.
                expect(create(RESCUER, { items_were_lost = true }))
                    .toContain("st_soulslike_rescuer_used_items_1")
            end)
        end)

        describe("clause joining", function()
            it("separates clauses with a single space", function()
                expect(create(RESCUER, { gave_food_or_water = true })).toContain(
                    "st_soulslike_rescuer_initial_1 st_soulslike_rescuer_food_1")
            end)
        end)

        describe("variant selection", function()
            it("picks the variant math.random returns", function()
                fakes.set_random_const(3)
                local msg = create(RESCUER, {})
                expect(msg).toContain("st_soulslike_rescuer_initial_3")
                expect(msg).toContain("st_soulslike_rescuer_stay_safe_3")
            end)

            it("offers five variants per message set", function()
                for i = 1, 5 do
                    fakes.set_random_const(i)
                    expect(create(RESCUER, {}))
                        .toContain("st_soulslike_rescuer_initial_" .. i)
                end
            end)
        end)
    end)

    describe("given no rescuer", function()

        describe("and no optional flags", function()
            it("returns just the generic opener", function()
                expect(create(nil, {})).toBe("st_soulslike_rescuer_initial_generic")
            end)
        end)

        describe("and gave_food_or_water is set", function()
            it("includes the generic food clause", function()
                expect(create(nil, { gave_food_or_water = true }))
                    .toContain("st_soulslike_rescuer_food_generic")
            end)

            it("still has no stay-safe closer", function()
                -- Deliberate asymmetry with the rescuer branch.
                expect(create(nil, { gave_food_or_water = true }))
                    .never.toContain("stay_safe")
            end)
        end)

        describe("and any of the three pda flags is set", function()
            it("includes the generic pda clause", function()
                for _, flag in ipairs({ "has_pda_marker", "has_stash_pda_marker",
                                        "has_multi_stash_pda_marker" }) do
                    expect(create(nil, { [flag] = true }))
                        .toContain("st_soulslike_rescuer_pda_generic")
                end
            end)
        end)

        describe("and all three pda flags are set", function()
            it("emits the pda clause exactly once", function()
                local msg = create(nil, {
                    has_pda_marker = true, has_stash_pda_marker = true,
                    has_multi_stash_pda_marker = true,
                })
                local _, count = msg:gsub("st_soulslike_rescuer_pda_generic", "")
                expect(count).toBe(1)
            end)
        end)

        describe("and radio_freq is set", function()
            it("includes the generic radio clause", function()
                expect(create(nil, { radio_freq = "121.5" }))
                    .toContain("st_soulslike_rescuer_radio_generic")
            end)
        end)

        describe("and looter or items_were_lost are set", function()
            it("ignores them, since those clauses are rescuer-only", function()
                expect(create(nil, {
                    enemy = { name = "V", community = "bandit" },
                    items_were_lost = true,
                })).toBe("st_soulslike_rescuer_initial_generic")
            end)
        end)
    end)
end)

return true
