-- Reachability probe. Calls every non-UI mod function once and reports
-- OK / FAIL. Not a test suite -- it asserts nothing about correctness, only
-- that the harness can reach each function without an engine.
--
--   tools\luajit.exe probe.lua
--
-- Exit 0 when everything outside the two UI modules is reachable. That is the
-- definition of "harness complete"; specs are written against it separately.

package.path = "./?.lua;" .. package.path

local H = require("harness.init")
local B = H.builders
local world = H.world
local fakes = H.fakes

local pass, fail = 0, 0
local failures = {}

local function probe(label, fn)
    local ok, err = pcall(fn)
    if ok then
        pass = pass + 1
        print(string.format("  ok   %s", label))
    else
        fail = fail + 1
        local msg = tostring(err):gsub("^.-([%w_]+%.script:%d+)", "%1")
        print(string.format("  FAIL %s\n         %s", label, msg))
        failures[#failures + 1] = label .. "  --  " .. msg
    end
end

local function section(name) print("\n" .. name) end

-- --------------------------------------------------------------- fresh boot

local MODULES = { "soulslike_classes", "soulslike", "soulslike_mcm",
                  "soulslike_scenarios", "soulslike_scenario_logic_factory",
                  "soulslike_message_factory", "soulslike_note" }

local function fresh(opts)
    opts = opts or {}
    H.boot{
        load = MODULES,
        mods = opts.mods,
        actor = { rank = 5000, reputation = 100, money = 5000,
                  level_vertex_id = 111, game_vertex_id = 222 },
        soulslike_mode = true,
    }
    fakes.set_random_const(1)
    fakes.set_ltx("wpn_ak74", { kind = "w_rifle" })
    fakes.set_ltx("bread", { kind = "i_food" })
    fakes.set_ltx("letter", { kind = "letter" })
    fakes.set_ltx("S_INVBOX", { class = "S_INVBOX" })
    fakes.set_ltx("simulation_boar", { class = "SM_BOARW", kind = "SM_BOARW" })

    -- A recorded spawn point; without one the mod hits vector():set(nil,...),
    -- which the engine turns into a CTD. See the note at the end.
    local st = soulslike.get_soulslike_state()
    st.spawn_location = { level = "zaton", position = { x = 0, y = 0, z = 0 },
                          angle = { x = 0, y = 0, z = 0 },
                          level_vertex_id = 111, game_vertex_id = 222 }
    return st
end

-- ============================================================ soulslike.script

section("soulslike.script")
fresh()

probe("IsSoulslikeMode",            function() return IsSoulslikeMode() end)
probe("IsToolkit",                  function() return IsToolkit(nil, "itm_basickit") end)
probe("get_soulslike_state",        function() return soulslike.get_soulslike_state() end)
probe("debug / info / warn / error",function()
    soulslike.debug("x"); soulslike.info("x"); soulslike.warn("x"); soulslike.error("x")
    soulslike.debug({ a = 1, b = { c = 2 } })      -- exercises print_table
end)
probe("debug_tip",                  function() soulslike.debug_tip("hi") end)
probe("try",                        function() return soulslike.try(function() return 1 end) end)
probe("set_spawn",                  function() soulslike.set_spawn(false) end)
probe("set_spawn(show_message)",    function() soulslike.set_spawn(true) end)
probe("force_save",                 function() soulslike.force_save("test") end)
probe("find_closest_enemy",         function() return soulslike.find_closest_enemy() end)
probe("find_closest_enemy_mutant",  function() return soulslike.find_closest_enemy_mutant() end)
probe("find_closest_enemy_stalker", function() return soulslike.find_closest_enemy_stalker() end)
probe("find_closest_friendly_stalker", function() return soulslike.find_closest_friendly_stalker() end)
probe("dream_callback",             function() soulslike.dream_callback() end)

-- ------------------------------------------------------- callback handlers

section("soulslike.script -- registered callbacks")
fresh()
soulslike.on_game_start()

probe("actor_on_before_hit", function()
    local mon = world.spawn_npc("looter", { kind = "monster" })
    SendScriptCallback("actor_on_before_hit",
        { power = 0.5, type = hit.wound, impulse = 1, draftsman = mon }, 12, {})
end)
probe("actor_on_first_update",  function() SendScriptCallback("actor_on_first_update") end)
probe("on_level_changing",      function() SendScriptCallback("on_level_changing") end)
probe("save_state",             function() SendScriptCallback("save_state", {}) end)
probe("load_state",             function() SendScriptCallback("load_state", {}) end)
probe("on_game_load",           function() SendScriptCallback("on_game_load") end)
probe("actor_on_sleep",         function() SendScriptCallback("actor_on_sleep", 8) end)
probe("on_before_save_input",   function() SendScriptCallback("on_before_save_input", {}, 1, "n") end)
probe("on_console_execute",     function() SendScriptCallback("on_console_execute", "save", "my save") end)
probe("actor_on_stash_remove",  function() SendScriptCallback("actor_on_stash_remove", { stash_id = 1 }) end)

probe("actor_on_item_take_from_box", function()
    local box = world.container("box", { section = "inv_backpack" })
    SendScriptCallback("actor_on_item_take_from_box", box,
                       world.give("actor", "medkit"))
end)

probe("physic_object_on_use_callback", function()
    local box = world.container("hidden", { kind = "invbox" })
    SendScriptCallback("physic_object_on_use_callback", box, db.actor)
end)

probe("actor_on_before_death", function()
    local mon = world.spawn_npc("looter", { kind = "monster" })
    SendScriptCallback("actor_on_before_hit",
        { power = 99, type = hit.wound, impulse = 1, draftsman = mon }, 12, {})
    SendScriptCallback("actor_on_before_death", mon, {})
    H.tick()
end)

probe("wakeup_callback (after a death)", function() soulslike.wakeup_callback() end)

-- ================================================== scenario_logic_factory

section("soulslike_scenario_logic_factory.script")
fresh()

probe("create_by_id x4", function()
    for id = 1, 4 do
        assert(soulslike_scenario_logic_factory.create_by_id(id), "nil for id " .. id)
    end
end)
probe("compute_fatal_hit_info", function()
    local f = H.loader.upvalue(soulslike_scenario_logic_factory.create_new,
                               "compute_fatal_hit_info")
    return f({})
end)
probe("find_backpack", function()
    local f = H.loader.upvalue(soulslike_scenario_logic_factory.create_new,
                               "find_backpack")
    return f()
end)
probe("create_new (no hits)",  function()
    return soulslike_scenario_logic_factory.create_new({})
end)
probe("create_new (monster kill)", function()
    local mon = world.spawn_npc("m", { kind = "monster" })
    fakes.register_object(mon)
    return soulslike_scenario_logic_factory.create_new({
        { power = 50, is_fatal = true, time = 0, draftsman_id = mon:id() },
    })
end)

-- ======================================================= soulslike_scenarios

section("soulslike_scenarios.script -- base methods")
fresh{ mods = { "item_parts", "item_radio", "treasure_manager",
                "actor_status_thirst", "magazine_binder", "arszi_psy" } }

local function scenario()
    local s = DefaultSoulslikeScenarioLogic()
    s:SetLevelName("zaton"); s:SetLootScalar(1); s:SetIsInDoor(false)
    s:SetIsInWater(false)
    return s
end

probe("setters (9)", function()
    local s = scenario()
    local npc = world.spawn_npc("n", { kind = "stalker" })
    s:SetRescuer(npc); s:SetLooter(npc)
    s:SetLooterType(soulslike.entity_type.Stalker)
    s:SetKiller(npc); s:SetKillerType(soulslike.entity_type.Stalker)
    s:SetFatalHitType(hit.wound)
end)
probe("HealActor",            function() scenario():HealActor() end)
probe("ApplyRankLoss",        function() scenario():ApplyRankLoss() end)
probe("ApplyReputationLoss",  function() scenario():ApplyReputationLoss() end)
probe("ApplyMoneyLoss",       function() scenario():ApplyMoneyLoss() end)
probe("IsItemLossAllowed",    function()
    return scenario():IsItemLossAllowed(world.give("actor", "wpn_ak74", { kind = "weapon" }))
end)
probe("ApplyItemConditionLoss (weapon)", function()
    scenario():ApplyItemConditionLoss(
        world.give("actor", "wpn_ak74", { kind = "weapon" }), nil, 0.5)
end)
probe("ApplyItemConditionLoss (other)", function()
    scenario():ApplyItemConditionLoss(world.give("actor", "medkit"), nil, 0.5)
end)
probe("ApplyTransferItemsPreConditions", function()
    scenario():ApplyTransferItemsPreConditions()
end)
probe("TryStalkerLooter", function()
    local s = scenario()
    s.logic_state.allow_npc_looting = true
    return s:TryStalkerLooter(world.give("actor", "medkit"), nil,
                              world.spawn_npc("looter", { kind = "stalker" }))
end)
probe("TryMonsterLooter", function()
    local s = scenario()
    s.logic_state.allow_npc_looting = true
    fakes.set_ltx("meat", { kind = "i_mutant_raw" })
    return s:TryMonsterLooter(world.give("actor", "meat"), nil,
                              world.spawn_npc("mon", { kind = "monster" }))
end)
probe("TryTarkovLooter", function()
    local s = scenario()
    return s:TryTarkovLooter(world.give("actor", "medkit"),
                             world.container("st"),
                             world.spawn_npc("l2", { kind = "stalker" }))
end)
probe("TransferItem", function()
    local s = scenario()
    return s:TransferItem(world.give("actor", "medkit"), world.container("st2"), nil)
end)
probe("TransferItems", function()
    local s = scenario()
    world.give("actor", "medkit")
    local box = world.container("st3")
    s:TransferItems(box:id())
    H.tick()
end)
probe("CreateStash x4", function()
    for _, cls in ipairs({ "DefaultSoulslikeScenarioLogic",
                           "RFDetectorSoulslikeScenarioLogic",
                           "HiddenStashSoulslikeScenarioLogic",
                           "NoLossSoulslikeScenarioLogic" }) do
        local s = _G[cls]()
        s:SetLevelName("zaton"); s:SetLootScalar(1)
        s:CreateStash()
    end
end)
probe("ApplyTransferItemsPostConditions x4", function()
    for _, cls in ipairs({ "DefaultSoulslikeScenarioLogic",
                           "RFDetectorSoulslikeScenarioLogic",
                           "HiddenStashSoulslikeScenarioLogic",
                           "NoLossSoulslikeScenarioLogic" }) do
        local s = _G[cls]()
        s.logic_state.stash_id = world.container("pc_" .. cls):id()
        s:ApplyTransferItemsPostConditions()
    end
end)
probe("GiveFoodAndWater",  function() scenario():GiveFoodAndWater() end)
probe("GiveMeds/Weapon/Outfit/Mask", function()
    local s = scenario()
    s:GiveMeds(); s:GiveWeapon(); s:GiveOutfit(); s:GiveMask()
end)
probe("TrackAmbusher", function()
    scenario():TrackAmbusher(1, anim.look_around, move.standing, move.stand,
                             look.search, { x = 0, y = 0, z = 0 }, 1, 1)
end)
probe("SpawnAmbush (mutant)", function()
    local s = scenario()
    s.logic_state.killer_type = soulslike.entity_type.Monster
    s.logic_state.has_mutant_bait = true
    s.logic_state.mutant_ambush_chance = 1
    s.logic_state.death_location = { position = { x = 0, y = 0, z = 0 },
                                     level_vertex_id = 1, game_vertex_id = 1 }
    s:SpawnAmbush()
end)
probe("StopSurgeAndStorm",  function() scenario():StopSurgeAndStorm() end)
probe("AdvanceTime",        function() scenario():AdvanceTime() end)
probe("SendWakeupMessage",  function() scenario():SendWakeupMessage() end)
probe("RespawnActor",       function() scenario():RespawnActor(); H.tick() end)
probe("HandleItemsAndRespawn", function()
    world.give("actor", "medkit")
    scenario():HandleItemsAndRespawn()
    H.tick()
end)
probe("TransferAndRespawn", function()
    scenario():TransferAndRespawn(world.container("st4"):id()); H.tick()
end)
probe("OnDeath",    function() scenario():OnDeath(); H.tick() end)
probe("OnComplete", function() scenario():OnComplete() end)
probe("OnRespawn",  function() scenario():OnRespawn() end)
probe("destroy",    function() scenario():destroy() end)
probe("ignore_list (file-local)", function()
    local f = H.loader.upvalue(soulslike_scenarios.SoulslikeScenarioLogic
                               and nil or _G.NoLossSoulslikeScenarioLogic.IsItemLossAllowed,
                               "ignore_list")
    return f and f("bolt")
end)
probe("NoLoss overrides", function()
    local s = NoLossSoulslikeScenarioLogic()
    s:TransferItems(nil)
    return s:IsItemLossAllowed(world.give("actor", "medkit"))
end)

-- ==================================================== message factory + note

section("soulslike_message_factory.script / soulslike_note.script")
fresh()

probe("create (rescuer)",    function()
    return soulslike_message_factory.create(true, { gave_food_or_water = true })
end)
probe("create (no rescuer)", function()
    return soulslike_message_factory.create(nil, {})
end)
probe("menu_read", function()
    local note = world.give("actor", "letter")
    note._parent = db.actor:id()
    return soulslike_note.menu_read(note)
end)
probe("func_radio_freq", function()
    local note = world.give("actor", "letter")
    local st = soulslike.get_soulslike_state()
    st.note_message_data[note:id()] = { freq = "121.5", level_name = "zaton" }
    return soulslike_note.func_radio_freq(note)
end)

-- ============================================================= soulslike_mcm

section("soulslike_mcm.script")
fresh()

probe("on_mcm_load", function() return soulslike_mcm.on_mcm_load() end)
probe("every getter", function()
    local n = 0
    for name, fn in pairs(soulslike_mcm) do
        if type(fn) == "function" and name ~= "on_mcm_load" then
            fn("ignore_bolt")     -- the one getter taking an argument
            n = n + 1
        end
    end
    assert(n > 50, "expected 50+ getters, saw " .. n)
end)

-- ==================================================================== report

print("")
print(string.rep("-", 66))
print(string.format("%d reachable, %d unreachable", pass, fail))
if fail > 0 then
    print("")
    for i, f in ipairs(failures) do print(string.format("  %d) %s", i, f)) end
end
os.exit(fail == 0 and 0 or 1)
