local model = require("goal.model")
local store = require("goal.store")
local passed = 0

local function test(name, fn)
  fn()
  passed = passed + 1
  io.stdout:write("ok ", name, "\n")
end

local function rejects(value)
  assert(value == nil)
end

test("task normalization boundaries, IDs and ownership", function()
  local tasks = {}
  for i = 1, 8 do tasks = { { title = tostring(i), subtasks = tasks } } end
  assert(#assert(model.normalize_tasks(tasks)) == 1)
  local generated = assert(model.normalize_tasks({ { title = "Generated" }, { id = "task-1", title = "Explicit" } }))
  assert(generated[1].id ~= "task-1")
  rejects(model.normalize_tasks({ ignored = { title = "Map" } }))
  local input = { { title = "Owned", extra = { value = true } } }
  local output = assert(model.normalize_tasks(input))
  output[1].extra.value = false
  assert(input[1].extra.value == true)
  rejects(model.new("Ship", { id = "g", verification_contract = false }))
  rejects(model.normalize_tasks({ { title = "X", verification_contract = false } }))
end)

test("archived marker forbids every mutation; reasons and resume cleanup", function()
  local goal = assert(model.new("Ship", { id = "g" }))
  goal.archived_at = "now"
  rejects(model.update(goal, { objective = "Other" }, true))
  rejects(model.pause(goal, "reason")); rejects(model.abort(goal, "reason")); rejects(model.complete(goal, "done"))
  rejects(model.tweak(goal, "Other", true)); rejects(model.set_task_status(goal, "missing", "complete"))
  goal.archived_at = nil
  rejects(model.pause(goal))
  goal = assert(model.pause(goal, "because"))
  goal.suggested_action = "act"
  goal = assert(model.resume(goal))
  assert(goal.pause_reason == nil and goal.suggested_action == nil)
  rejects(model.abort(goal))
  assert(assert(model.abort(goal, "because")).status == "aborted")
end)

test("completion summaries, evidence and descendant resolution are mandatory", function()
  local goal = assert(model.new("Ship", { id = "g", verification_contract = "Tests pass", tasks = {
    { id = "p", title = "Parent", subtasks = { { id = "c", title = "Child", verification_contract = "Test" } } },
  } }))
  rejects(model.complete(goal, "", ""))
  rejects(model.complete(goal, "done", "evidence"))
  rejects(model.set_task_status(goal, "p", "complete"))
  rejects(model.set_task_status(goal, "c", "complete"))
  local child_done = assert(model.set_task_status(goal, "c", "complete", "Tests passed"))
  assert(goal.tasks[1].subtasks[1].status == "pending")
  local all_done = assert(model.set_task_status(child_done, "p", "complete"))
  rejects(model.complete(all_done, "done", " "))
  local complete = assert(model.complete(all_done, "Shipped", "Tests passed"))
  assert(complete.status == "complete" and all_done.status == "active")
  rejects(model.set_task_status(complete, "p", "skipped", "reason"))
end)

test("skips require reasons and retain completed descendant evidence", function()
  local goal = assert(model.new("Ship", { id = "g", tasks = {
    { id = "p", title = "Parent", subtasks = { { id = "a", title = "A" }, { id = "b", title = "B" } } },
  } }))
  rejects(model.set_task_status(goal, "p", "skipped", " "))
  goal = assert(model.set_task_status(goal, "a", "complete", "Evidence retained"))
  goal = assert(model.set_task_status(goal, "p", "skipped", "Out of scope"))
  assert(goal.tasks[1].subtasks[1].evidence == "Evidence retained")
  assert(goal.tasks[1].subtasks[2].status == "skipped")
  assert(goal.tasks[1].subtasks[2].skip_reason:find("Out of scope", 1, true))
  assert(model.complete(goal, "Done"))
end)

test("objectives and task validation reject invalid input without mutations", function()
  rejects(model.new(" ", { id = "g" }))
  rejects(model.normalize_tasks({ { id = "x", title = "A" }, { id = "x", title = "B" } }))
  rejects(model.normalize_tasks({ { title = "A" }, { title = "a" } }))
  local nested = { title = "leaf" }
  for i = 1, 8 do nested = { title = tostring(i), subtasks = { nested } } end
  rejects(model.normalize_tasks({ nested }))
  local goal = assert(model.new("Original", { id = "g", tasks = { { title = "Task", status = "complete" } } }))
  assert(goal.tasks[1].status == "pending", "caller cannot pre-complete tasks")
  rejects(model.tweak(goal, "Changed", false))
  assert(goal.objective == "Original")
  assert(assert(model.tweak(goal, "Changed", true)).objective == "Changed")
end)

test("store rejects malformed records before accepting them", function()
  uji = {
    sha256 = function() return string.rep("x", 32) end,
    data = { write = function(_, _, callback) callback(true) end },
    json = { encode = function(v) return v end, array = function(v) return v end },
  }
  local goal = assert(model.new("Ship", { id = "g" }))
  local state = { version = 1, directory = "/p", goals = { g = goal }, focused_id = "g", settings = { max_auto_turns = 10 } }
  local saved
  store.save(state, function(ok) saved = ok end)
  assert(saved)
  local function rejected_record(change)
    local copied_goal = {}
    for key, value in pairs(goal) do copied_goal[key] = value end
    local copy = { version = 1, directory = "/p", goals = { g = copied_goal }, focused_id = "g", settings = { max_auto_turns = 10 } }
    change(copy)
    local result, failure
    store.save(copy, function(ok, err) result = ok; if ok == nil then failure = err end end)
    assert(result == nil, failure)
  end
  rejected_record(function(s) s.goals.x = goal end)
  rejected_record(function(s) s.goals.g.status = "nonsense" end)
  rejected_record(function(s) s.focused_id = "missing" end)
  rejected_record(function(s) s.settings.max_auto_turns = -1 end)
  rejected_record(function(s) s.goals.g.tasks = { bad = true } end)
  goal.archived_at = "now"
  store.save(state, function(ok, err) assert(ok, err) end)
end)

io.stdout:write("passed ", passed, " core tests\n")
