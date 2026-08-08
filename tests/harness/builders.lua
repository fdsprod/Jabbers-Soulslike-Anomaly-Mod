-- Fixture builders for the userdata-ish objects the mod receives from the
-- engine. Everything is a plain table with method-style accessors, because
-- the mod calls them as obj:id(), obj:section(), etc.
--
-- The `_kind` tag drives the IsStalker / IsMonster / ... predicates in fakes.lua.

local M = {}

local next_id = 1000
local function alloc_id()
    next_id = next_id + 1
    return next_id
end

-- Shared: gives an object the id()/name()/section() accessors the mod expects.
local function base(o, kind)
    o = o or {}
    o._kind = kind
    o._id = o._id or alloc_id()
    o._name = o._name or (kind .. "_" .. tostring(o._id))
    o._section = o._section or (kind .. "_section")

    function o:id() return self._id end
    function o:name() return self._name end
    function o:section() return self._section end
    return o
end

--- An NPC (stalker or monster). Opts:
---   id, name, section, kind ("stalker" | "monster"), community,
---   goodwill (general_goodwill vs actor), alive, position {x,y,z}
function M.make_npc(opts)
    opts = opts or {}
    local o = base({
        _id      = opts.id,
        _name    = opts.name,
        _section = opts.section,
    }, opts.kind or "stalker")

    o._community = opts.community or "stalker"
    o._goodwill  = opts.goodwill == nil and 0 or opts.goodwill
    o._alive     = opts.alive ~= false
    o._position  = M.make_vector(opts.position)

    function o:community() return self._community end
    function o:character_community() return self._community end
    function o:general_goodwill() return self._goodwill end
    function o:alive() return self._alive end
    function o:position() return self._position end
    function o:character_rank() return opts.rank or 0 end
    function o:character_name() return self._name end
    function o:clsid() return opts.clsid or 1 end
    function o:section_name() return self._section end
    function o:level_vertex_id() return opts.level_vertex_id or 1 end
    function o:game_vertex_id() return opts.game_vertex_id or 1 end

    -- Server-object style fields, for objects reached via alife():object().
    o.m_level_vertex_id = opts.level_vertex_id or 1
    o.m_game_vertex_id  = opts.game_vertex_id or 1
    o.online            = opts.online == true
    o.parent_id         = opts.parent_id
    o.section           = o._section
    function o:switch_online() self.online = true end

    -- State setters npc_on_net_spawn drives (soulslike.script:929-934).
    -- Recorded rather than modelled: specs assert which constant was applied.
    o.applied = {}
    local function setter(field)
        return function(self, v) self.applied[field] = v end
    end
    o.set_mental_state     = setter("mental_state")
    o.set_body_state       = setter("body_state")
    o.set_movement_type    = setter("movement_type")
    o.set_desired_position = setter("desired_position")
    function o:set_sight(t) self.applied.sight_type = t end
    function o:set_desired_direction() self.applied.desired_direction = true end

    -- Squad support for SpawnAmbush's is_squad branch.
    o._squad_members = opts.squad_members or {}
    function o:squad_members()
        local i = 0
        return function()
            i = i + 1
            return self._squad_members[i]
        end
    end
    function o:create_npc() end

    return o
end

function M.make_stalker(opts)
    opts = opts or {}; opts.kind = "stalker"
    return M.make_npc(opts)
end

function M.make_monster(opts)
    opts = opts or {}; opts.kind = "monster"
    return M.make_npc(opts)
end

function M.make_anomaly(opts)
    opts = opts or {}; opts.kind = "anomaly"
    return M.make_npc(opts)
end

