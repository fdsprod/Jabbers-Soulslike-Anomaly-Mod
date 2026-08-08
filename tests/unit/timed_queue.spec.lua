-- soulslike_classes.TimedQueue (soulslike_classes.script).
--
-- Backs the rolling hit window that feeds death-cause attribution:
-- soulslike.script:58 creates it with MAX_HIT_POOL_COUNT / MAX_HIT_TIME, and
-- actor_on_before_hit enqueues into it on every hit taken.

local H = require("harness.init")
local fakes = H.fakes

describe("TimedQueue", function()

    local TimedQueue

    beforeEach(function()
        H.boot{ load = { "soulslike_classes" } }
        TimedQueue = soulslike_classes.TimedQueue
        fakes.set_time(0)
    end)

    local function queue(max_count, expiry)
        return TimedQueue(max_count or 30, expiry or 1000)
    end

    describe("a newly constructed queue", function()
        it("has nothing to peek at", function()
            expect(queue():Peek()).toBeNil()
        end)

        it("dequeues nil", function()
            expect(queue():Dequeue()).toBeNil()
        end)

        it("has no values", function()
            expect(queue():Values()).toHaveLength(0)
        end)
    end)

    describe("Enqueue()", function()
        describe("given an entry", function()
            it("stamps it with the current time_global", function()
                local q = queue()
                fakes.set_time(4321)
                q:Enqueue({ id = 1 })
                expect(q:Peek().__cached_time).toBe(4321)
            end)
        end)

        describe("given an entry that already carries __cached_time", function()
            it("overwrites it, so callers cannot backdate an entry", function()
                local q = queue()
                fakes.set_time(777)
                q:Enqueue({ id = 1, __cached_time = 1 })
                expect(q:Peek().__cached_time).toBe(777)
            end)
        end)
    end)

    describe("Dequeue()", function()
        describe("given several entries", function()
            it("returns them in FIFO order", function()
                local q = queue()
                q:Enqueue({ id = 1 }); q:Enqueue({ id = 2 }); q:Enqueue({ id = 3 })
                expect(q:Dequeue().id).toBe(1)
                expect(q:Dequeue().id).toBe(2)
                expect(q:Dequeue().id).toBe(3)
            end)

            it("returns nil once drained", function()
                local q = queue()
                q:Enqueue({ id = 1 })
                q:Dequeue()
                expect(q:Dequeue()).toBeNil()
            end)
        end)
    end)

    describe("Peek()", function()
        describe("given a non-empty queue", function()
            it("returns the head", function()
                local q = queue()
                q:Enqueue({ id = 1 })
                expect(q:Peek().id).toBe(1)
            end)

            it("does not consume it", function()
                local q = queue()
                q:Enqueue({ id = 1 })
                q:Peek()
                expect(q:Peek().id).toBe(1)
                expect(q:Dequeue().id).toBe(1)
            end)
        end)
    end)

    describe("Values()", function()
        describe("given several entries", function()
            it("returns all of them", function()
                local q = queue()
                q:Enqueue({ id = 1 }); q:Enqueue({ id = 2 })
                expect(q:Values()).toHaveLength(2)
            end)
        end)

        describe("given a partial dequeue", function()
            -- The internal first/last index pair leaves a hole at the front,
            -- and Values() walks with pairs(). This is the shape most at risk.
            it("omits the dequeued entry", function()
                local q = queue()
                q:Enqueue({ id = 1 }); q:Enqueue({ id = 2 }); q:Enqueue({ id = 3 })
                q:Dequeue()

                local vals = q:Values()
                expect(vals).toHaveLength(2)
                for _, v in ipairs(vals) do
                    expect(v.id).never.toBe(1)
                end
            end)
        end)
    end)

    describe("Clear()", function()
        describe("given a populated queue", function()
            it("empties it", function()
                local q = queue()
                q:Enqueue({ id = 1 }); q:Enqueue({ id = 2 })
                q:Clear()
                expect(q:Peek()).toBeNil()
                expect(q:Values()).toHaveLength(0)
            end)

            it("resets the indices so the queue is reusable", function()
                local q = queue()
                q:Enqueue({ id = 1 }); q:Enqueue({ id = 2 })
                q:Clear()
                q:Enqueue({ id = 9 })
                expect(q:Peek().id).toBe(9)
                expect(q:Values()).toHaveLength(1)
            end)
        end)
    end)

    describe("Invalidate()", function()

        describe("given an entry older than the expiry window", function()
            it("drops it", function()
                local q = queue(30, 1000)
                fakes.set_time(0)
                q:Enqueue({ id = "old" })
                fakes.set_time(2000)
                q:Invalidate()
                expect(q:Peek()).toBeNil()
            end)
        end)

        describe("given an entry inside the window", function()
            it("keeps it", function()
                local q = queue(30, 1000)
                fakes.set_time(0)
                q:Enqueue({ id = "fresh" })
                fakes.set_time(500)
                q:Invalidate()
                expect(q:Peek().id).toBe("fresh")
            end)
        end)

        describe("given an entry exactly on the window boundary", function()
            it("keeps it, because the comparison is strict", function()
                -- Condition is `cached + expiry < now`, so equality survives.
                local q = queue(30, 1000)
                fakes.set_time(0)
                q:Enqueue({ id = "edge" })
                fakes.set_time(1000)
                q:Invalidate()
                expect(q:Peek().id).toBe("edge")
            end)
        end)

        describe("given expired entries followed by a live one", function()
            it("stops at the first live entry", function()
                -- It breaks rather than scanning on, which is correct only
                -- because entries are enqueued in time order.
                local q = queue(30, 1000)
                fakes.set_time(0);    q:Enqueue({ id = "old1" })
                fakes.set_time(100);  q:Enqueue({ id = "old2" })
                fakes.set_time(5000); q:Enqueue({ id = "fresh" })

                fakes.set_time(5100)
                q:Invalidate()

                local vals = q:Values()
                expect(vals).toHaveLength(1)
                expect(vals[1].id).toBe("fresh")
            end)
        end)

        describe("given every entry has expired", function()
            it("empties the queue", function()
                local q = queue(30, 100)
                fakes.set_time(0)
                q:Enqueue({ id = 1 }); q:Enqueue({ id = 2 })
                fakes.set_time(10000)
                q:Invalidate()
                expect(q:Values()).toHaveLength(0)
            end)
        end)

        describe("given an empty queue", function()
            it("does not raise", function()
                local q = queue()
                expect(function() q:Invalidate() end).never.toThrow()
            end)
        end)
    end)

    describe("max_count", function()
        -- CHARACTERIZATION, NOT ENDORSEMENT. __init takes max_count and the
        -- caller passes MAX_HIT_POOL_COUNT = 30 (soulslike.script:56), but no
        -- method ever reads it -- Enqueue does not evict. In-game the queue is
        -- bounded only by the 30s expiry window and by Clear() on death, so a
        -- sustained hit stream grows it without limit.
        --
        -- If bounding is later added, these should flip to asserting eviction.
        describe("given more entries than max_count", function()
            it("does not evict anything", function()
                local q = queue(3, 100000)
                for i = 1, 10 do q:Enqueue({ id = i }) end
                expect(q:Values()).toHaveLength(10)
            end)

            it("still records the unused limit", function()
                local q = queue(3, 100000)
                expect(q.max_count).toBe(3)
            end)
        end)
    end)
end)

return true
