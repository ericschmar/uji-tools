local store = ...
local app = require("uji.core.app")
local tool = require("uji.core.tool")
local command = require("uji.core.command")
local event = require("uji.core.event")
local Store = require("goal.store")
local UI = require("goal.ui")
local parent = store:create_session("Goal integration")
app.attach(parent)
require("uji.core.model").resolve({ provider = "goal-test", model = "fake" })
local plugin = require("goal").setup({ max_auto_turns = 2 })
assert(require("goal").setup() == plugin, "setup must be idempotent")
assert(uji.json.encode(tool.get("goal_list").parameters):find('"required":%[%]'), "empty required schema must serialize as an array")
local function wait(predicate, label)
  local deadline = uji.os.clock() + 5
  while not predicate() and uji.os.clock() < deadline do uji.sleep(0.01) end
  assert(predicate(), label)
end
local function call(name, args)
  local result
  local cancel = tool.get(name).run(args or {}, { done = function(text) result = text end })
  wait(function() return result ~= nil end, "tool result: " .. name)
  assert(type(cancel) == "function", "async tools need cancellation")
  return result
end
local function success(name, args)
  local text = call(name, args)
  assert(not text:find("error:", 1, true), text)
  return text
end
local function goal()
  local state = plugin.state()
  return state.goals[state.focused_id]
end
local function run_command(name, args)
  command.commands:get(name).handler(args or "")
  uji.sleep(0.05)
end
local function roundtrip()
  local result, err
  Store.open(uji.session.info().directory, function(value, failure) result, err = value, failure end)
  wait(function() return result ~= nil or err ~= nil end, "store roundtrip")
  assert(result, err)
  return result
end