--- The actor. Opts: id (defaults to AC_ID), health, power, rank, community,
--- position, inventory (list of items for iterate_inventory).
function M.make_actor(opts)
    opts = opts or {}
    local o = base({
        _id      = opts.id or (_G.AC_ID or 0),
        _name    = opts.name or "actor",
        _section = "actor",
    }, "actor")

    -- Plain fields the mod writes directly (HealActor, dream_callback).
    o.health    = opts.health == nil and 1.0 or opts.health
    o.power     = opts.power  == nil and 1.0 or opts.power
    o.radiation = opts.radiation or 0
    o.bleeding  = opts.bleeding or 0
    o.psy_health= opts.psy_health == nil and 1.0 or opts.psy_health
    o.satiety   = opts.satiety == nil and 1.0 or opts.satiety

    o._rank      = opts.rank or 0
    o._rep       = opts.reputation or 0
    o._money     = opts.money or 0
    o._community = opts.community or "stalker"
    o._position  = M.make_vector(opts.position)
    o._inventory = opts.inventory or {}
    o._slots     = opts.slots or {}

    function o:character_rank() return self._rank end
    function o:set_character_rank(v) self._rank = v end
    function o:character_reputation() return self._rep end
    function o:set_character_reputation(v) self._rep = v end
    function o:character_community() return self._community end
    function o:character_name() return opts.character_name or "Marked One" end
    function o:position() return self._position end
    function o:alive() return true end
    function o:general_goodwill() return 0 end
    function o:set_health_ex(v) self.health = v end
    function o:level_vertex_id() return opts.level_vertex_id or 1 end
    function o:game_vertex_id() return opts.game_vertex_id or 1 end
    function o:money() return self._money end
    function o:give_money(v) self._money = self._money + v end
    function o:give_info_portion(id) if _G.give_info_portion then _G.give_info_portion(id) end end

    -- Only the accessors GiveFoodAndWater reads (soulslike_scenarios.script:576).
    o._conditions = {
        GetSatiety      = function() return o.satiety end,
        SatietyCritical = function() return opts.satiety_critical or 0.2 end,
    }
    function o:cast_Actor()
        return { conditions = function() return o._conditions end }
    end

    -- Overridden by world.lua when the item model is active. The default here
    -- keeps actor-only specs working without booting the world.
    function o:iterate_inventory(fn)
        for _, item in ipairs(self._inventory) do
            if fn(self, item) then return end
        end
    end

    function o:item_in_slot(n) return self._slots[n] end
    function o:transfer_item(_, _) end
    function o:give_game_news(...) end

    return o
end

--- An inventory item. Opts: id, section, kind (drives Is* predicates),
--- condition.
function M.make_item(opts)
    opts = opts or {}
    local o = base({
        _id      = opts.id,
        _name    = opts.name,
        _section = opts.section or "itm_generic",
    }, opts.kind or "item")

    o._condition = opts.condition == nil and 1.0 or opts.condition
    function o:condition() return self._condition end
    return o
end

-- The engine binds set(float,float,float) only
-- (xray-monolith/src/xrServerEntities/script_fvector_script.cpp:24). Passing
-- nil matches no overload, so luabind raises lua_cast_failed, which under
-- !XRAY_EXCEPTIONS becomes Debug.fatal -- a hard CTD, not a catchable error.
--
-- We raise to match. Coercing nil to 0 would silently paper over two mod sites
-- that can pass nil coordinates (soulslike_scenario_logic_factory.script:174
-- and soulslike_scenarios.script:845, both when no spawn was ever recorded).
-- Set this false only in a spec that deliberately needs to step past it.
M.strict_vectors = true

--- A vector with the distance methods the mod uses.
function M.make_vector(v)
    v = v or {}
    local o = { x = v.x or 0, y = v.y or 0, z = v.z or 0 }

    function o:set(x, y, z)
        if M.strict_vectors and (x == nil or y == nil or z == nil) then
            error("vector:set() got nil (" .. tostring(x) .. ", " .. tostring(y)
                  .. ", " .. tostring(z) .. ") -- the engine binds "
                  .. "set(float,float,float) and would hard-crash here", 2)
        end
        self.x, self.y, self.z = x, y, z
        return self
    end

    function o:distance_to_sqr(other)
        local dx, dy, dz = self.x - other.x, self.y - other.y, self.z - other.z
        return dx * dx + dy * dy + dz * dz
    end

    function o:distance_to(other)
        return math.sqrt(self:distance_to_sqr(other))
    end

    return o
end

--- A hit record, shaped as soulslike.actor_on_before_hit enqueues them
--- (soulslike.script:907-913).
function M.make_hit(opts)
    opts = opts or {}
    return {
        type         = opts.type or (_G.hit and _G.hit.wound) or 5,
        power        = opts.power or 0,
        is_fatal     = opts.is_fatal or false,
        time         = opts.time or 0,
        draftsman_id = opts.draftsman_id,
    }
end

--- Installs the `vector()` global used across the mod.
function M.install(env)
    env = env or _G
    env.vector = function() return M.make_vector() end
    return env
end

function M.reset() next_id = 1000 end

return M
