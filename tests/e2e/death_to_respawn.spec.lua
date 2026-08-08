-- End to end: the player takes hits, dies, and wakes up somewhere else.
--
--   actor_on_before_hit xN
--     -> actor_on_before_death
--          -> create_new              (scenario selection)
--          -> OnDeath                 (heal, rank/rep loss)
--          -> HandleItemsAndRespawn   (record death location, CreateStash)
--          -> CreateTimeEvent         <-- the flow suspends here
--   H.tick()
--          -> TransferItems           (per-item loss decisions)
--          -> ApplyMoneyLoss
--          -> RespawnActor            -> CreateTimeEvent -> ChangeLevel
--
-- The suspension is the reason this needs a tick pump: HandleItemsAndRespawn
-- returns long before anything has moved, so asserting immediately after the
-- death callback would only ever see an empty stash.
--
-- House style here: run the journey once in beforeEach, then one `it` per
-- observable, rather than replaying a forty-step flow for every assertion.

local H = require("harness.init")
local B = H.builders

local MOD_SCRIPTS = {
    "soulslike_classes", "soulslike", "soulslike_mcm",
    "soulslike_message_factory", "soulslike_scenarios",
    "soulslike_scenario_logic_factory",
}

--- Boot a world where the player is far from spawn, so selection lands on a
--- real loss scenario rather than the close-range no-loss arm.
local function boot(opts)
    opts = opts or {}
    H.boot{ load = MOD_SCRIPTS, soulslike_mode = true }
    H.fakes.set_random_min()
    H.set_spawn{ level = "zaton", position = { x = 0, y = 0, z = 0 } }
    H.set_actor{
        position = { x = 0, y = 0, z = 500 },
        rank = 5000, reputation = 400, money = 10000,
    }
    B.stub_finders{ friendly_stalker = B.make_stalker{ name = "medic" } }

    H.fakes.set_ltx("itm_actor_backpack", { kind = "i_backpack" })
    -- Force the Default scenario so a stash is actually created; the weighted
    -- pick is covered on its own in unit/create_new.spec.lua.
    H.fakes.set_mcm("debug/is_enabled", true)
    H.fakes.set_mcm("debug/debug_the_default_scenario", true)

    soulslike.on_game_start()
    return opts
end

local function live_scenario()
    return H.loader.upvalue(soulslike.wakeup_callback, "scenario_logic")
end

-- TransferItem spends two different KINDS of roll per item and they want
-- opposite values, so a single constant cannot drive either outcome:
--
--   math.random()        -- the keep roll in IsItemLossAllowed (:966-981);
--                           LOW keeps the item
--   math.random(0, 100)  -- the loss roll in TransferItem (:1196);
--                           LOW loses the item
--
-- Hence a predicate on the call form rather than set_random_const.
local function lose_everything()
    H.fakes.set_random(function(a, b)
        if a == nil then return 0.999 end   -- fail every keep roll
        return a                            -- pass every loss roll
    end)
end

local function lose_nothing()
    H.fakes.set_random(function(a, b)
        if a == nil then return 0.0 end     -- win every keep roll
        return b or 1                       -- fail every loss roll
    end)
end

--- Take a hit, as actor_on_before_hit records it.
local function take_hit(opts)
    opts = opts or {}
    SendScriptCallback("actor_on_before_hit",
        { power = opts.power or 10, type = opts.type or hit.wound }, opts.bone or 1,
        { ret_value = true })
end

--- Die. Returns the flags table the handler wrote into.
local function die()
    local flags = { ret_value = true }
    SendScriptCallback("actor_on_before_death", nil, flags)
    return flags
end

