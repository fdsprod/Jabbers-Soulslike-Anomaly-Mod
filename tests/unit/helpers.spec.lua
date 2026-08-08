-- The helper functions soulslike.script installs onto the shared stdlib
-- tables (soulslike.script:74-93).
--
-- Trivial on their own. They earn their place by doubling as a live assertion
-- that the loader's global-table-mutation semantics are right: if the wrapper
-- ever stopped letting modules write through to the real `math` and `table`,
-- these are the first thing that breaks.

local H = require("harness.init")

describe("soulslike helpers", function()

    beforeEach(function()
        H.boot{ load = { "soulslike_classes", "soulslike" } }
    end)

    describe("math.clamp()", function()

        it("is installed on the shared math table", function()
            expect(math.clamp).toBeType("function")
        end)

        describe("given a value inside the range", function()
            it("returns it unchanged", function()
                expect(math.clamp(5, 0, 10)).toBe(5)
            end)
        end)

        describe("given a value below the range", function()
            it("returns the minimum", function()
                expect(math.clamp(-1, 0, 10)).toBe(0)
            end)
        end)

        describe("given a value above the range", function()
            it("returns the maximum", function()
                expect(math.clamp(11, 0, 10)).toBe(10)
            end)
        end)

        describe("given a value exactly on a bound", function()
            it("returns that bound", function()
                expect(math.clamp(0, 0, 10)).toBe(0)
                expect(math.clamp(10, 0, 10)).toBe(10)
            end)
        end)

        describe("given an inverted range", function()
            it("returns min, because the x < min branch wins first", function()
                -- Characterization, not endorsement. No caller does this today.
                expect(math.clamp(5, 10, 0)).toBe(10)
            end)
        end)
    end)

    describe("table.get_length()", function()

        describe("given an empty table", function()
            it("returns 0", function()
                expect(table.get_length({})).toBe(0)
            end)
        end)

        describe("given a sequential array", function()
            it("returns the element count", function()
                expect(table.get_length({ 1, 2, 3 })).toBe(3)
            end)
        end)

        describe("given a keyed table", function()
            it("counts the hash part too", function()
                expect(table.get_length({ a = 1, b = 2 })).toBe(2)
                expect(table.get_length({ 1, 2, x = 3 })).toBe(3)
            end)
        end)

        describe("given a sparse table", function()
            it("counts every entry, unlike #", function()
                -- Why the mod uses it: soulslike_scenarios.script:709 checks
                -- table.get_length(spawns) rather than #spawns.
                local sparse = {}
                sparse[1] = "a"
                sparse[5] = "b"
                expect(table.get_length(sparse)).toBe(2)
            end)
        end)
    end)

    describe("table.has_value()", function()

        describe("given a value in the array part", function()
            it("returns true", function()
                expect(table.has_value({ "a", "b" }, "b")).toBeTruthy()
            end)
        end)

        describe("given a value that is absent", function()
            it("returns false", function()
                expect(table.has_value({ "a", "b" }, "c")).toBeFalsy()
            end)
        end)

        describe("given an empty table", function()
            it("returns false", function()
                expect(table.has_value({}, "a")).toBeFalsy()
            end)
        end)

        describe("given a value only in the hash part", function()
            it("does not find it, because it walks with ipairs", function()
                -- Worth pinning: a caller passing a keyed table gets a silent
                -- false rather than an error.
                expect(table.has_value({ x = "found-me" }, "found-me")).toBeFalsy()
            end)
        end)
    end)

    describe("soulslike.try()", function()

        describe("given a function that succeeds", function()
            it("returns its result", function()
                expect(soulslike.try(function() return 42 end)).toBe(42)
            end)

            it("forwards extra arguments", function()
                expect(soulslike.try(function(a, b) return a + b end, 2, 3)).toBe(5)
            end)
        end)

        describe("given a function that raises", function()
            it("does not propagate the error", function()
                expect(function() soulslike.try(function() error("boom") end) end)
                    .never.toThrow()
            end)

            it("returns false", function()
                expect(soulslike.try(function() error("boom") end)).toBe(false)
            end)
        end)

        describe("given a function that legitimately returns false", function()
            it("is indistinguishable from a failure", function()
                -- Characterization of a real sharp edge: callers cannot tell a
                -- raised error from an honest false.
                expect(soulslike.try(function() return false end)).toBe(false)
                expect(soulslike.try(function() error("x") end)).toBe(false)
            end)
        end)
    end)
end)

return true
