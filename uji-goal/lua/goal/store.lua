local M = {}

local function filename(directory)
  if type(directory) ~= "string" or directory == "" then return nil, "directory is required" end
  local digest, hex = uji.sha256(directory), {}
  for index = 1, #digest do hex[index] = string.format("%02x", digest:byte(index)) end
  return "goal-" .. table.concat(hex) .. ".json"
end

local function nonempty(value)
  return type(value) == "string" and value:match("%S") ~= nil
end

local function text_fields(record, fields)
  for _, name in ipairs(fields) do
    if record[name] ~= nil and type(record[name]) ~= "string" then return false end
  end
  return true
end

local function valid_tasks(tasks)
  if type(tasks) ~= "table" then return false end
  local ids, titles = {}, {}
  local function visit(list, depth)
    if type(list) ~= "table" or (depth > 8 and next(list) ~= nil) then return false end
    local count, maximum = 0, 0
    for key in pairs(list) do
      if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false end
      count = count + 1; if key > maximum then maximum = key end
    end
    if count ~= maximum then return false end
    for _, task in ipairs(list) do
      if type(task) ~= "table" or not nonempty(task.id) or not nonempty(task.title)
        or (task.status ~= "pending" and task.status ~= "complete" and task.status ~= "skipped")
        or not text_fields(task, { "verification_contract", "evidence", "skip_reason", "completed_at" }) then return false end
      if task.status == "skipped" and not nonempty(task.skip_reason) then return false end
      if task.status == "complete" and nonempty(task.verification_contract) and not nonempty(task.evidence) then return false end
      if ids[task.id] then return false end
      ids[task.id] = true
      local title = task.title:lower():match("^%s*(.-)%s*$")
      if titles[title] then return false end
      titles[title] = true
      if task.subtasks ~= nil and not visit(task.subtasks, depth + 1) then return false end
    end
    return true
  end
  return visit(tasks, 1)
end

local function valid_record(record, directory)
  if type(record) ~= "table" or record.version ~= 1 or record.directory ~= directory
    or type(record.goals) ~= "table" or type(record.settings) ~= "table" then
    return nil, "invalid or mismatched goal store record"
  end
  if record.focused_id ~= nil and (not nonempty(record.focused_id) or record.goals[record.focused_id] == nil) then
    return nil, "invalid focused goal id"
  end
  for id, goal in pairs(record.goals) do
    if type(id) ~= "string" or type(goal) ~= "table" or goal.id ~= id or not nonempty(goal.objective)
      or (goal.status ~= "active" and goal.status ~= "paused" and goal.status ~= "complete" and goal.status ~= "aborted" and goal.status ~= "archived")
      or type(goal.auto_continue) ~= "boolean" or type(goal.sisyphus) ~= "boolean"
      or (goal.archived_at ~= nil and not nonempty(goal.archived_at))
      or not text_fields(goal, { "created_at", "updated_at", "verification_contract", "completion_summary", "verification_summary", "pause_reason", "abort_reason", "suggested_action" })
      or not valid_tasks(goal.tasks) then return nil, "invalid goal record: " .. tostring(id) end
    if goal.usage ~= nil and (type(goal.usage) ~= "table" or type(goal.usage.tokens_used) ~= "number" or type(goal.usage.active_seconds) ~= "number") then return nil, "invalid goal usage: " .. id end
  end
  for key, value in pairs(record.settings) do
    if key == "auto_continue" and type(value) ~= "boolean" then return nil, "invalid auto_continue setting" end
    if key == "max_auto_turns" and (type(value) ~= "number" or value < 0 or value % 1 ~= 0) then return nil, "invalid max_auto_turns setting" end
  end
  return record
end

function M.filename(directory) return filename(directory) end
function M.empty(directory) return { version = 1, directory = directory, goals = {}, focused_id = nil, settings = {} } end

function M.open(directory, callback)
  local name, err = filename(directory)
  if not name then callback(nil, err); return end
  uji.data.read(name, function(text, read_err)
    if text == nil then
      local message = tostring(read_err or "")
      if message:lower():match("not found") or message:lower():match("no such file") or message:lower():match("does not exist") then callback(M.empty(directory))
      else callback(nil, "read goal store: " .. message) end
      return
    end
    local ok, record = pcall(uji.json.decode, text)
    if not ok then callback(nil, "decode goal store: " .. tostring(record)); return end
    local checked, validation_err = valid_record(record, directory)
    callback(checked, validation_err)
  end)
end

local function serializable(state)
  local copy = {}
  for key, value in pairs(state) do copy[key] = value end
  copy.goals = {}
  for id, goal in pairs(state.goals) do
    local saved = {}
    for key, value in pairs(goal) do saved[key] = value end
    local function mark_tasks(tasks)
      local result = {}
      for index, task in ipairs(tasks or {}) do
        local copied_task = {}
        for key, value in pairs(task) do copied_task[key] = value end
        copied_task.subtasks = mark_tasks(task.subtasks or {})
        result[index] = copied_task
      end
      return uji.json.array(result)
    end
    saved.tasks = mark_tasks(goal.tasks or {})
    copy.goals[id] = saved
  end
  return copy
end

function M.save(state, callback)
  callback = callback or function() end
  local checked, err = valid_record(state, state and state.directory)
  if not checked then callback(nil, err); return end
  local name
  name, err = filename(state.directory)
  if not name then callback(nil, err); return end
  local ok, text = pcall(uji.json.encode, serializable(state))
  if not ok then callback(nil, "encode goal store: " .. tostring(text)); return end
  uji.data.write(name, text, function(written, write_err)
    if not written then callback(nil, "write goal store: " .. tostring(write_err or "unknown error")); return end
    callback(true)
  end)
end

return M