describe("e2e: death to respawn", function()

    describe("given the player dies carrying loot", function()
        local flags, stash_id

        beforeEach(function()
            boot()
            H.world.give("actor", "wpn_ak74", { kind = "weapon" })
            H.world.give("actor", "medkit")
            H.world.give("actor", "bread")

            -- All loss rolls succeed, so every eligible item is destroyed and
            -- the ignore-list survivors stand out.
            lose_everything()
            H.fakes.set_mcm("items/item_loss_scalar", 1.0)
            H.fakes.set_mcm("items/ignore_rank_when_computing_item_loss_chance", true)

            take_hit{ power = 50 }
            flags = die()
            stash_id = live_scenario().logic_state.stash_id
            H.tick()
        end)

        it("suppresses the engine's own death handling", function()
            expect(flags.ret_value).toBe(false)
        end)

        it("creates exactly one stash", function()
            expect(H.world.created).toHaveLength(1)
            expect(H.world.created[1].section).toBe("inv_backpack")
        end)

        it("registers the stash in the save", function()
            local stash = soulslike.get_soulslike_state().created_stashes[stash_id]
            expect(stash).toBeDefined()
            expect(stash.lost_items).toBeDefined()
            expect(stash.examine).toBe(false)
        end)

        it("records where the player died", function()
            local loc = live_scenario().logic_state.death_location
            expect(loc.position.z).toBe(500)
            expect(loc.level_vertex_id).toBeDefined()
        end)

        it("leaves ignore-listed items on the actor", function()
            expect(H.world.contents("actor")).toContain("medkit")
        end)

        it("destroys the items the loss rolls claimed", function()
            expect(H.world.destroyed()).toContain("wpn_ak74")
        end)

        it("marks the story as having lost items", function()
            expect(live_scenario().logic_state.story.items_were_lost).toBe(true)
        end)

        it("deducts rank", function()
            expect(db.actor:character_rank()).toBeLessThan(5000)
        end)

        it("deducts reputation", function()
            expect(db.actor:character_reputation()).toBeLessThan(400)
        end)

        it("heals the actor", function()
            expect(db.actor.health).toBeGreaterThan(0)
        end)

        it("grants temporary invulnerability", function()
            expect(bind_stalker_ext.invulnerable_time).toBeGreaterThan(0)
        end)

        it("counts the death", function()
            expect(H.fakes.call_count("increment_statistic")).toBe(1)
        end)

        it("changes level exactly once", function()
            expect(H.fakes.call_count("ChangeLevel")).toBe(1)
        end)

        it("fades the screen out before the transition", function()
            expect(H.fakes.call_count("level.add_pp_effector")).toBeGreaterThan(0)
        end)

        it("leaves no time events pending", function()
            expect(H.timeevents.pending()).toBe(0)
        end)
    end)

    describe("given items survive the loss rolls", function()
        local stash_id

        beforeEach(function()
            boot()
            H.world.give("actor", "wpn_ak74", { kind = "weapon" })
            H.world.give("actor", "bread")

            -- Every loss roll fails, so nothing is destroyed and everything
            -- transferable ends up in the stash.
            lose_nothing()
            die()
            stash_id = live_scenario().logic_state.stash_id
            H.tick()
        end)

        it("moves them into the stash", function()
            local stash = H.world.object(stash_id)
            expect(H.world.where(H.world.item_by_section("bread")))
                .toBe(H.world.where(H.world.item_by_section("wpn_ak74")))
            expect(stash).toBeDefined()
        end)

        it("destroys nothing", function()
            expect(H.world.destroyed()).toEqual({})
        end)

        it("empties the actor's inventory", function()
            expect(H.world.contents("actor")).toEqual({})
        end)

        it("marks the stash on the map", function()
            expect(H.fakes.call_count("level.map_add_object_spot_ser")).toBe(1)
        end)

        it("records the pda marker in the story", function()
            expect(live_scenario().logic_state.story.has_pda_marker).toBe(true)
        end)
    end)

    describe("given the stash is not online yet when the timer fires", function()
        -- wait_for_stash_creation returns false until level.object_by_id can
        -- resolve the stash, and CreateTimeEvent re-queues on anything that is
        -- not literally `true` (_g.script:375). This is the retry contract.
        local stash_id

        beforeEach(function()
            boot()
            H.world.give("actor", "bread")
            lose_nothing()
            die()
            stash_id = live_scenario().logic_state.stash_id
            H.world.hide(stash_id)
        end)

        -- A bounded pump runs exactly one frame and leaves the retry in place,
        -- which is the only way to observe the mid-wait state.
        it("does not transfer anything on the first tick", function()
            H.tick{ passes = 1 }
            expect(H.world.contents("actor")).toContain("bread")
        end)

        it("keeps the event queued", function()
            H.tick{ passes = 1 }
            expect(H.timeevents.pending()).toBeGreaterThan(0)
        end)

        it("does not change level yet", function()
            H.tick{ passes = 1 }
            expect(H.fakes.call_count("ChangeLevel")).toBe(0)
        end)

        it("completes once the stash comes online", function()
            H.tick{ passes = 1 }
            H.world.reveal(stash_id)
            H.tick()
            expect(H.world.contents("actor")).toEqual({})
            expect(H.fakes.call_count("ChangeLevel")).toBe(1)
        end)
    end)

    describe("given hardcore lose-all-items is enabled", function()
        beforeEach(function()
            boot()
            H.fakes.set_mcm("hardcore/lose_all_items_on_death", true)
            H.world.give("actor", "wpn_ak74", { kind = "weapon" })
            H.world.give("actor", "bread")
            lose_nothing()
            die()
            H.tick()
        end)

        it("creates no stash at all", function()
            expect(H.world.created).toEqual({})
        end)

        it("destroys everything", function()
            expect(H.world.contents("actor")).toEqual({})
        end)

        it("still respawns the player", function()
            expect(H.fakes.call_count("ChangeLevel")).toBe(1)
        end)
    end)

    describe("given the player was in an arena fight", function()
        it("ignores the death entirely", function()
            boot()
            give_info_portion("bar_arena_fight")
            local flags = die()
            expect(flags.ret_value).toBe(true)
            expect(live_scenario()).toBeNil()
        end)
    end)

    describe("given soulslike mode is off", function()
        it("ignores the death entirely", function()
            H.boot{ load = MOD_SCRIPTS }
            H.fakes.set_random_min()
            soulslike.on_game_start()
            local flags = die()
            expect(flags.ret_value).toBe(true)
        end)
    end)

    -- FIXES: D5. RespawnActor built its destination vector straight from
    -- spawn_location with no nil-guard, unlike the identical call in
    -- SpawnAmbush (:770). A save with no recorded spawn made the respawn an
    -- access violation rather than a recoverable error.
    describe("given no spawn point was ever recorded", function()
        beforeEach(function()
            boot()
            soulslike.get_soulslike_state().spawn_location = {
                level = nil,
                position = { x = nil, y = nil, z = nil },
                angle = { x = nil, y = nil, z = nil },
                level_vertex_id = nil,
                game_vertex_id = nil,
            }
            H.world.give("actor", "bread")
            lose_nothing()
        end)

        it("does not raise on death", function()
            expect(function() die() end).never.toThrow()
        end)

        it("does not raise while the transfer completes", function()
            die()
            expect(function() H.tick() end).never.toThrow()
        end)

        it("does not attempt the level change", function()
            die()
            H.tick()
            expect(H.fakes.call_count("ChangeLevel")).toBe(0)
        end)

        -- The items still need to reach the stash: failing to respawn must not
        -- also cost the player their gear.
        it("still transfers the items to the stash", function()
            die()
            H.tick()
            expect(H.world.contents("actor")).toEqual({})
        end)
    end)

    describe("the hit queue", function()
        it("feeds the recorded hits into scenario selection", function()
            boot()
            local killer = B.make_monster{ name = "boar" }
            H.fakes.register_object(killer)

            SendScriptCallback("actor_on_before_hit",
                { power = 90, type = hit.wound, draftsman = killer }, 1,
                { ret_value = true })
            die()

            expect(live_scenario().logic_state.killer_type)
                .toBe(soulslike.entity_type.Monster)
        end)

        it("is cleared after the death is handled", function()
            boot()
            take_hit{ power = 50 }

            -- hit_queue is a file-local of the handlers, which are themselves
            -- upvalues of on_game_start -- hence the two-level reach.
            local on_hit = H.loader.upvalue(soulslike.on_game_start, "actor_on_before_hit")
            local queue = H.loader.upvalue(on_hit, "hit_queue")
            expect(#queue:Values()).toBeGreaterThan(0)

            die()
            expect(queue:Values()).toEqual({})
        end)
    end)
end)

return true
