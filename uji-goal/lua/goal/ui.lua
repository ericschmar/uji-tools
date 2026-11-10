local M = {}

local ito = require("ito")

local function goal_detail(goal)
  if not goal then
    return "No goal is set."
  end

  local lines = {
    "# " .. (goal.objective or "Untitled goal"),
    "",
    "**ID:** " .. (goal.id or "unknown"),
    "**Status:** " .. (goal.status or "unknown"),
    "**Sisyphus mode:** " .. (goal.sisyphus and "on" or "off"),
  }
  if goal.archived_at then lines[#lines + 1] = "**Archived:** " .. tostring(goal.archived_at) end
  if goal.completion_summary then lines[#lines + 1] = "**Completion summary:** " .. goal.completion_summary end
  if goal.auto_continue ~= nil then
    lines[#lines + 1] = "**Auto-continue:** " .. (goal.auto_continue and "on" or "off")
  end
  if goal.pause_reason then lines[#lines + 1] = "**Pause reason:** " .. goal.pause_reason end
  if goal.stop_reason then lines[#lines + 1] = "**Stop reason:** " .. goal.stop_reason end
  if goal.verification_contract and goal.verification_contract ~= "" then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "## Verification contract"
    lines[#lines + 1] = goal.verification_contract
  end
  if goal.verification_summary then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "## Verification summary"
    lines[#lines + 1] = goal.verification_summary
  end

  local function render(tasks, depth)
    for _, task in ipairs(tasks or {}) do
      local marker = task.status == "complete" and "x" or task.status == "skipped" and "-" or " "
      lines[#lines + 1] = string.rep("  ", depth) .. "- [" .. marker .. "] " .. (task.title or task.id or "Task") .. " (`" .. (task.id or "unknown") .. "`)"
      if task.verification_contract and task.verification_contract ~= "" then
        lines[#lines + 1] = string.rep("  ", depth + 1) .. "- Contract: " .. task.verification_contract
      end
      if task.evidence and task.evidence ~= "" then
        lines[#lines + 1] = string.rep("  ", depth + 1) .. "- Evidence: " .. task.evidence
      end
      if task.skip_reason then lines[#lines + 1] = string.rep("  ", depth + 1) .. "- Skip reason: " .. task.skip_reason end
      render(task.subtasks, depth + 1)
    end
  end
  if goal.tasks and #goal.tasks > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "## Tasks"
    render(goal.tasks, 0)
  end
  return table.concat(lines, "\n")
end

function M.detail(goal)
  return goal_detail(goal)
end

function M.list(state)
  local goals = state and state.goals or {}
  local entries = {}
  for id, goal in pairs(goals) do
    if not goal.archived_at then entries[#entries + 1] = { id = goal.id or id, goal = goal } end
  end
  table.sort(entries, function(a, b)
    if (a.goal.created_at or "") == (b.goal.created_at or "") then return a.id < b.id end
    return (a.goal.created_at or "") < (b.goal.created_at or "")
  end)
  if #entries == 0 then return "No goals." end
  local lines = { "# Goals", "" }
  for _, entry in ipairs(entries) do
    local goal = entry.goal
    local marker = entry.id == (state and state.focused_id) and "▶" or " "
    lines[#lines + 1] = string.format("%s **%s** — %s", marker, entry.id, goal.status or "unknown")
    lines[#lines + 1] = "  " .. (goal.objective or "Untitled goal")
  end
  return table.concat(lines, "\n")
end

function M.tasks(goal)
  if not goal or not goal.tasks or #goal.tasks == 0 then return "No tasks for this goal." end
  local lines = { "# Tasks: " .. (goal.objective or goal.id or "Goal"), "" }
  local function render(tasks, depth)
    for _, task in ipairs(tasks) do
      local marker = task.status == "complete" and "x" or task.status == "skipped" and "-" or " "
      lines[#lines + 1] = string.rep("  ", depth) .. "- [" .. marker .. "] " .. (task.title or task.id or "Task") .. " (`" .. (task.id or "unknown") .. "`)"
      if task.skip_reason then lines[#lines + 1] = string.rep("  ", depth + 1) .. "  Skip reason: " .. task.skip_reason end
      if task.evidence then lines[#lines + 1] = string.rep("  ", depth + 1) .. "  Evidence: " .. task.evidence end
      if task.verification_contract then lines[#lines + 1] = string.rep("  ", depth + 1) .. "  Contract: " .. task.verification_contract end
      render(task.subtasks, depth + 1)
    end
  end
  render(goal.tasks, 0)
  return table.concat(lines, "\n")
end

function M.show(title, text)
  return uji.ui.overlay(function()
    return ito.ScrollView(uji.ui.Markdown(text or "")):padding(1):border(ito.theme().borders.rounded):title(title or "")
  end)
end

function M.pick(state, on_choice)
  local goals = state and state.goals or {}
  local items = {}
  for id, goal in pairs(goals) do if not goal.archived_at then items[#items + 1] = id end end
  table.sort(items)
  return uji.ui.pick({
    title = "Choose goal",
    items = items,
    current = state and state.focused_id,
    label = function(id)
      local goal = goals[id]
      return id .. " — " .. (goal.status or "unknown") .. " — " .. (goal.objective or "")
    end,
  }, on_choice)
end

function M.toolbar()
  local display = ito.state("No goal")
  local handle = uji.ui.toolbar({
    ito.ToolbarItem(ito.ToolbarPlacement.bottom_bar, function()
      return ito.Text(display.value)
    end),
  })
  return {
    update = function(_, goal, runner_status)
      local text = "No goal"
      if goal then
        local objective = goal.objective or ""
        if #objective > 80 then objective = objective:sub(1, 77) .. "..." end
        local resolved, total = 0, 0
        local function count(tasks)
          for _, task in ipairs(tasks or {}) do
            total = total + 1
            if task.status == "complete" or task.status == "skipped" then resolved = resolved + 1 end
            count(task.subtasks)
          end
        end
        count(goal.tasks)
        text = (goal.status or "unknown") .. " · " .. objective .. string.format(" · %d/%d tasks", resolved, total)
      end
      if type(runner_status) == "table" then
        local used = tonumber(runner_status.used) or 0
        local limit = tonumber(runner_status.limit) or 0
        text = text .. string.format(" · %d/%d turns%s", used, limit, runner_status.armed and " · armed" or "")
      end
      display.value = text
    end,
    remove = function()
      return handle:remove()
    end,
  }
end

return M
