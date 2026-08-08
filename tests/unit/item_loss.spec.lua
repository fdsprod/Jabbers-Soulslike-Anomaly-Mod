-- SoulslikeScenarioLogic:IsItemLossAllowed (soulslike_scenarios.script:919-984)
--
-- Decides what the player permanently loses, so it is the single most
-- consequential predicate in the mod. Pure: no side effects beyond debug
-- logging, which makes it exhaustively table-testable.
--
-- Two structures worth keeping in mind while reading:
--
--   * The six category GATES read the logic_state snapshot taken at __init,
--     but the four KEEP-ROLLS read live MCM. A spec that sets one and asserts
--     the other will look correct and prove nothing.
--
--   * `and` short-circuits, so exactly 0 or 1 math.random() calls happen per
--     invocation. The budget is asserted separately because a stray roll would
--     desynchronise every subsequent roll in a real death sequence.

local H = require("harness.init")
local B = H.builders

local MOD_SCRIPTS = {
    "soulslike_classes", "soulslike", "soulslike_mcm",
    "soulslike_message_factory", "soulslike_scenarios",
}

-- Kinds map onto the _kind tag the Is* predicates read. Toolkits are the
-- exception: the mod replaces _G.IsToolkit with a tools_list section lookup
-- (soulslike.script:196-201), so a toolkit case needs a REAL section and its
-- kind tag is irrelevant.
local TOOLKIT_SECTION = "itm_basickit"

local function boot()
    H.boot{ load = MOD_SCRIPTS }
    H.fakes.set_random_min()
end

--- Build the scenario and the item for one case, then run the predicate.
--- Returns allowed, rolls_spent.
local function evaluate(case)
    boot()

    for key, value in pairs(case.mcm or {}) do
        H.fakes.set_mcm(key, value)
    end

    local scenario = B.make_scenario{
        class = case.class,
        state = case.state or {},
    }

    local section = case.section or "itm_generic"
    if case.backpack then
        H.fakes.set_ltx(section, { kind = "i_backpack" })
    end

    local item = B.make_item{ section = section, kind = case.kind }

    if case.rolls then
        H.fakes.set_random_sequence(case.rolls)
    else
        -- No roll expected. An empty queue turns an unexpected roll into a
        -- loud failure rather than a silently reused value.
        H.fakes.set_random_sequence{}
    end

    local before = H.fakes.random_count()
    local allowed = scenario:IsItemLossAllowed(item)
    return allowed, H.fakes.random_count() - before
end

-- Each case is one row of the decision table. `budget` is the exact number of
-- math.random() calls the case may spend.
local CASES = {
    {
        name = "the player died in water",
        why  = "the water short-circuit precedes every other check",
        kind = "weapon", section = "wpn_ak74",
        state = { player_died_in_water = true },
        allowed = false, budget = 0,
    },
    {
        name = "a weapon and weapon loss is disallowed",
        kind = "weapon", section = "wpn_ak74",
        state = { allow_weapon_loss = false },
        allowed = false, budget = 0,
    },
    {
        name = "an artefact and artefact loss is disallowed",
        kind = "artefact", section = "af_medusa",
        state = { allow_artifact_loss = false },
        allowed = false, budget = 0,
    },
    {
        name = "an outfit and outfit loss is disallowed",
        kind = "outfit", section = "novice_outfit",
        state = { allow_outfit_loss = false },
        allowed = false, budget = 0,
    },
    {
        name = "headgear and headgear loss is disallowed",
        kind = "headgear", section = "helm_respirator",
        state = { allow_headgear_loss = false },
        allowed = false, budget = 0,
    },
    {
        name = "a toolkit and toolkit loss is disallowed",
        why  = "IsToolkit is a section lookup, not a kind tag",
        section = TOOLKIT_SECTION,
        state = { allow_toolkit_loss = false },
        allowed = false, budget = 0,
    },
    {
        name = "a backpack",
        why  = "refused unconditionally -- there is no allow flag for it",
        section = "itm_actor_backpack", backpack = true,
        allowed = false, budget = 0,
    },
    {
        name = "a grenade while weapon loss is disallowed",
        why  = "grenades are not weapons, so the weapon gate does not apply",
        kind = "grenade", section = "grenade_f1",
        state = { allow_weapon_loss = false },
        allowed = true, budget = 0,
    },
    {
        name = "an outfit and the keep roll succeeds",
        kind = "outfit", section = "novice_outfit",
        rolls = { 0.10 },
        allowed = false, budget = 1,
    },
    {
        name = "an outfit and the keep roll fails",
        kind = "outfit", section = "novice_outfit",
        rolls = { 0.90 },
        allowed = true, budget = 1,
    },
    {
        name = "an outfit and the roll lands exactly on the keep chance",
        why  = "the comparison is `<`, so the boundary loses the item",
        kind = "outfit", section = "novice_outfit",
        rolls = { 0.25 },
        allowed = true, budget = 1,
    },
    {
        name = "headgear and the keep roll succeeds",
        kind = "headgear", section = "helm_respirator",
        rolls = { 0.10 },
        allowed = false, budget = 1,
    },
    {
        name = "a weapon and the keep roll succeeds",
        kind = "weapon", section = "wpn_ak74",
        rolls = { 0.10 },
        allowed = false, budget = 1,
    },
    {
        name = "an artefact and the keep roll succeeds",
        kind = "artefact", section = "af_medusa",
        rolls = { 0.10 },
        allowed = false, budget = 1,
    },
    {
        name = "a weapon and a raised keep chance covers the roll",
        why  = "the keep chances are read live from MCM, not from the snapshot",
        kind = "weapon", section = "wpn_ak74",
        mcm  = { ["items/weapon_keep_chance"] = 0.95 },
        rolls = { 0.90 },
        allowed = false, budget = 1,
    },
    {
        name = "an ordinary item",
        section = "medkit",
        allowed = true, budget = 0,
    },
    {
        name = "a toolkit and toolkit loss is allowed",
        why  = "toolkits have an allow flag but no keep roll, unlike the other four",
        section = TOOLKIT_SECTION,
        allowed = true, budget = 0,
    },
}

