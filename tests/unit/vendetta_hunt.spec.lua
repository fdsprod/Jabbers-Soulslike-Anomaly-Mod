-- soulslike_vendetta: the grudge, the hunt, and when the hunt ends.
--
-- A squad that loses a member to the player and then kills the player starts
-- hunting: soulslike_vendetta sets scripted_target/rush_to_target on the squad
-- server object, the same pair sim_squad_bounty uses for bounty hunters
-- (sim_squad_bounty.script:71-72).
--
-- The window is measured in GAME hours, and the respawn moves the game clock:
-- RespawnActor advances to daylight when nighttime respawns are disabled
-- (soulslike_scenarios.script:906-920). That interaction is the point of the
-- last block here.

local H = require("harness.init")
local B = H.builders
local fakes = H.fakes

describe("vendetta squads", function()

    local squad, killer, actor

    -- Squads reach squad_on_npc_death as SERVER objects, where id is a field
    -- and not a method (axr_main.script:152 documents all three params as
    -- server objects).
    local function make_squad(name, faction, members)
        local sq = H.world.spawn_npc(name)
        sq.id = sq:id()
        sq.player_id = faction
        sq._members = members
        sq.name = function(self) return name end
        sq.section_name = function(self) return faction .. "_sim_squad_advanced" end
        sq.npc_count = function(self) return self._members end
        sq.set_squad_relation = function(self, rel) self._relation = rel end
        return sq
    end

    local function make_member(name, squad_obj)
        local npc = H.world.spawn_npc(name)
        H.world.server(npc:id()).group_id = squad_obj.id
        return npc
    end

    beforeEach(function()
        H.boot{
            load = {
                "soulslike_classes", "soulslike", "soulslike_mcm",
                "soulslike_message_factory", "soulslike_scenarios",
                "soulslike_scenario_logic_factory", "soulslike_vendetta",
            },
            soulslike_mode = true,
        }
        H.set_spawn{ level = "zaton" }
        H.set_actor{ position = { x = 0, y = 0, z = 0 } }

        fakes.set_mcm("scenarios/enable_vendetta_squads", true)
        fakes.set_mcm("scenarios/vendetta_hunt_hours", 12)
        fakes.set_mcm("scenarios/max_vendetta_squads", 2)

        soulslike_vendetta.on_game_start()

        squad = make_squad("bandit_squad", "bandit", 3)
        killer = make_member("bandit_killer", squad)
        actor = { id = 0 }
    end)

    --- The player kills one of theirs, then they kill the player.
    local function earn_a_grudge_and_die()
        soulslike_vendetta.record_squad_member_kill(squad, { id = 990 }, actor)
        return soulslike_vendetta.record_actor_death(killer)
    end

    describe("given the squad owes the player nothing", function()
        it("does not start a hunt", function()
            expect(soulslike_vendetta.record_actor_death(killer)).toBe(false)
        end)

        it("leaves the death-site ambush alone", function()
            soulslike_vendetta.record_actor_death(killer)
            expect(soulslike_vendetta.consume_pending_hunt()).toBe(false)
        end)
    end)

    describe("given the player killed one of theirs first", function()
        it("starts a hunt when they kill the player", function()
            expect(earn_a_grudge_and_die()).toBe(true)
        end)

        it("replaces the death-site ambush", function()
            earn_a_grudge_and_die()
            expect(soulslike_vendetta.consume_pending_hunt()).toBe(true)
        end)

        it("only replaces it once", function()
            earn_a_grudge_and_die()
            soulslike_vendetta.consume_pending_hunt()
            expect(soulslike_vendetta.consume_pending_hunt()).toBe(false)
        end)

        it("routes the squad at the actor", function()
            earn_a_grudge_and_die()
            soulslike_vendetta.tick()
            expect(squad.scripted_target).toBe("actor")
            expect(squad.rush_to_target).toBe(true)
        end)

        -- Without this a neutral squad crosses the whole map and then stands
        -- there, because nothing ever made it hostile.
        it("makes the squad hostile", function()
            earn_a_grudge_and_die()
            soulslike_vendetta.tick()
            expect(squad._relation).toBe("enemy")
        end)
    end)

    describe("the hunt window", function()
        beforeEach(function()
            earn_a_grudge_and_die()
            soulslike_vendetta.tick()
        end)

        it("is still running before the window is up", function()
            fakes.advance_game_seconds(11 * 3600)
            soulslike_vendetta.tick()
            expect(soulslike_vendetta.is_hunting(squad.id)).toBe(true)
        end)

        it("ends once the window is up", function()
            fakes.advance_game_seconds(13 * 3600)
            soulslike_vendetta.tick()
            expect(soulslike_vendetta.is_hunting(squad.id)).toBe(false)
        end)

        it("lets the squad go when it ends", function()
            fakes.advance_game_seconds(13 * 3600)
            soulslike_vendetta.tick()
            expect(squad.scripted_target).toBeNil()
        end)
    end)

    -- The reason the window is stamped at respawn and not at death.
    --
    -- RespawnActor pushes the clock to daylight when nighttime respawns are
    -- disabled (soulslike_scenarios.script:906-920). Dying at 21:00 advances
    -- 10 to 12 hours. Stamped at death, a 12 game hour window is spent before
    -- the player is back on their feet, and the squad that earned the grudge
    -- never hunts at all.
    describe("given the respawn pushes the clock to daylight", function()
        local function die_at_night_and_respawn()
            fakes.set_mcm("character/allow_nighttime_respawn", false)
            fakes.set_game_time(21, 0)
            fakes.set_random_const(0)

            earn_a_grudge_and_die()
            B.stub_finders{}

            -- The real order: RespawnActor moves the clock, OnComplete runs
            -- once the player is up. begin_hunt_window is wired into
            -- OnComplete, so calling both is what proves the wiring rather
            -- than just the function.
            local scenario = B.make_scenario{}
            scenario:RespawnActor()
            scenario:OnComplete()

            soulslike_vendetta.tick()
        end

        it("advances the clock past the window", function()
            die_at_night_and_respawn()
            -- 21:00 + 10h lands at 07:00, so the whole 12h window would be gone
            -- if the stamp were taken at death.
            expect(H.fakes.call_count("level.change_game_time")).toBe(1)
            expect(level.get_time_hours()).toBe(7)
        end)

        it("still leaves the squad hunting", function()
            die_at_night_and_respawn()
            expect(soulslike_vendetta.is_hunting(squad.id)).toBe(true)
        end)

        it("gives the squad the full window from when the player wakes up", function()
            die_at_night_and_respawn()
            fakes.advance_game_seconds(11 * 3600)
            soulslike_vendetta.tick()
            expect(soulslike_vendetta.is_hunting(squad.id)).toBe(true)
        end)
    end)
end)
