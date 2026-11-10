local store = ...
local ito = require("ito")
local app = require("uji.core.app")
local ui = require("uji.core.ui")
local UI = require("goal.ui")
local plugin = require("goal").setup({ max_auto_turns = 2 })
app.attach(store:create_session("Goal native UI"))
uji.ui.configure({ theme = "default" })
ui:open()
ui:listen()

local goal = {
  id = "goal-completed", status = "complete", objective = "Completed visible goal",
  tasks = {
    { id = "task-evidence", title = "Verified task", status = "complete", evidence = "UI smoke evidence" },
    { id = "task-skipped", title = "Skipped task", status = "skipped", skip_reason = "Not applicable" },
  },
}
local archived = { id = "goal-archived", status = "paused", objective = "Archived hidden goal", archived_at = "now" }
local state = { goals = { [goal.id] = goal, [archived.id] = archived }, focused_id = goal.id }

local toolbar = UI.toolbar()
toolbar:update(goal, { armed = true, used = 1, limit = 2 })
local function screen()
  ui:paint()
  local diagnostics = require("uji.core.diagnostics").list()
  assert(#diagnostics == 0, uji.json.encode(diagnostics))
  local _, height = ui.screen:size()
  local lines = {}
  for row = 0, height - 1 do lines[#lines + 1] = ui.screen:text(row) end
  return table.concat(lines, "\n")
end
local function has(text)
  return screen():find(text, 1, true) ~= nil
end
assert(has("Completed visible goal"), "goal toolbar objective missing")
assert(has("1/2 turns"), "goal toolbar turn usage missing")

local picker_items
local picker_label
local old_pick = uji.ui.pick
uji.ui.pick = function(options)
  picker_items = options.items
  picker_label = options.label
end
UI.pick(state, function() end)
uji.ui.pick = old_pick
assert(#picker_items == 1 and picker_items[1] == goal.id, "goal picker must show completed and exclude archived goals")
assert(picker_label(goal.id):find("complete", 1, true), "completed goal picker label missing status")

local overlay = UI.show("Goal task details", UI.detail(goal))
assert(overlay and type(overlay.close) == "function")
assert(has("task-evidence"), "task IDs missing from native overlay")
assert(has("UI smoke evidence"), "task evidence missing from native overlay")
assert(has("Not applicable"), "skip reason missing from native overlay")
local shown = false
for _ = 1, 8 do
  ui:key(require("uji.core.ui.keys").chord("down"))
  local text = screen()
  if text:find("Skip reason", 1, true) then shown = true end
end
assert(shown, "task overlay content should remain scrollable")
overlay:close()
local diagnostics = require("uji.core.diagnostics").list()
assert(#diagnostics == 0, uji.json.encode(diagnostics))
io.stdout:write("\npassed terminal UI: goal toolbar, completed/archived picker, scrollable task evidence and skip reasons\n")
