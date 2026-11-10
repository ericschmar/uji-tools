package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local Runner = require("goal.runner")

local function harness(limit)
  local events = {}
  local names = {}
  local deferred = {}
  local goal = { id = "g1", status = "active", auto_continue = true }
  local queue = {}
  local submissions = {}
  local runtime = {
    on = function(name, callback, opts)
      events[name] = callback
      local handler_name = opts and opts.name or name
      names[handler_name] = name
      return handler_name
    end,
    off = function(event, name)
      assert(names[name] == event)
      events[event] = nil
    end,
    defer = function(_, callback)
      deferred[#deferred + 1] = callback
    end,
    session = {
      queue = function() return queue end,
      state = function() return "idle" end,
      submit = function(text) submissions[#submissions + 1] = text end,
    },
  }
  local pauses, changes = {}, 0
  local runner = Runner.new({
    uji = runtime,
    limit = limit,
    focused = function() return goal end,
    pause = function(reason) pauses[#pauses + 1] = reason end,
    changed = function() changes = changes + 1 end,
  })
  runner.setup()
  return runner, events, deferred, submissions, goal, queue, pauses
end

local function equal(a, b, message)
  assert(a == b, message or (tostring(a) .. " ~= " .. tostring(b)))
end

local runner, events, deferred, submissions, goal, queue = harness(2)
assert(runner.start("g1"))
events.turn_finished()
events.turn_finished()
equal(#deferred, 1)
deferred[1]()
equal(#submissions, 1)
events.turn_finished()
deferred[2]()
equal(#submissions, 2)
events.turn_finished()
equal(runner.status().enabled, false)
equal(#deferred, 2)

runner, events, deferred, submissions, goal, queue = harness(2)
assert(runner.start("g1"))
events.turn_finished()
queue[1] = "queued"
events.queue_changed()
deferred[1]()
equal(#submissions, 0)
equal(runner.status().enabled, false)

runner, events, deferred, submissions = harness(2)
assert(runner.start("g1"))
events.turn_finished()
events.session_created()
deferred[1]()
equal(#submissions, 0)
equal(runner.status().enabled, false)

runner, events = harness(2)
assert(not pcall(runner.set_limit, -1))
assert(not pcall(runner.set_limit, 1.5))
assert(runner.set_limit(0))
equal(runner.status().limit, 0)
runner.dispose()
equal(events.turn_finished, nil)

runner, events, deferred, submissions, goal, queue = harness(2)
assert(runner.start("g1"))
queue[1] = "my message"
events.turn_finished()
equal(#deferred, 0)
equal(runner.status().enabled, false)

runner, events, deferred, submissions = harness(2)
assert(runner.start("g1"))
events.message_appended({ type = "error", text = "interrupted" })
events.turn_finished()
equal(#deferred, 0)
equal(runner.status().enabled, false)

runner, events, deferred, submissions, goal = harness(2)
assert(runner.start("g1"))
goal.status = "paused"
events.turn_finished()
equal(#deferred, 0)
equal(runner.status().enabled, false)

runner, events, deferred, submissions = harness(2)
assert(runner.start("g1"))
events.session_resumed()
events.turn_finished()
equal(#deferred, 0)
equal(runner.status().enabled, false)

print("runner tests passed")
