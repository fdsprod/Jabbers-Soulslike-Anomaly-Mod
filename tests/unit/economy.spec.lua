-- The four irreversible player-facing deductions:
--   ApplyRankLoss           (soulslike_scenarios.script:390-404)
--   ApplyReputationLoss     (:406-420)
--   ApplyItemConditionLoss  (:422-478)
--   ApplyMoneyLoss          (:1227-1241)
--
-- Rank and reputation land in int-typed engine fields via a setter that does
-- not clamp and truncates toward zero (character_info_defs.h:8,
-- policy.hpp:377), so what the mod computes is what the player is left with.

local H = require("harness.init")
local B = H.builders

local MOD_SCRIPTS = {
    "soulslike_classes", "soulslike", "soulslike_mcm",
    "soulslike_message_factory", "soulslike_scenarios",
}

local function boot(opts)
    H.boot(opts or { load = MOD_SCRIPTS })
    H.fakes.set_random_min()
end

describe("SoulslikeScenarioLogic:ApplyRankLoss()", function()

    beforeEach(function() boot() end)

    describe("given rank loss is disabled", function()
        it("leaves the rank alone", function()
            H.fakes.set_mcm("character/allow_rank_loss", false)
            local actor = H.set_actor{ rank = 5000 }
            B.make_scenario{}:ApplyRankLoss()
            expect(actor:character_rank()).toBe(5000)
        end)

        it("does not notify the statistics system", function()
            H.fakes.set_mcm("character/allow_rank_loss", false)
            H.set_actor{ rank = 5000 }
            B.make_scenario{}:ApplyRankLoss()
            expect(H.fakes.call_count("check_for_rank_change")).toBe(0)
        end)
    end)

    describe("given a positive rank", function()
        it("deducts the configured percentage", function()
            local actor = H.set_actor{ rank = 5000 }
            B.make_scenario{ state = { rank_loss_percent = 0.02 } }:ApplyRankLoss()
            expect(actor:character_rank()).toBe(4900)
        end)

        it("notifies the statistics system exactly once", function()
            H.set_actor{ rank = 5000 }
            B.make_scenario{}:ApplyRankLoss()
            expect(H.fakes.call_count("check_for_rank_change")).toBe(1)
        end)

        -- FIXES: D11. The engine stores an int, so a fractional result is
        -- truncated on the way in; the mod should decide the value rather than
        -- leaving rounding to luabind's static_cast.
        it("stores an integer", function()
            local actor = H.set_actor{ rank = 1001 }
            B.make_scenario{ state = { rank_loss_percent = 0.02 } }:ApplyRankLoss()
            expect(actor:character_rank() % 1).toBe(0)
        end)
    end)

    describe("given a rank of zero", function()
        it("leaves it at zero", function()
            local actor = H.set_actor{ rank = 0 }
            B.make_scenario{}:ApplyRankLoss()
            expect(actor:character_rank()).toBe(0)
        end)
    end)

    describe("given a negative rank", function()
        -- FIXES: D11. math.abs made the loss positive regardless of sign, so a
        -- negative rank was driven further negative -- a penalty that grows
        -- without bound instead of a percentage deduction. Nothing in the
        -- engine clamps it back (InventoryOwner.cpp:450-491).
        it("does not push the rank further negative", function()
            local actor = H.set_actor{ rank = -1000 }
            B.make_scenario{ state = { rank_loss_percent = 0.02 } }:ApplyRankLoss()
            expect(actor:character_rank()).never.toBeLessThan(-1000)
        end)

        it("clamps the result at zero rather than going deeper", function()
            local actor = H.set_actor{ rank = -1000 }
            B.make_scenario{ state = { rank_loss_percent = 0.02 } }:ApplyRankLoss()
            expect(actor:character_rank()).toBe(0)
        end)
    end)

    describe("given a loss percent of zero", function()
        it("changes nothing", function()
            local actor = H.set_actor{ rank = 5000 }
            B.make_scenario{ state = { rank_loss_percent = 0 } }:ApplyRankLoss()
            expect(actor:character_rank()).toBe(5000)
        end)
    end)
end)

