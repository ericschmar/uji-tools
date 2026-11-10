local store = ...
local ito = require("ito")
local app = require("uji.core.app")
local ui = require("uji.core.ui")
local keys = require("uji.core.ui.keys")
local plugin = require("managed_subagent.ui")
local child = {
    id = "agent-1",
    agent = { name = "scout" },
    task = "Inspect the test",
    status = "running",
    messages = {
        { type = "user", text = "CHILD_PROMPT" },
        { type = "assistant", text = "**FORMATTED_REPLY**", tool_calls = {
            { id = "read-child", name = "read_file", arguments = '{"path":"CHILD_FILE.lua","offset":1,"limit":10}' },
        } },
        { type = "tool", name = "read_file", tool_call_id = "read-child",
            content = "CHILD_RAW_OUTPUT", summary = "CHILD_SUMMARY" },
    },
    partial = "CHILD_LIVE",
    steering = {}
}
local second = {
    id = "agent-2", agent = { name = "worker" }, task = "Second task", status = "running",
    messages = {}, partial = "SECOND_LIVE", steering = {}
}
local received, listeners, stopped = {}, {}, {}
local reject = false
local manager = {}
function manager:list() return { child, second } end

function manager:get(id) return id == child.id and child or id == second.id and second or nil end

function manager:subscribe(fn) listeners[#listeners + 1] = fn end

function manager:steer(id, text, source)
    if reject then return "error: rejected for test" end
    received[#received + 1] = { id = id, text = text, source = source }
    return "queued"
end

function manager:stop(id)
    stopped[#stopped + 1] = id
    return "stopped"
end

local function theme()
    local path = uji.os.env("UJI_TEST_THEME")
    return path and assert(loadfile(path))() or require("uji.themes.default")()
end
app.attach(store:create_session("UI test"))
plugin.setup(manager, {})
uji.ui.configure({ theme = plugin.wrap_theme(theme()) })
ui:open()
ui:listen()
ui:set_input("MAIN_DRAFT")
local function rows()
    ui:paint()
    local diagnostics = require("uji.core.diagnostics").list()
    assert(#diagnostics == 0, uji.json.encode(diagnostics))
    local _, height = ui.screen:size()
    local result = {}
    for row = 0, height - 1 do result[#result + 1] = ui.screen:text(row) end
    return result
end
local last_screen
local function shown(text)
    last_screen = table.concat(rows(), "\n")
    return last_screen:find(text, 1, true)
end
local function click(text)
    uji.sleep(0.5)
    for row, line in ipairs(rows()) do
        local at = line:find(text, 1, true)
        if at then
            local col = ito.text.width and ito.text.width(line:sub(1, at - 1)) or uji.width(line:sub(1, at - 1))
            ui:mouse({ kind = "down", button = "left", row = row - 1, col = col })
            ui:mouse({ kind = "up", button = "left", row = row - 1, col = col })
            return
        end
    end
    error("missing clickable text: " .. text .. "\n" .. table.concat(rows(), "\n"))
end
assert(shown("Main conversation"), "main sidebar entry missing")
assert(shown("MAIN_DRAFT"), "parent draft missing")
assert(not shown("Inspect the test"), "sidebar must not show task details")
assert(not shown("agent-2"), "sidebar must not show task IDs")
local sidebar_rows = rows()
local scout_row, worker_row
for index, line in ipairs(sidebar_rows) do
    if line:find("scout", 1, true) then scout_row = index end
    if line:find("worker", 1, true) then worker_row = index end
end
assert(scout_row and worker_row == scout_row + 1, "agents must occupy consecutive single lines")
local frames = ui.theme.tokens.symbols.spinner
local function spinner_at(line)
    for _, frame in ipairs(frames) do
        if line:find(frame, 1, true) then return frame end
    end
end
local first_frame = spinner_at(sidebar_rows[scout_row])
assert(first_frame, "running agents must use the theme spinner")
uji.sleep(ui.theme.tokens.limits.spinner_interval * 1.5)
assert(spinner_at(rows()[scout_row]) ~= first_frame, "agent spinner must animate")
click("scout")
assert(shown("CHILD_LIVE"), "child live view did not open")
assert(shown("CHILD_PROMPT"), "saved child messages missing")
assert(shown("FORMATTED_REPLY") and not shown("**FORMATTED_REPLY**"), "assistant markdown must be rendered")
assert(shown("CHILD_FILE.lua") and not shown('"offset"'), "tool calls must use their formatted description")
assert(shown("CHILD_SUMMARY") and not shown("CHILD_RAW_OUTPUT"), "tool results must start folded")
click("CHILD_SUMMARY")
assert(shown("CHILD_RAW_OUTPUT"), "tool results must expand on click")
click("CHILD_RAW_OUTPUT")
assert(shown("CHILD_SUMMARY"), "tool results must fold on click")
local function drag_copy(backwards, into_sidebar)
    local snapshot = rows()
    local first, last, start_col, end_col
    for index, line in ipairs(snapshot) do
        local prompt = line:find("CHILD_PROMPT", 1, true)
        local live = line:find("CHILD_LIVE", 1, true)
        if prompt then first, start_col = index - 1, ito.text.width(line:sub(1, prompt - 1)) end
        if live then last, end_col = index - 1, ito.text.width(line:sub(1, live - 1)) + #"CHILD_LIVE" end
    end
    assert(first and last, "selection endpoints must be visible")
    local copied, copy = nil, ui.copy
    ui.copy = function(_, text) copied = text end
    local from = { row = first, col = start_col }
    local to = { row = last, col = into_sidebar and 119 or end_col }
    if backwards then from, to = to, from end
    uji.sleep(0.55)
    ui:mouse({ kind = "down", button = "left", row = from.row, col = from.col })
    ui:mouse({ kind = "drag", button = "left", row = to.row, col = to.col })
    ui:paint()
    ui:mouse({ kind = "up", button = "left", row = to.row, col = to.col })
    ui.copy = copy
    assert(copied and copied:find("CHILD_PROMPT", 1, true) and copied:find("CHILD_LIVE", 1, true),
        "multi-line copy must retain transcript text")
    assert(not copied:find("│", 1, true) and not copied:find("scout", 1, true)
        and not copied:find("Main conversation", 1, true), "transcript copy must exclude sidebar: " .. copied)
    ui.window.selection:clear()
end
drag_copy(false)
drag_copy(true)
drag_copy(false, true)
for char in ("STEER_FROM_VIEW"):gmatch(".") do ui:key(keys.chord(char)) end
ui:key(keys.chord("enter"))
uji.sleep(0.05)
assert(received[1] and received[1].text == "STEER_FROM_VIEW" and received[1].source == "ui",
    "child input must steer selected agent")
assert(ui.composer:text() == "MAIN_DRAFT", "child input must not mutate the parent draft")
reject = true
for char in ("FAILED_DRAFT"):gmatch(".") do ui:key(keys.chord(char)) end
ui:key(keys.chord("enter"))
uji.sleep(0.05)
assert(shown("FAILED_DRAFT"), "failed steering must preserve its draft")
assert(ui.composer:text() == "MAIN_DRAFT", "failed steering must not edit the parent draft")
reject = false
ui:key(keys.parse("<C-u>"))
for char in ("CHILD_DRAFT"):gmatch(".") do ui:key(keys.chord(char)) end
assert(shown("CHILD_DRAFT"), "draft missing before switching\n" .. last_screen)
ui:key(keys.parse("<A-m>"))
uji.sleep(0.05)
assert(shown("MAIN_DRAFT"), "main shortcut did not return to parent")
click("scout")
assert(shown("CHILD_DRAFT"), "child draft should survive switching\n" .. last_screen)
click("worker")
assert(shown("SECOND_LIVE"), "second child must open")
assert(not shown("CHILD_DRAFT"), "child drafts must not leak between agents")
for char in ("SECOND_DRAFT"):gmatch(".") do ui:key(keys.chord(char)) end
assert(shown("SECOND_DRAFT"), "second child composer must receive input")
click("scout")
assert(shown("CHILD_DRAFT"), "first child draft must survive visiting another agent")
click("worker")
assert(shown("SECOND_DRAFT"), "second child draft must survive switching")
click("Main conversation")
ui:key(keys.chord("!"))
assert(ui.composer:text() == "MAIN_DRAFT!", "input immediately after switching to main must reach the parent")
ui:key(keys.chord("backspace"))
click("scout")
ui:handle({ type = "paste", text = " PASTED_TEXT\nSECOND_LINE" })
assert(shown("PASTED_TEXT"), "terminal paste must reach the child composer")
assert(ui.composer:text() == "MAIN_DRAFT", "paste must not change the hidden parent")
ui:key(keys.parse("<C-u>"))
assert(not shown("CHILD_DRAFT"), "editing shortcuts must edit the child composer")
assert(ui.composer:text() == "MAIN_DRAFT", "editing shortcuts must not edit the parent")
ui:key(keys.chord("esc"))
assert(shown("MAIN_DRAFT"), "Escape should return to main rather than interrupt it")
click("scout")
local Confirm = require("uji.core.ui.views.confirm")
local approval = ui:present(Confirm({ title = "PARENT_APPROVAL", body = "Main thread needs approval" }))
assert(shown("PARENT_APPROVAL"), "parent approvals must remain visible from child view")
ui:key(keys.chord("y"))
assert(approval:wait() == true, "approval keys must reach the parent confirmation")
assert(shown("CHILD_LIVE"), "closing approval should restore child view")
assert(ui.composer:text() == "MAIN_DRAFT", "approval input must not change the parent draft")
assert(#received == 1, "approval input must not steer the child")
local denied = ui:present(Confirm({ title = "PARENT_DENIAL", body = "Deny this request" }))
assert(shown("PARENT_DENIAL"), "second parent confirmation must render")
ui:key(keys.chord("esc"))
assert(denied:wait() == false, "Escape must deny the modal rather than switch conversations")
assert(shown("CHILD_LIVE"), "denying approval must restore the child view")
local select = uji.ui.select
uji.ui.select = function(_, callback) callback(child) end
local commands = require("uji.core.command")
commands.commands:get("agent-stop").handler("")
assert(stopped[1] == child.id, "stop picker must stop the picked agent")
commands.commands:get("agent-main").handler("")
commands.commands:get("agents").handler("")
assert(shown("CHILD_LIVE"), "agents command must select the picked child")
uji.ui.configure({ theme = "default" })
assert(shown("MAIN_DRAFT"), "unwrapped theme must show the main composer")
commands.commands:get("agents").handler("")
ui:key(keys.chord("X"))
assert(ui.composer:text() == "MAIN_DRAFTX", "unwrapped theme input must remain with the visible parent")
ui:set_input("MAIN_DRAFT")
uji.ui.configure({ theme = plugin.wrap_theme(theme()) })
commands.commands:get("agents").handler("")
uji.ui.select = select
assert(shown("CHILD_LIVE"), "restoring wrapper must allow child selection")
uji.sleep(ui.theme.tokens.limits.flash + 0.05)
ui.screen:clear()
local terminal = ui.screen
local narrow = setmetatable({ size = function() return 70, 32 end }, {
    __index = function(_, key)
        return function(_, ...) return terminal[key](terminal, ...) end
    end
})
ui.screen, ui.window.screen = narrow, narrow
assert(not shown("Main conversation"), "narrow layout should hide the sidebar")
assert(shown("Main thread"), "narrow child view must still offer return to main\n" .. last_screen)
drag_copy(false)
local diagnostics = require("uji.core.diagnostics")
assert(#diagnostics.list() == 0, "rendering must not produce diagnostics")
io.stdout:write(
"\npassed terminal UI: right sidebar, live view, steering input, drafts, return shortcut, approval, narrow layout\n")