success("goal_get")
assert(not plugin.runner.status().enabled)
local text = success("goal_set", { objective = "Ship the native plugin", verification_contract = "Tests pass", tasks = {
  { id = "parent", title = "Implement", subtasks = { { id = "child", title = "Test", verification_contract = "Run tests" } } },
} })
assert(goal().id:match("^%x+$") and #goal().id == 24, "safe goal IDs")
local id = goal().id
assert(text:find(id, 1, true) and text:find("child", 1, true), "details must include goal and task IDs")
assert(call("complete_task", { task_id = "parent" }):find("error:", 1, true))
assert(call("complete_task", { task_id = "child" }):find("error:", 1, true))
success("complete_task", { task_id = "child", evidence = "Model-free test suite passed" })
success("complete_task", { task_id = "parent" })
assert(call("goal_update", { action = "complete", completion_summary = "Implemented" }):find("error:", 1, true))
success("goal_update", { action = "complete", completion_summary = "Implemented", verification_summary = "Tests pass" })
assert(goal().status == "complete" and not goal().archived_at)
assert(not plugin.runner.status().enabled)
assert(success("goal_list"):find(id, 1, true), "completed goals stay visible")
assert(roundtrip().goals[id].status == "complete", "completion persists")
assert(call("propose_task_list", { tasks = { { title = "Bypass" } } }):find("error:", 1, true))
success("goal_archive")
assert(not success("goal_list"):find(id, 1, true), "archived goals must be hidden")
assert(roundtrip().goals[id].archived_at, "archive retains history")

success("goal_set", { objective = "Original", auto_continue = false })
local original = goal().objective
assert(call("goal_update", { action = "tweak", new_objective = "Unauthorized", change_summary = "test" }):find("error:", 1, true))
assert(goal().objective == original)
local submit = uji.session.submit
uji.session.submit = function() end
run_command("goal-tweak", "Change scope")
success("goal_update", { action = "tweak", new_objective = "Authorized", change_summary = "Changed scope" })
assert(goal().objective == "Authorized" and goal().revisions[1].objective == "Original")
assert(call("goal_update", { action = "tweak", new_objective = "Again", change_summary = "test" }):find("error:", 1, true))
uji.session.submit = submit

local old = plugin.state()
local write = uji.data.write
uji.data.write = function(_, _, callback) callback(nil, "injected write failure") end
assert(call("goal_set", { objective = "Must not persist" }):find("injected write failure", 1, true))
assert(plugin.state().focused_id == old.focused_id, "write failure must not accept in-memory changes")
uji.data.write = write

success("goal_set", { objective = "Bounded continuation" })
local finished = 0
event.on("turn_finished", function() finished = finished + 1 end, { name = "goal-test-finished", priority = 1 })
app.agent:submit("Begin a model-free test turn")
wait(function() return goal().status == "paused" end, "continuation limit pauses goal")
assert(finished == 3, "initial turn plus exactly two follow-up turns")
assert(goal().pause_reason:find("limit", 1, true))
assert(not plugin.runner.status().enabled)

run_command("goal-resume")
wait(function() return app.agent:working() end, "resume starts turn")
app.agent:interrupt()
wait(function() return goal().status == "paused" end, "interrupt pauses execution")
local count = finished
uji.sleep(0.2)
assert(finished == count and not app.agent:working(), "interrupt must not restart execution")

success("goal_set", { objective = "Restored goal" })
event.emit("session_resumed", { session_id = parent.id })
success("goal_get")
assert(goal().objective == "Restored goal" and not plugin.runner.status().enabled, "restoration does not arm continuation")

local filename = Store.filename(uji.session.info().directory)
local good = uji.data.read(filename)
assert(good)
uji.data.write(filename, "{broken")
event.emit("session_resumed", { session_id = parent.id })
assert(call("goal_get"):find("error:", 1, true), "corruption must surface")
assert(call("goal_set", { objective = "Never overwrite corruption" }):find("error:", 1, true))
assert(uji.data.read(filename) == "{broken", "corruption cannot be silently replaced")
local invalid_settings = uji.json.decode(good)
invalid_settings.settings.max_auto_turns = "bad"
uji.data.write(filename, uji.json.encode(invalid_settings))
assert(call("goal_get"):find("error:", 1, true), "invalid settings cannot wedge the operation queue")
uji.data.write(filename, good)
success("goal_get")
assert(Store.filename("/another/project") ~= filename, "project directories must have separate records")
local held_write
local native_write = uji.data.write
uji.data.write = function(name, contents, callback)
  native_write(name, contents, function(ok, err)
    held_write = function() callback(ok, err) end
  end)
end
local cancelled_result
local cancel = tool.get("goal_set").run({ objective = "Cancelled while saving" }, { done = function(value) cancelled_result = value end })
wait(function() return held_write ~= nil end, "hold goal write")
cancel()
event.emit("message_appended", { type = "error", text = "interrupted" })
event.emit("turn_finished", {})
uji.data.write = native_write
held_write()
uji.sleep(0.05)
assert(cancelled_result == nil and not plugin.runner.status().enabled, "cancelled write must not arm execution")

held_write = nil
uji.data.write = function(name, contents, callback)
  native_write(name, contents, function(ok, err) held_write = function() callback(ok, err) end end)
end
tool.get("goal_set").run({ objective = "Old session write" }, { done = function() error("stale write result delivered") end })
wait(function() return held_write ~= nil end, "hold old session write")
tool.get("goal_set").run({ objective = "Old queued request" }, { done = function() error("stale queued result delivered") end })
event.emit("session_resumed", { session_id = parent.id })
uji.data.write = native_write
held_write()
uji.sleep(0.05)
assert(plugin.state() == nil and not plugin.runner.status().enabled, "stale write must not restore memory or authorization")
success("goal_get")
assert(goal().objective == "Old session write", "already committed write remains on disk, queued stale write does not run")

local native_read = uji.data.read
local held_read
event.emit("session_resumed", { session_id = parent.id })
uji.data.read = function(name, callback)
  native_read(name, function(contents, err) held_read = function() callback(contents, err) end end)
end
tool.get("goal_get").run({}, { done = function() error("stale read result delivered") end })
wait(function() return held_read ~= nil end, "hold old session read")
event.emit("session_resumed", { session_id = parent.id })
uji.data.read = native_read
held_read()
uji.sleep(0.05)
assert(plugin.state() == nil and not plugin.runner.status().enabled, "stale read must not repopulate session state")
success("goal_get")

local native_submit = uji.session.submit
uji.session.submit = function() end
run_command("sisyphus", "Follow the ordered plan")
success("goal_set", { objective = "Drafted ordered goal" })
assert(goal().sisyphus, "Sisyphus drafting mode must survive commitment without an optional flag")
plugin.runner.stop()
uji.session.submit = native_submit
local overlay = UI.show("Native goal view", UI.detail(goal()))
assert(overlay and type(overlay.close) == "function")
overlay:close()
local problems = uji.diagnostics.list()
assert(#problems == 0, uji.json.encode(problems))
print("passed native integration: lifecycle, tasks, evidence, tweaks, persistence, failure handling, bounded continuation, interruption, restoration, UI APIs")