describe("SoulslikeScenarioLogic:IsItemLossAllowed()", function()

    for _, case in ipairs(CASES) do
        local context = "given " .. case.name
        if case.why then context = context .. " (" .. case.why .. ")" end

        describe(context, function()
            it(case.allowed and "allows the loss" or "refuses the loss", function()
                local allowed = evaluate(case)
                expect(allowed).toBe(case.allowed)
            end)

            it("spends " .. case.budget .. " random roll(s)", function()
                local _, spent = evaluate(case)
                expect(spent).toBe(case.budget)
            end)
        end)
    end

    describe("the snapshot / live-MCM split", function()
        -- The gates read logic_state, captured at construction. Changing MCM
        -- afterwards must not move a gate.
        it("ignores an MCM change to a category gate after construction", function()
            boot()
            local scenario = B.make_scenario{ state = { allow_weapon_loss = false } }
            H.fakes.set_mcm("items/allow_weapon_loss", true)
            H.fakes.set_random_sequence{}

            local ak = B.make_item{ section = "wpn_ak74", kind = "weapon" }
            expect(scenario:IsItemLossAllowed(ak)).toBe(false)
        end)

        -- The keep chances do NOT come from the snapshot, so changing MCM
        -- after construction does move them.
        it("honours an MCM change to a keep chance after construction", function()
            boot()
            local scenario = B.make_scenario{}
            H.fakes.set_mcm("items/weapon_keep_chance", 1.0)
            H.fakes.set_random_sequence{ 0.99 }

            local ak = B.make_item{ section = "wpn_ak74", kind = "weapon" }
            expect(scenario:IsItemLossAllowed(ak)).toBe(false)
        end)
    end)

    describe("given the NoLoss scenario", function()
        -- The subclass overrides the predicate outright
        -- (soulslike_scenarios.script:1488).
        it("refuses every item", function()
            local allowed = evaluate{
                class = "NoLossSoulslikeScenarioLogic",
                kind = "weapon", section = "wpn_ak74",
            }
            expect(allowed).toBe(false)
        end)

        it("refuses even an ordinary item", function()
            local allowed = evaluate{
                class = "NoLossSoulslikeScenarioLogic",
                section = "medkit",
            }
            expect(allowed).toBe(false)
        end)

        it("spends no rolls", function()
            local _, spent = evaluate{
                class = "NoLossSoulslikeScenarioLogic",
                kind = "outfit", section = "novice_outfit",
            }
            expect(spent).toBe(0)
        end)
    end)

    describe("gate ordering", function()
        -- The water short-circuit is first, so it wins over a category that
        -- would otherwise spend a roll.
        it("lets the water check pre-empt an outfit keep roll", function()
            local allowed, spent = evaluate{
                kind = "outfit", section = "novice_outfit",
                state = { player_died_in_water = true },
            }
            expect(allowed).toBe(false)
            expect(spent).toBe(0)
        end)

        -- Gates run before rolls, so a disallowed category never reaches its
        -- keep roll.
        it("lets a category gate pre-empt that category's keep roll", function()
            local _, spent = evaluate{
                kind = "weapon", section = "wpn_ak74",
                state = { allow_weapon_loss = false },
            }
            expect(spent).toBe(0)
        end)
    end)
end)

return true
