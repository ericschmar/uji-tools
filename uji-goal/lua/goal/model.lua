local M = {}

local DEFAULT_MAX_DEPTH = 8

local function clone(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for key, item in pairs(value) do result[key] = clone(item) end
  return result
end

local function nonempty(value)
  return type(value) == "string" and value:match("%S") ~= nil
end

local function normalize_tasks(tasks, max_depth)
  if tasks == nil then return {} end
  if type(tasks) ~= "table" then return nil, "tasks must be a table" end
  local ids, titles, next_id = {}, {}, 0
  local function valid_list(list)
    local count, maximum = 0, 0
    for key in pairs(list) do
      if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false end
      count = count + 1
      if key > maximum then maximum = key end
    end
    return count == maximum
  end
  local function reserve(list)
    if type(list) ~= "table" or not valid_list(list) then return false end
    for _, task in ipairs(list) do
      if type(task) ~= "table" then return false end
      if task.id ~= nil then ids[task.id] = true end
      if task.subtasks ~= nil and not reserve(task.subtasks) then return false end
    end
    return true
  end
  if not reserve(tasks) then return nil, "tasks must be a table of task records" end
  local used_ids = {}
  local function visit(list, depth)
    if type(list) ~= "table" then return nil, "tasks must be a table" end
    local count, maximum = 0, 0
    for key in pairs(list) do
      if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return nil, "tasks must be an array" end
      count = count + 1; if key > maximum then maximum = key end
    end
    if count ~= maximum then return nil, "tasks must be a contiguous array" end
    if depth > max_depth and #list > 0 then return nil, "task depth exceeds limit " .. max_depth end
    local result = {}
    for _, original in ipairs(list) do
      if type(original) ~= "table" or not nonempty(original.title) then return nil, "task title must be nonempty" end
      if original.verification_contract ~= nil and type(original.verification_contract) ~= "string" then return nil, "verification contract must be a string" end
      local task = clone(original)
      if task.id == nil then
        repeat next_id = next_id + 1; task.id = "task-" .. next_id until not ids[task.id] and not used_ids[task.id]
      end
      if type(task.id) ~= "string" or not nonempty(task.id) then return nil, "task id must be nonempty" end
      if used_ids[task.id] then return nil, "duplicate task id: " .. task.id end
      used_ids[task.id] = true
      local title = task.title:lower():match("^%s*(.-)%s*$")
      if titles[title] then return nil, "duplicate task title: " .. task.title end
      titles[title] = true
      task.status = task.status or "pending"
      if task.status ~= "pending" and task.status ~= "complete" and task.status ~= "skipped" then return nil, "invalid task status: " .. tostring(task.status) end
      local subtasks, err = visit(task.subtasks or {}, depth + 1)
      if not subtasks then return nil, err end
      task.subtasks = subtasks
      result[#result + 1] = task
    end
    return result
  end
  local err
  local result
  result, err = visit(tasks, 1)
  return result, err
end

local function all_resolved(tasks)
  for _, task in ipairs(tasks or {}) do
    if task.status ~= "complete" and task.status ~= "skipped" then return false end
    if not all_resolved(task.subtasks) then return false end
  end
  return true
end

function M.new(objective, options)
  options = options or {}
  if not nonempty(objective) then return nil, "objective must be nonempty" end
  if type(options.id) ~= "string" or not nonempty(options.id) then return nil, "id is required" end
  if options.verification_contract ~= nil and type(options.verification_contract) ~= "string" then return nil, "verification contract must be a string" end
  local tasks, err = normalize_tasks(options.tasks, options.max_depth or DEFAULT_MAX_DEPTH)
  if not tasks then return nil, err end
  local function reset(tree)
    for _, task in ipairs(tree) do
      task.status, task.evidence, task.skip_reason, task.completed_at = "pending", nil, nil, nil
      reset(task.subtasks)
    end
  end
  reset(tasks)
  return { id = options.id, objective = objective, status = "active", created_at = options.now, updated_at = options.now,
    auto_continue = options.auto_continue ~= false, sisyphus = options.sisyphus == true,
    verification_contract = options.verification_contract, tasks = tasks, usage = { tokens_used = 0, active_seconds = 0 } }
end

function M.normalize_tasks(tasks, max_depth) return normalize_tasks(tasks, max_depth or DEFAULT_MAX_DEPTH) end

local function mutate(goal, operation)
  if type(goal) ~= "table" then return nil, "goal is required" end
  local result = clone(goal)
  local ok, err = operation(result)
  if not ok then return nil, err end
  return result
end

function M.update(goal, updates, authorized_tweak)
  if type(updates) ~= "table" then return nil, "updates must be a table" end
  return mutate(goal, function(copy)
    if copy.archived_at ~= nil or copy.status == "complete" or copy.status == "archived" or copy.status == "aborted" then return false, "goal is not mutable" end
    if updates.objective ~= nil and updates.objective ~= copy.objective and authorized_tweak ~= true then return false, "objective change requires authorized tweak" end
    if updates.objective ~= nil and not nonempty(updates.objective) then return false, "objective must be nonempty" end
    for key, value in pairs(updates) do
      if key == "objective" or key == "tasks" then copy[key] = value end
      if key == "verification_contract" then
        if value ~= nil and type(value) ~= "string" then return false, "verification contract must be a string" end
        copy[key] = value
      end
    end
    if updates.tasks ~= nil then
      if copy.status ~= "active" then return false, "tasks can only be updated on an active goal" end
      local tasks, err = normalize_tasks(updates.tasks)
      if not tasks then return false, err end
      local function reset(tree)
        for _, task in ipairs(tree) do
          task.status, task.evidence, task.skip_reason, task.completed_at = "pending", nil, nil, nil
          reset(task.subtasks)
        end
      end
      reset(tasks)
      copy.tasks = tasks
    end
    return true
  end)
end

function M.complete(goal, completion_summary, verification_summary, now)
  return mutate(goal, function(copy)
    if copy.archived_at ~= nil or copy.status ~= "active" then return false, "only active, non-archived goals can be completed" end
    if not nonempty(completion_summary) then return false, "completion summary must be nonempty" end
    if copy.verification_contract and copy.verification_contract ~= "" and not nonempty(verification_summary) then return false, "verification contract requires verification summary" end
    if not all_resolved(copy.tasks) then return false, "unresolved tasks remain" end
    copy.status, copy.completed_at, copy.updated_at = "complete", now, now
    copy.completion_summary, copy.verification_summary = completion_summary, verification_summary
    return true
  end)
end

function M.pause(goal, reason, now)
  return mutate(goal, function(copy)
    if copy.archived_at ~= nil or copy.status ~= "active" then return false, "cannot pause goal in status " .. tostring(copy.status) end
    if not nonempty(reason) then return false, "pause reason must be nonempty" end
    copy.status, copy.pause_reason, copy.updated_at = "paused", reason, now
    return true
  end)
end

function M.resume(goal, now)
  return mutate(goal, function(copy)
    if copy.archived_at ~= nil or copy.status ~= "paused" then return false, "cannot resume goal in status " .. tostring(copy.status) end
    copy.status, copy.pause_reason, copy.suggested_action, copy.updated_at = "active", nil, nil, now
    return true
  end)
end

function M.abort(goal, reason, now)
  return mutate(goal, function(copy)
    if copy.archived_at ~= nil or (copy.status ~= "active" and copy.status ~= "paused") then return false, "cannot abort goal in status " .. tostring(copy.status) end
    if not nonempty(reason) then return false, "abort reason must be nonempty" end
    copy.status, copy.abort_reason, copy.updated_at = "aborted", reason, now
    return true
  end)
end

function M.archive(goal, now)
  return mutate(goal, function(copy)
    if copy.status ~= "complete" and copy.status ~= "aborted" and copy.status ~= "paused" then return false, "goal cannot be archived in status " .. tostring(copy.status) end
    copy.status, copy.archived_at, copy.updated_at = "archived", now, now
    return true
  end)
end

function M.tweak(goal, objective, authorized_tweak)
  if authorized_tweak ~= true then return nil, "authorized tweak is required" end
  if type(goal) ~= "table" then return nil, "goal is required" end
  if not nonempty(objective) then return nil, "objective must be nonempty" end
  if goal.archived_at ~= nil or (goal.status ~= "active" and goal.status ~= "paused") then return nil, "goal cannot be tweaked in status " .. tostring(goal.status) end
  return M.update(goal, { objective = objective }, true)
end

function M.set_task_status(goal, id, status, detail, now)
  return mutate(goal, function(copy)
    if copy.archived_at ~= nil or copy.status ~= "active" then return false, "tasks can only be changed on an active goal" end
    local function find(tasks)
      for _, task in ipairs(tasks or {}) do
        if task.id == id then return task end
        local found = find(task.subtasks); if found then return found end
      end
    end
    local task = find(copy.tasks)
    if not task then return false, "task not found: " .. tostring(id) end
    if task.status ~= "pending" then return false, "only pending tasks can be changed" end
    if status == "complete" then
      if not all_resolved(task.subtasks) then return false, "unresolved subtasks remain" end
      if task.verification_contract and task.verification_contract ~= "" and not nonempty(detail) then return false, "task verification evidence is required" end
      task.evidence, task.completed_at = detail, now
    elseif status == "skipped" then
      if not nonempty(detail) then return false, "skip reason is required" end
      local function skip(tree)
        for _, child in ipairs(tree or {}) do
          if child.status == "pending" then child.status, child.skip_reason = "skipped", "Parent skipped: " .. detail end
          skip(child.subtasks)
        end
      end
      skip(task.subtasks); task.skip_reason = detail
    else return false, "task status must be complete or skipped" end
    task.status = status
    return true
  end)
end

return M
