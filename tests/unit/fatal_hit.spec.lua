-- compute_fatal_hit_info (soulslike_scenario_logic_factory.script:8).
--
-- The densest logic in the mod: it decides WHO killed you, which drives the
-- whole scenario choice. File-local and never exported, so it is reached
-- through the upvalues of create_new rather than by editing the mod.
--
-- Algorithm, for reference:
--   fatal_hit = first hit in ipairs order with is_fatal
--   time_span = max_time - min_time  (or 1 when all hits share a timestamp)
--   weight    = single_hit and 1 or (hit.time - min_time) / time_span, clamped
--   bucket[type].power += hit.power * weight * (hit.is_fatal and 2 or 1)
--   result    = the bucket with the highest power

local H = require("harness.init")
local fakes = H.fakes
local B = H.builders

describe("compute_fatal_hit_info()", function()

    local compute, ET

    beforeEach(function()
        H.boot{ load = { "soulslike_classes", "soulslike",
                         "soulslike_scenario_logic_factory" } }

        -- Extracted from the test environment, not from inside a module:
        -- soulslike.script defines `function debug(output)`, which shadows the
        -- stdlib debug table within that module's scope.
        compute = H.loader.upvalue(
            soulslike_scenario_logic_factory.create_new, "compute_fatal_hit_info")
        assert(compute, "could not reach compute_fatal_hit_info via upvalue")

        ET = soulslike.entity_type
        fakes.set_time(10000)
    end)

    -- Registers an object with level.object_by_id and returns its id.
    local function place(obj)
        fakes.register_object(obj)
        return obj:id()
    end

    describe("given no hits", function()
        it("does not raise", function()
            -- max_time stays -math.huge and falls back to time_global().
            expect(function() compute({}) end).never.toThrow()
        end)

        it("returns nil", function()
            expect(compute({})).toBeNil()
        end)
    end)

    describe("draftsman classification", function()

        describe("given a hit with no draftsman_id", function()
            it("attributes it to Other", function()
                local r = compute({ B.make_hit{ power = 50, is_fatal = true, time = 100 } })
                expect(r.draftsman_type).toBe(ET.Other)
            end)
        end)

        describe("given a draftsman_id that no longer resolves", function()
            it("falls back to Other", function()
                -- level.object_by_id returns nil for a despawned object.
                local r = compute({ B.make_hit{ power = 50, is_fatal = true,
                                                time = 100, draftsman_id = 999999 } })
                expect(r.draftsman_type).toBe(ET.Other)
            end)
        end)

        describe("given a stalker draftsman", function()
            it("classifies as Stalker", function()
                local id = place(B.make_stalker{})
                local r = compute({ B.make_hit{ power = 10, is_fatal = true,
                                                time = 0, draftsman_id = id } })
                expect(r.draftsman_type).toBe(ET.Stalker)
            end)
        end)

        describe("given a monster draftsman", function()
            it("classifies as Monster", function()
                local id = place(B.make_monster{})
                local r = compute({ B.make_hit{ power = 10, is_fatal = true,
                                                time = 0, draftsman_id = id } })
                expect(r.draftsman_type).toBe(ET.Monster)
            end)
        end)

        describe("given an anomaly draftsman", function()
            it("classifies as Anomaly", function()
                local id = place(B.make_anomaly{})
                local r = compute({ B.make_hit{ power = 10, is_fatal = true,
                                                time = 0, draftsman_id = id } })
                expect(r.draftsman_type).toBe(ET.Anomaly)
            end)
        end)

        describe("given the actor as draftsman", function()
            it("classifies as Self", function()
                -- Checked by id against AC_ID before any Is* predicate, so
                -- self-inflicted damage wins over other classifications.
                local actor = B.make_actor{}
                place(actor)
                local r = compute({ B.make_hit{ power = 10, is_fatal = true,
                                                time = 0, draftsman_id = actor:id() } })
                expect(r.draftsman_type).toBe(ET.Self)
            end)
        end)
    end)

    describe("power weighting", function()

        describe("given a single hit", function()
            it("gives it full weight", function()
                -- raw_span == 0 -> single_hit -> weight forced to 1. Without
                -- that guard the sole hit would weigh 0 and attribute nothing.
                local id = place(B.make_monster{})
                local r = compute({ B.make_hit{ power = 40, is_fatal = true,
                                                time = 500, draftsman_id = id } })
                expect(r.power).toBeCloseTo(80)   -- 40 * weight 1 * fatal 2x
            end)
        end)

        describe("given several hits sharing one timestamp", function()
            it("gives them all full weight", function()
                local id = place(B.make_monster{})
                local r = compute({
                    B.make_hit{ power = 10, time = 500, draftsman_id = id },
                    B.make_hit{ power = 20, time = 500, draftsman_id = id },
                })
                expect(r.power).toBeCloseTo(30)
            end)
        end)

        describe("given a fatal hit", function()
            it("doubles its contribution", function()
                local id = place(B.make_monster{})
                local plain = compute({ B.make_hit{ power = 25, time = 0, draftsman_id = id } })
                local fatal = compute({ B.make_hit{ power = 25, time = 0,
                                                    is_fatal = true, draftsman_id = id } })
                expect(fatal.power).toBeCloseTo(plain.power * 2)
            end)
        end)

        describe("given hits spread over time", function()
            it("weights later hits more heavily", function()
                local mon = place(B.make_monster{})
                local r = compute({
                    B.make_hit{ power = 100, time = 0,    draftsman_id = mon },
                    B.make_hit{ power = 100, time = 500,  draftsman_id = mon },
                    B.make_hit{ power = 100, time = 1000, draftsman_id = mon },
                })
                expect(r.power).toBeCloseTo(150)   -- weights 0, 0.5, 1
            end)

            it("CHARACTERIZATION: gives the earliest hit zero weight", function()
                -- weight = (time - min_time)/time_span, so the oldest hit
                -- always weighs 0 and adds nothing at all. A big opening shot
                -- followed by a light finisher attributes the kill to the
                -- finisher.
                --
                -- A real behavioral edge, not obviously intended. Pinned so a
                -- deliberate change is visible; if the weighting is ever
                -- revised (e.g. to a floor above 0), update this, don't delete
                -- it.
                local stalker = place(B.make_stalker{})
                local monster = place(B.make_monster{})

                local r = compute({
                    B.make_hit{ power = 1000, time = 0,    draftsman_id = stalker },
                    B.make_hit{ power = 1,    time = 1000, draftsman_id = monster,
                                is_fatal = true },
                })

                expect(r.draftsman_type).toBe(ET.Monster)
                expect(r.power).toBeCloseTo(2)   -- 1 * weight 1 * fatal 2x
            end)
        end)
    end)

    describe("aggregation", function()

        describe("given two different objects of the same type", function()
            it("sums them into one bucket", function()
                local a = place(B.make_stalker{ name = "a" })
                local b = place(B.make_stalker{ name = "b" })
                local r = compute({
                    B.make_hit{ power = 30, time = 100, draftsman_id = a },
                    B.make_hit{ power = 30, time = 100, draftsman_id = b },
                })
                expect(r.draftsman_type).toBe(ET.Stalker)
                expect(r.power).toBeCloseTo(60)
            end)
        end)

        describe("given competing buckets", function()
            it("returns the highest-power one", function()
                local stalker = place(B.make_stalker{})
                local monster = place(B.make_monster{})
                local r = compute({
                    B.make_hit{ power = 10, time = 100, draftsman_id = stalker },
                    B.make_hit{ power = 90, time = 100, draftsman_id = monster },
                })
                expect(r.draftsman_type).toBe(ET.Monster)
            end)
        end)
    end)

    describe("the fatal hit", function()

        describe("given one hit flagged fatal", function()
            it("attaches it to the result", function()
                local id = place(B.make_monster{})
                local fatal = B.make_hit{ power = 5, time = 100, is_fatal = true,
                                          draftsman_id = id }
                local r = compute({ B.make_hit{ power = 5, time = 100,
                                                draftsman_id = id }, fatal })
                expect(r.fatal_hit).toBe(fatal)
            end)

            it("attaches the resolved draftsman object to it", function()
                -- create_new() reads
                -- hit.fatal_hit.draftsman:general_goodwill(...) at
                -- soulslike_scenario_logic_factory.script:248, so the object
                -- -- not just the id -- has to be on the record.
                local stalker = B.make_stalker{}
                place(stalker)
                local fatal = B.make_hit{ power = 5, time = 0, is_fatal = true,
                                          draftsman_id = stalker:id() }
                expect(compute({ fatal }).fatal_hit.draftsman).toBe(stalker)
            end)
        end)

        describe("given several hits flagged fatal", function()
            it("picks the first, because the loop breaks on a match", function()
                local id = place(B.make_monster{})
                local first  = B.make_hit{ power = 5, time = 100, is_fatal = true,
                                           draftsman_id = id }
                local second = B.make_hit{ power = 5, time = 200, is_fatal = true,
                                           draftsman_id = id }
                expect(compute({ first, second }).fatal_hit).toBe(first)
            end)
        end)

        describe("given no hit is flagged fatal", function()
            -- Damage-over-time deaths: nothing is marked fatal, but
            -- attribution must still pick a bucket.
            it("still resolves a draftsman type", function()
                local id = place(B.make_monster{})
                expect(compute({ B.make_hit{ power = 5, time = 100,
                                             draftsman_id = id } }).draftsman_type)
                    .toBe(ET.Monster)
            end)

            it("leaves fatal_hit nil", function()
                local id = place(B.make_monster{})
                expect(compute({ B.make_hit{ power = 5, time = 100,
                                             draftsman_id = id } }).fatal_hit)
                    .toBeNil()
            end)
        end)
    end)

    describe("side effects", function()
        describe("given any hit record", function()
            it("CHARACTERIZATION: writes the draftsman back onto the caller's table", function()
                -- soulslike.script keeps these in the TimedQueue, so after a
                -- death the queued records hold live object references until
                -- Clear() runs.
                local id = place(B.make_monster{})
                local rec = B.make_hit{ power = 5, time = 0, is_fatal = true,
                                        draftsman_id = id }
                expect(rec.draftsman).toBeNil()          -- precondition
                compute({ rec })
                expect(rec.draftsman).toBeDefined()
            end)
        end)
    end)

    describe("given a realistic mixed engagement", function()
        local function run()
            local stalker = place(B.make_stalker{})
            local monster = place(B.make_monster{})
            return compute({
                B.make_hit{ power = 20, time = 0,    draftsman_id = stalker }, -- w 0.0  -> 0
                B.make_hit{ power = 20, time = 1000, draftsman_id = stalker }, -- w 0.5  -> 10
                B.make_hit{ power = 30, time = 1500, draftsman_id = monster }, -- w 0.75 -> 22.5
                B.make_hit{ power = 30, time = 2000, draftsman_id = monster,
                            is_fatal = true },                                 -- w 1 x2 -> 60
            })
        end

        it("attributes to the dominant late damage", function()
            expect(run().draftsman_type).toBe(ET.Monster)
        end)

        it("sums the winning bucket correctly", function()
            expect(run().power).toBeCloseTo(82.5)
        end)

        it("reports the fatal hit", function()
            expect(run().fatal_hit).toBeDefined()
        end)
    end)
end)

return true