describe("SoulslikeScenarioLogic:ApplyReputationLoss()", function()

    beforeEach(function() boot() end)

    describe("given reputation loss is disabled", function()
        it("leaves the reputation alone", function()
            H.fakes.set_mcm("character/allow_rep_loss", false)
            local actor = H.set_actor{ reputation = 400 }
            B.make_scenario{}:ApplyReputationLoss()
            expect(actor:character_reputation()).toBe(400)
        end)
    end)

    describe("given a positive reputation", function()
        it("deducts the configured percentage", function()
            local actor = H.set_actor{ reputation = 400 }
            B.make_scenario{ state = { rep_loss_percent = 0.05 } }:ApplyReputationLoss()
            expect(actor:character_reputation()).toBe(380)
        end)

        it("notifies the statistics system exactly once", function()
            H.set_actor{ reputation = 400 }
            B.make_scenario{}:ApplyReputationLoss()
            expect(H.fakes.call_count("check_for_reputation_change")).toBe(1)
        end)

        it("stores an integer", function()
            local actor = H.set_actor{ reputation = 401 }
            B.make_scenario{ state = { rep_loss_percent = 0.05 } }:ApplyReputationLoss()
            expect(actor:character_reputation() % 1).toBe(0)
        end)
    end)

    describe("given a negative reputation", function()
        -- FIXES: D11. Reputation legitimately runs negative for a hated actor,
        -- so this is the sign case that actually happens in play. The old
        -- math.abs form always subtracted, driving it further negative every
        -- death without bound.
        it("does not push it further negative", function()
            local actor = H.set_actor{ reputation = -400 }
            B.make_scenario{ state = { rep_loss_percent = 0.05 } }:ApplyReputationLoss()
            expect(actor:character_reputation()).never.toBeLessThan(-400)
        end)

        -- Decays toward neutral rather than clamping at zero: clamping would
        -- wipe out earned standing in one death, which is a reward, not a loss.
        it("decays it toward zero by the same percentage", function()
            local actor = H.set_actor{ reputation = -400 }
            B.make_scenario{ state = { rep_loss_percent = 0.05 } }:ApplyReputationLoss()
            expect(actor:character_reputation()).toBe(-380)
        end)

        it("never overshoots past neutral", function()
            local actor = H.set_actor{ reputation = -10 }
            B.make_scenario{ state = { rep_loss_percent = 1.0 } }:ApplyReputationLoss()
            expect(actor:character_reputation()).toBe(0)
        end)
    end)

    describe("given a reputation of zero", function()
        it("leaves it at zero", function()
            local actor = H.set_actor{ reputation = 0 }
            B.make_scenario{}:ApplyReputationLoss()
            expect(actor:character_reputation()).toBe(0)
        end)
    end)
end)

