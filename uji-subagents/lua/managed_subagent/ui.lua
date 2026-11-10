local ito = require("ito")

local active
local screen_default
local wrapped_views = setmetatable({}, { __mode = "k" })

local function enabled()
    local theme = require("uji.core.ui").theme.tokens
    return theme and theme.views and wrapped_views[theme.views[uji.ui.Screen]] or false
end

local function task_label(task)
    local name = task.agent and task.agent.name or "agent"
    local status = task.status or "unknown"
    local unread = active and active.unread[task.id] and " •" or ""
    return name .. " · " .. status .. unread
end

local function make_scroll(id)
    local scroll = ito.ScrollState({ follow = true })
    active.scrolls[id] = scroll
    return scroll
end

local function task_messages(task)
    local rows = {}
    local renderer = require("uji.core.ui.transcript.rows")
    local ui = require("uji.core.ui")
    local ctx = ito.theme()
    local scroll = active.scrolls[task.id] or make_scroll(task.id)
    local open = active.expanded[task.id] or {}
    active.expanded[task.id] = open
    local function toggle(message)
        return function()
            open[message] = not open[message]
            scroll.following = false
            active.revision.value = active.revision.value + 1
        end
    end
    local results, claimed = {}, {}
    local calls = {}
    for _, message in ipairs(task.messages or {}) do
        if message.type == "assistant" or message.type == "user" then calls = {} end
        for _, call in ipairs(message.tool_calls or {}) do
            calls[call.id] = call
        end
        if message.type == "tool" and calls[message.tool_call_id] then
            results[calls[message.tool_call_id]] = message
            claimed[message] = true
        end
    end
    local function append(message, answers)
        local views = renderer.entry(ctx, message, #rows > 0 and ctx.limits.message_gap or 0,
            ui.theme.show_thinking, false, open[message] == true, toggle(message), answers)
        for _, view in ipairs(views) do rows[#rows + 1] = view end
    end
    for _, message in ipairs(task.messages or {}) do
        if not claimed[message] then
            local answers = {}
            for index, call in ipairs(message.tool_calls or {}) do
                local result = results[call]
                answers[index] = result and {
                    message = result, expanded = open[result] == true, toggle = toggle(result),
                } or false
            end
            append(message, answers)
        end
    end
    if (task.partial and task.partial ~= "") or (task.reasoning and task.reasoning ~= "") then
        append({ type = "assistant", text = task.partial or "", reasoning = task.reasoning })
    end
    for _, steering in ipairs(task.steering or {}) do
        rows[#rows + 1] = uji.ui.SystemMessage({ text = "Steering · " .. steering.status .. " · " .. steering.text })
    end
    if task.error then
        rows[#rows + 1] = uji.ui.ErrorMessage({ text = tostring(task.error) })
    end
    return rows
end

local function select_task(id)
    if not active then return end
    if id and not enabled() then
        uji.notify("Agent conversations require the managed-subagent theme wrapper")
        return
    end
    active.selected = id
    active.selection_changed = true
    active.editor = nil
    active.unread[id or "main"] = nil
    active.revision.value = active.revision.value + 1
end

local function sidebar(tasks)
    local rows = { ito.Text("Agents  /agents"):bold() }
    rows[#rows + 1] = ito.Text("Main conversation" .. (active.unread.main and " •" or ""))
        :on_tap(function() select_task(nil) end)
    for _, task in ipairs(tasks) do
        local id = task.id
        local working = task.status == "starting" or task.status == "running" or task.status == "stopping"
        local name = ito.Text(task.agent and task.agent.name or "agent")
        if active.selected == id then name = name:reverse() end
        local label = ito.HStack({
            working and ito.Spinner():padding({ trailing = 1 }) or false,
            name:grow(),
            ito.Text((working and "" or " · " .. (task.status or "unknown"))
                .. (active.unread[id] and " •" or "")):dim(),
        }):height(1)
        rows[#rows + 1] = label:on_tap(function() select_task(id) end)
    end
    return ito.ScrollView(ito.VStack(rows)):width(30):border(ito.theme().borders.plain)
end

local function main_screen(screen, tasks, width)
    local content = ito.VStack({
        screen.greeting(), screen.transcript():grow(), screen.activity():padding({ vertical = 1 }),
        screen.modals(), ito.ToolbarItems(ito.ToolbarPlacement.keyboard),
        screen.composer():border(ito.theme().borders.plain, { edges = ito.Edges.horizontal }),
        ito.ToolbarItems(ito.ToolbarPlacement.bottom_bar),
    }):grow()
    active.content = content
    return ito.HStack({ content, width >= 100 and sidebar(tasks) or false }):grow()
end

local function build_screen(screen, width)
    local state = active
    if not state then return screen_default(screen) end
    local revision = state.revision.value
    local tasks = state.manager:list() or {}
    local function chrome(content)
        local placement = ito.ToolbarPlacement
        return ito.VStack({
            ito.HStack({ ito.ToolbarItems(placement.top_bar_leading, ito.HStack), ito.Spacer(),
                ito.ToolbarItems(placement.top_bar_trailing, ito.HStack) }),
            content:grow(),
        }):opaque():background(ito.theme().styles.screen)
    end
    if require("uji.core.ui"):mode() == "confirm" then
        return chrome(main_screen(screen, tasks, width))
    end
    local selected
    for _, task in ipairs(tasks) do
        if task.id == state.selected then
            selected = task
            break
        end
    end
    local side = width >= 100 and sidebar(tasks) or false
    if not selected then return chrome(main_screen(screen, tasks, width)) end
    local draft = state.drafts[selected.id]
    local transcript = ito.VStack(task_messages(selected))
    state.content = transcript
    local composer = ito.TextField(draft):id("managed-steering", selected.id)
        :placeholder("Steer " .. (selected.agent and selected.agent.name or "agent") .. "…"):focused()
        :on_submit(function(text)
            if text == "" then return end
            if text == "/agent-main" or text == "/agents" or text == "/agent-stop" then
                draft.value = ""
                uji.task.spawn(function()
                    if text == "/agent-main" then
                        select_task(nil)
                    elseif text == "/agents" then
                        active.commands.agents()
                    else
                        uji.notify(state.manager:stop(selected.id))
                    end
                end)
                return
            end
            uji.task.spawn(function()
                local ok, result = pcall(function() return state.manager:steer(selected.id, text, "ui") end)
                if not ok or (type(result) == "string" and result:match("^error:")) then
                    uji.notify(tostring(result))
                elseif draft.value == text then
                    draft.value = ""
                end
            end)
        end)
    state.editor = composer
    return chrome(ito.HStack({
        ito.VStack({
            ito.Text("← Main thread (Alt-M)"):on_tap(function() select_task(nil) end),
            ito.Text(selected.id .. " · " .. selected.agent.name .. " · " .. selected.status):bold(),
            ito.ScrollView(transcript):state(state.scrolls[selected.id] or make_scroll(selected.id)):grow(),
            screen.modals(),
            ito.Text("Steer this agent · /agent-stop to cancel"):dim(),
            composer,
            ito.ToolbarItems(ito.ToolbarPlacement.keyboard), ito.ToolbarItems(ito.ToolbarPlacement.bottom_bar),
        }):grow(),
        side,
    }))
end

local M = {}

function M.setup(manager, opts)
    opts = opts or {}
    if opts.skip == true then return end
    active = { manager = manager, selected = nil, revision = ito.state(0), drafts = {}, scrolls = {}, expanded = {}, unread = {}, commands = {} }
    local function synchronize(task)
        local present = {}
        for _, item in ipairs(manager:list()) do
            present[item.id] = true
            if not active.drafts[item.id] then active.drafts[item.id] = ito.state("") end
        end
        for _, collection in ipairs({ active.drafts, active.scrolls, active.expanded, active.unread }) do
            for id in pairs(collection) do
                if id ~= "main" and not present[id] then collection[id] = nil end
            end
        end
        if active.selected and not present[active.selected] then select_task(nil) end
        if task and active.selected ~= task.id then active.unread[task.id] = true end
        active.revision.value = active.revision.value + 1
    end
    synchronize()
    manager:subscribe(synchronize)
    require("managed_subagent.input").install(function()
        if not enabled() and active.selected then
            active.selected, active.editor, active.selection_changed = nil, nil, true
        end
        return active
    end, function() select_task(nil) end, function()
        if not active or not enabled() then return end
        local ui = require("uji.core.ui")
        local width = ui.screen:size()
        if width < 100 or ui:mode() ~= "normal" then return end
        return active.content and active.content.inner and active.content.inner.width
    end)
    uji.on("message_appended", function()
        if active and active.selected then
            active.unread.main = true
            active.revision.value = active.revision.value + 1
        end
    end)
    local function picker(on_select)
        local items = manager:list() or {}
        table.insert(items, 1, { id = false, agent = { name = "Main conversation" }, status = "main" })
        uji.ui.select({ title = "Agents", items = items, label = task_label }, function(task)
            if task then on_select(task) end
        end)
    end
    local function agents_picker()
        picker(function(task) select_task(task.id or nil) end)
    end
    active.commands.agents = agents_picker
    uji.command.add("agents", { desc = "choose a managed agent", handler = agents_picker })
    uji.command.add("agent-main", { desc = "return to the main conversation", handler = function() select_task(nil) end })
    uji.command.add("agent-stop", {
        desc = "stop a managed agent",
        handler = function(args)
            local id = args and args:match("%S+")
            local function stop(selected)
                if not selected.id then return end
                local ok, result = pcall(function() return manager:stop(selected.id) end)
                if not ok or (type(result) == "string" and result:match("^error:")) then uji.notify(tostring(result)) end
            end
            if not id then return picker(stop) end
            local ok, result = pcall(function() return manager:stop(id) end)
            if not ok or (type(result) == "string" and result:match("^error:")) then uji.notify(tostring(result)) end
        end
    })
    uji.keymap.add("normal", "<A-a>", agents_picker)
    uji.keymap.add("normal", "<A-m>", function() select_task(nil) end)
end

function M.wrap_theme(theme)
    local wrapped = {}
    for key, value in pairs(theme) do wrapped[key] = value end
    wrapped.views = {}
    for key, value in pairs(theme.views or {}) do wrapped.views[key] = value end
    screen_default = theme.views and theme.views[uji.ui.Screen]
    wrapped.views[uji.ui.Screen] = function(screen)
        return ito.SubcomposeLayout(function(room) return build_screen(screen, room.width) end)
    end
    wrapped_views[wrapped.views[uji.ui.Screen]] = true
    return wrapped
end

return M
