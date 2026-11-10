local M = {}

local DEFAULT_LIMIT = 10

function M.new(opts)
  opts = opts or {}
  local focused = assert(opts.focused, "focused callback is required")
  local pause = assert(opts.pause, "pause callback is required")
  local changed = opts.changed or function() end
  local uji = opts.uji or _G.uji
  local limit = opts.limit == nil and DEFAULT_LIMIT or opts.limit
  assert(type(limit) == "number" and limit >= 0 and limit % 1 == 0, "limit must be an integer >= 0")
  local enabled = false
  local goal_id
  local turns = 0
  local error_seen = false
  local generation = 0
  local pending = false
  local handlers = {}

  local function notify()
    changed()
  end

  local function stop(reason)
    enabled = false
    goal_id = nil
    error_seen = false
    generation = generation + 1
    pending = false
    notify()
    return reason
  end

  local function current_goal()
    local ok, goal = pcall(focused)
    if not ok then
      return nil
    end
    return goal
  end

  local function on_error(message)
    if type(message) == "table" and message.type == "error" then
      error_seen = true
    end
  end

  local function on_queued()
    if enabled and uji.session.queue and #uji.session.queue() > 0 then
      stop("user message queued")
    end
  end

  local function on_created()
    if enabled then
      stop("new session created")
    end
  end

  local function on_finished()
    if not enabled or pending then
      return
    end
    local active = current_goal()
    if not active or active.id ~= goal_id then
      stop("goal is no longer focused")
      return
    end
    if active.status == "paused" or active.status == "aborted" or active.status == "complete" or active.status == "completed" then
      stop(active.status)
      return
    end
    if error_seen then
      local reason = "turn ended with an error or interruption"
      stop(reason)
      pcall(pause, reason)
      return
    end
    if uji.session.queue and #uji.session.queue() > 0 then
      stop("user message queued")
      return
    end
    if active.auto_continue == false then
      stop("auto continuation disabled")
      return
    end
    if turns >= limit then
      local reason = "continuation limit reached"
      stop(reason)
      pcall(pause, reason)
      return
    end
    turns = turns + 1
    error_seen = false
    pending = true
    local token = generation
    uji.defer(0, function()
      if token ~= generation then
        return
      end
      pending = false
      if not enabled then
        return
      end
      local latest = current_goal()
      if not latest or latest.id ~= goal_id or latest.status ~= "active" or latest.auto_continue == false then
        stop("goal state changed")
        return
      end
      if uji.session.state() ~= "idle" or (uji.session.queue and #uji.session.queue() > 0) then
        stop("session busy or user message queued")
        return
      end
      local ok = pcall(uji.session.submit, "Continue the focused goal. Review its current state and take the next safe, unfinished step. If blocked, pause the goal with a reason; if finished, mark it complete.")
      if not ok then
        stop("continuation submit failed")
        return
      end
      notify()
    end)
    notify()
  end

  local api = {}

  function api.start(id)
    local active = current_goal()
    if not active or active.id ~= id then
      return nil, "goal is not focused"
    end
    if active.status ~= "active" or active.auto_continue == false then
      return nil, "goal is not eligible for auto continuation"
    end
    goal_id = id
    turns = 0
    error_seen = false
    generation = generation + 1
    enabled = true
    notify()
    return true
  end

  function api.stop()
    if enabled then
      stop("stopped")
    end
  end

  function api.status()
    return { enabled = enabled, goal_id = goal_id, turns = turns, limit = limit }
  end

  function api.setup()
    if not uji then
      return nil, "uji runtime unavailable"
    end
    if not uji.on or not uji.defer or not uji.session then
      return nil, "uji runtime does not support safe continuation"
    end
    handlers.error = uji.on("message_appended", on_error, { name = "goal-runner-error" })
    handlers.submitted = uji.on("message_submitted", on_queued, { name = "goal-runner-queue" })
    handlers.queue = uji.on("queue_changed", on_queued, { name = "goal-runner-queue-changed" })
    handlers.finished = uji.on("turn_finished", on_finished, { name = "goal-runner-finished" })
    handlers.created = uji.on("session_created", on_created, { name = "goal-runner-created" })
    handlers.paused = uji.on("before_quit", function() api.stop() end, { name = "goal-runner-quit" })
    handlers.resumed = uji.on("session_resumed", function() api.stop() end, { name = "goal-runner-resume" })
    return true
  end

  function api.set_limit(value)
    assert(type(value) == "number" and value >= 0 and value % 1 == 0, "limit must be an integer >= 0")
    limit = value
    notify()
    return true
  end

  function api.dispose()
    api.stop()
    if uji and uji.off then
      for event, name in pairs({
        message_appended = "goal-runner-error", message_submitted = "goal-runner-queue",
        queue_changed = "goal-runner-queue-changed", turn_finished = "goal-runner-finished",
        session_created = "goal-runner-created", before_quit = "goal-runner-quit",
        session_resumed = "goal-runner-resume",
      }) do
        uji.off(event, name)
      end
    end
    handlers = {}
  end

  return api
end

return M
