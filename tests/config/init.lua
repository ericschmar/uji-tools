require("uji.builtin.defaults")
local root = assert(uji.os.env("UJI_TOOLS_TEST_ROOT"))
uji.pack.add({ { dir = root } })
local tools = require("uji_tools")
assert(tools.path("uji-spec-graph/skills") == root .. "/uji-spec-graph/skills")
assert(not pcall(tools.path, "../outside"))
assert(not pcall(tools.path, "/outside"))
assert(not pcall(tools.path, "..\\outside"))
local core_tools = require("uji.core.tool")
assert(not core_tools.get("goal_set"), "loading the collection must not enable plugins")
assert(tools.setup() == tools)
local count = #uji.pack.list()
assert(tools.setup() == tools and #uji.pack.list() == count, "mounting must be idempotent")
for _, name in ipairs({ "uji-subagents", "uji-goal", "uji-spec-graph" }) do
    local found = false
    for _, directory in ipairs(uji.pack.list()) do
        if directory == root .. "/" .. name then found = true end
    end
    assert(found, "missing bundled pack: " .. name)
end
assert(not core_tools.get("goal_set"), "mounting the collection must not enable plugins")
assert(type(require("managed_subagent").setup) == "function")
assert(type(require("managed_subagent.manager").new) == "function")
require("goal").setup({ toolbar = false })
require("spec_graph").setup({})
assert(core_tools.get("goal_set") and core_tools.get("spec_get"), "explicit setup must register tools")
assert(require("uji.core.context").functions:get("goal")() == nil, "loading a pack must not opt into goal work")
assert(io.open(tools.path("uji-spec-graph/skills/spec-graph/SKILL.md"), "r")):close()
assert(io.open(tools.path("pocketbase-mcp/package.json"), "r")):close()
package.loaded["uji.core.run"] = function()
    local diagnostics = require("uji.core.diagnostics").list()
    assert(#diagnostics == 0, uji.json.encode(diagnostics))
    io.stdout:write("passed root pack: relocated checkout, bundled modules, idempotence, opt-in setup and portable resource paths\n")
    require("uji.sys").os.exit(0)
end