describe("SoulslikeScenarioLogic:ApplyMoneyLoss()", function()

    beforeEach(function() boot() end)

    describe("given money loss is disabled", function()
        it("leaves the money alone", function()
            H.fakes.set_mcm("items/allow_money_loss", false)
            local actor = H.set_actor{ money = 10000 }
            H.fakes.set_random_sequence{}
            B.make_scenario{}:ApplyMoneyLoss()
            expect(actor:money()).toBe(10000)
        end)

        it("spends no rolls", function()
            H.fakes.set_mcm("items/allow_money_loss", false)
            H.set_actor{ money = 10000 }
            H.fakes.set_random_sequence{}
            local before = H.fakes.random_count()
            B.make_scenario{}:ApplyMoneyLoss()
            expect(H.fakes.random_count() - before).toBe(0)
        end)
    end)

    describe("given the chance roll fails", function()
        it("leaves the money alone", function()
            local actor = H.set_actor{ money = 10000 }
            H.fakes.set_random_sequence{ 0.99 }     -- >= the 0.5 default
            B.make_scenario{}:ApplyMoneyLoss()
            expect(actor:money()).toBe(10000)
        end)

        it("spends exactly one roll", function()
            H.set_actor{ money = 10000 }
            H.fakes.set_random_sequence{ 0.99 }
            local before = H.fakes.random_count()
            B.make_scenario{}:ApplyMoneyLoss()
            expect(H.fakes.random_count() - before).toBe(1)
        end)
    end)

    describe("given the chance roll succeeds", function()
        it("deducts floor(money * roll * max_percent)", function()
            local actor = H.set_actor{ money = 10000 }
            -- roll 1 passes the 0.5 chance; roll 2 scales the 0.10 max percent.
            H.fakes.set_random_sequence{ 0.1, 0.5 }
            B.make_scenario{}:ApplyMoneyLoss()
            expect(actor:money()).toBe(9500)        -- 10000 - floor(10000*0.05)
        end)

        it("spends exactly two rolls", function()
            H.set_actor{ money = 10000 }
            H.fakes.set_random_sequence{ 0.1, 0.5 }
            local before = H.fakes.random_count()
            B.make_scenario{}:ApplyMoneyLoss()
            expect(H.fakes.random_count() - before).toBe(2)
        end)

        it("never deducts more than the actor holds", function()
            -- give_money does not clamp -- it underflows u32
            -- (InventoryOwner.cpp:630-645) -- so an over-deduction would leave
            -- the player with ~4.29 billion rubles rather than zero.
            local actor = H.set_actor{ money = 10000 }
            H.fakes.set_random_sequence{ 0.0, 1.0 }
            H.fakes.set_mcm("items/money_loss_max_percent", 1.0)
            B.make_scenario{}:ApplyMoneyLoss()
            expect(actor:money()).toBeGreaterThan(-1)
            expect(actor:money()).toBeLessThan(10001)
        end)
    end)

    describe("given the actor is broke", function()
        it("does not call give_money at all", function()
            local actor = H.set_actor{ money = 0 }
            H.fakes.set_random_sequence{ 0.1, 0.5 }
            B.make_scenario{}:ApplyMoneyLoss()
            expect(actor:money()).toBe(0)
        end)
    end)

    describe("given the computed loss rounds down to zero", function()
        it("leaves the money untouched", function()
            local actor = H.set_actor{ money = 5 }
            H.fakes.set_random_sequence{ 0.1, 0.01 }   -- 5 * 0.001 -> floor 0
            B.make_scenario{}:ApplyMoneyLoss()
            expect(actor:money()).toBe(5)
        end)
    end)

    describe("given the NoLoss scenario", function()
        -- NoLoss overrides TransferItems and IsItemLossAllowed but NOT
        -- TransferAndRespawn, which is what calls this (:502). Money is lost
        -- even in the no-item-loss scenario -- deliberate, and worth pinning so
        -- it is not "fixed" by accident.
        it("still loses money", function()
            local actor = H.set_actor{ money = 10000 }
            H.fakes.set_random_sequence{ 0.1, 0.5 }
            B.make_scenario{ class = "NoLossSoulslikeScenarioLogic" }:ApplyMoneyLoss()
            expect(actor:money()).toBe(9500)
        end)
    end)
end)

