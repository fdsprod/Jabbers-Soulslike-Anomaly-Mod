-- Deferred callbacks: CreateTimeEvent / RemoveTimeEvent.
--
-- The mod uses these to continue work on a later frame, so the death->respawn
-- flow does NOT complete synchronously. Two sites depend on it:
--
--   HandleItemsAndRespawn (soulslike_scenarios.script:549) waits for the stash
--     object to exist before transferring items into it.
--   RespawnActor (:860) defers the ChangeLevel call.
--
-- Contract, from wait_for_stash_creation (:535): the callback returns true when
-- it is done and the event should be dropped, false to stay queued and be
-- retried on a later frame. We re-queue on false, which is what makes a spec
-- able to model "the stash is not online yet, then it is".

local M = {}

local queue = {}
local seq = 0

-- A never-satisfied condition would spin forever. Bound it so the spec fails
-- with a clear message instead of hanging the runner.
M.max_passes = 32

function M.install(env)
    env = env or _G

    env.CreateTimeEvent = function(a, b, delay, fn, ...)
        seq = seq + 1
        queue[#queue + 1] = {
            id    = seq,
            key   = tostring(a) .. "/" .. tostring(b),
            delay = delay,
            fn    = fn,
            args  = { ... },
            n     = select("#", ...),
        }
        return true
    end

    env.RemoveTimeEvent = function(a, b)
        local key = tostring(a) .. "/" .. tostring(b)
        for i = #queue, 1, -1 do
            if queue[i].key == key then table.remove(queue, i) end
        end
        return true
    end

    return env
end

--- Drain the queue. Events returning false are retried on the next pass, so a
--- chain (event A queues event B) settles in one pump() call.
--- Returns the number of callbacks invoked.
---
--- opts.passes bounds the number of passes and, because a bounded pump is an
--- explicit "run N frames" rather than "run to completion", leaves anything
--- still queued in place instead of raising. That is how a spec observes the
--- retry contract: pump one frame with the stash offline, assert nothing moved
--- and the event is still pending, bring the stash online, pump again.
function M.pump(opts)
    opts = opts or {}
    local limit = opts.passes or M.max_passes
    local invoked = 0

    for _ = 1, limit do
        if #queue == 0 then return invoked end

        local batch = queue
        queue = {}

        for _, ev in ipairs(batch) do
            invoked = invoked + 1
            local done = ev.fn(unpack(ev.args, 1, ev.n))
            if done ~= true then
                queue[#queue + 1] = ev      -- still waiting; retry next pass
            end
        end

    end

    if opts.passes then return invoked end

    -- A retrying event is legitimate -- wait_for_stash_creation returns false
    -- until the stash exists. There is no way to tell "will succeed later" from
    -- "never will" without running it, so max_passes is the only honest bound.
    local keys = {}
    for i, ev in ipairs(queue) do keys[i] = ev.key end
    error("timeevents: " .. #queue .. " event(s) still queued after " ..
          M.max_passes .. " passes (" .. table.concat(keys, ", ") ..
          ") -- they never returned true, so the condition they wait on is " ..
          "never met. If the wait is legitimate, raise timeevents.max_passes.", 2)
end

function M.pending() return #queue end

function M.peek()
    local out = {}
    for i, ev in ipairs(queue) do out[i] = ev.key end
    return out
end

function M.reset()
    queue = {}
    seq = 0
    M.max_passes = 32
end

return M
