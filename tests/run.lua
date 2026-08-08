-- Test entry point. Run via run.bat, or:
--   tools\luajit.exe run.lua            (all specs)
--   tools\luajit.exe run.lua self       (harness self-tests only)
--   tools\luajit.exe run.lua unit       (unit specs only)
--
-- Flags:
--   --no-color   plain output (also honours NO_COLOR / SPEC_NO_COLOR)
--   --ascii      ok/XX instead of the tick and cross, for a non-UTF-8 console

package.path = "./?.lua;" .. package.path

local spec = require("harness.spec")

-- Loaded with dofile rather than require: `.spec.lua` is the TS-idiomatic
-- filename but the dots do not map onto require's module paths.
local SELF = {
    "self/class.spec.lua",
    "self/loader.spec.lua",
    "self/dispatch.spec.lua",
    "self/timeevents.spec.lua",
    "self/world.spec.lua",
    "self/mods.spec.lua",
}

local UNIT = {
    "unit/helpers.spec.lua",
    "unit/timed_queue.spec.lua",
    "unit/state_shape.spec.lua",
    "unit/message_factory.spec.lua",
    "unit/fatal_hit.spec.lua",
}

-- Flags anywhere in the args; the first non-flag word selects the suite.
local which = "all"
for _, a in ipairs(arg or {}) do
    if a == "--no-color" then
        spec.configure{ color = false }
    elseif a == "--ascii" then
        spec.configure{ unicode = false }
    elseif a ~= "" and a:sub(1, 2) ~= "--" then
        which = a
    end
end

local function load_all(files)
    for _, path in ipairs(files) do
        local ok, err = pcall(dofile, path)
        if not ok then
            print("")
            print("!! failed to load " .. path)
            print("   " .. tostring(type(err) == "table" and err.msg or err))
            os.exit(2)
        end
    end
end

if which == "self" then
    load_all(SELF)
    os.exit(spec.run() == 0 and 0 or 1)
end

if which == "unit" then
    load_all(UNIT)
    os.exit(spec.run() == 0 and 0 or 1)
end

-- Full run. Self-tests gate the unit specs: if the harness is not faithful,
-- unit results mean nothing, so a self-test failure aborts before unit/ runs.
load_all(SELF)
local self_failed = spec.run()
if self_failed > 0 then
    print("")
    print("!! harness self-tests failed -- unit specs skipped.")
    print("   Fix the harness first; unit results would not be trustworthy.")
    os.exit(1)
end

print("")
spec.reset()
load_all(UNIT)
os.exit(spec.run() == 0 and 0 or 1)