describe("SoulslikeScenarioLogic:ApplyItemConditionLoss()", function()

    beforeEach(function() boot() end)

    describe("given a weapon", function()
        it("degrades every part by the percentage", function()
            local ak = B.make_item{ section = "wpn_ak74", kind = "weapon" }
            B.make_scenario{}:ApplyItemConditionLoss(ak, nil, 0.10)
            local parts = item_parts.get_parts_con(ak)
            expect(parts.barrel).toBe(90)
            expect(parts.receiver).toBe(90)
        end)

        -- The clamp floor is 1, so condition loss alone can never destroy a
        -- weapon (:460).
        it("never floors a part below 1", function()
            local ak = B.make_item{ section = "wpn_ak74", kind = "weapon" }
            B.make_scenario{}:ApplyItemConditionLoss(ak, nil, 1.0)
            expect(item_parts.get_parts_con(ak).barrel).toBe(1)
        end)

        it("leaves the item intact even at full loss", function()
            local ak = H.world.give("actor", "wpn_ak74", { kind = "weapon" })
            B.make_scenario{}:ApplyItemConditionLoss(ak, nil, 1.0)
            H.tick()
            expect(H.world.where(ak)).toBe("actor")
        end)

        -- CHARACTERIZATION: the weapon path never sets items_were_lost and
        -- never appends to lost_items, because a weapon cannot be destroyed
        -- this way. Only the non-weapon branch does (:471-474).
        it("CHARACTERIZATION: does not mark items as lost", function()
            local ak = B.make_item{ section = "wpn_ak74", kind = "weapon" }
            local s = B.make_scenario{}
            s:ApplyItemConditionLoss(ak, nil, 1.0)
            expect(s.logic_state.story.items_were_lost).toBeNil()
        end)
    end)

    describe("given a weapon and item_parts is absent", function()
        it("returns without touching the item", function()
            H.boot{ load = MOD_SCRIPTS, without = { "item_parts" } }
            H.fakes.set_random_min()
            local ak = H.world.give("actor", "wpn_ak74", { kind = "weapon" })
            B.make_scenario{}:ApplyItemConditionLoss(ak, nil, 1.0)
            H.tick()
            expect(H.world.where(ak)).toBe("actor")
        end)
    end)

    describe("given a degradable non-weapon", function()
        it("degrades its condition", function()
            local suit = H.world.give("actor", "novice_outfit",
                                      { kind = "outfit", condition = 1.0 })
            B.make_scenario{}:ApplyItemConditionLoss(suit, nil, 0.25)
            expect(suit:condition()).toBeCloseTo(0.75)
        end)

        it("keeps it in the container while it survives", function()
            local suit = H.world.give("actor", "novice_outfit",
                                      { kind = "outfit", condition = 1.0 })
            B.make_scenario{}:ApplyItemConditionLoss(suit, nil, 0.25)
            H.tick()
            expect(H.world.where(suit)).toBe("actor")
        end)
    end)

    describe("given a non-weapon degraded to nothing", function()
        -- utils_item.degrade releases the object at condition 0
        -- (utils_item.script:708) -- that is Lua behavior, not the engine's.
        it("destroys the item", function()
            local suit = H.world.give("actor", "novice_outfit",
                                      { kind = "outfit", condition = 1.0 })
            B.make_scenario{}:ApplyItemConditionLoss(suit, nil, 1.0)
            H.tick()
            expect(H.world.where(suit)).toBeNil()
        end)

        it("marks the story as having lost items", function()
            local suit = H.world.give("actor", "novice_outfit", { kind = "outfit" })
            local s = B.make_scenario{}
            s:ApplyItemConditionLoss(suit, nil, 1.0)
            expect(s.logic_state.story.items_were_lost).toBe(true)
        end)

        it("appends the section to the stash's lost_items", function()
            local stash = H.world.container("stash", { id = 777 })
            local suit = H.world.give("actor", "novice_outfit", { kind = "outfit" })
            local s = B.make_scenario{}
            s.game_state.created_stashes[777] = { lost_items = {}, examine = false }

            s:ApplyItemConditionLoss(suit, stash, 1.0)
            expect(s.game_state.created_stashes[777].lost_items).toEqual({ "novice_outfit" })
        end)

        it("still marks the story when there is no stash to record into", function()
            local suit = H.world.give("actor", "novice_outfit", { kind = "outfit" })
            local s = B.make_scenario{}
            s:ApplyItemConditionLoss(suit, nil, 1.0)
            expect(s.logic_state.story.items_were_lost).toBe(true)
        end)
    end)

    describe("given a non-degradable item that is not gear", function()
        it("leaves it untouched", function()
            H.fakes.set_ltx("bread", { degradable = false })
            local bread = H.world.give("actor", "bread", { condition = 1.0 })
            B.make_scenario{}:ApplyItemConditionLoss(bread, nil, 1.0)
            expect(bread:condition()).toBeCloseTo(1.0)
        end)
    end)
end)

return true
