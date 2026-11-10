require("uji.builtin.defaults")
local root = require("uji.core.paths").config() .. "/../.."
uji.pack.add({ { dir = root } })
local tools = {}
local plan_guard
local on = uji.on
uji.on = function(event, handler, opts)
    if opts and opts.name == "spec-graph-planmode" then plan_guard = handler end
    return on(event, handler, opts)
end
local add = uji.tool.add
uji.tool.add = function(name, spec)
    tools[name] = spec
    add(name, spec)
end
require("spec_graph").setup({ timeout = 10 })
uji.tool.add = add
uji.on = on
uji.provider.add({
    id = "spec-test", name = "Spec test", api = uji.api.openai(), base_url = "http://127.0.0.1:1",
    models = { { id = "fake", context = 10000 } },
})
package.loaded["uji.core.run"] = function()
    require("uji.core.task").release()
    local ok, err = pcall(function()
        local function run(name, args)
            local result
            local cancel = tools[name].run(args, { done = function(text) result = text end })
            if type(cancel) == "string" then return cancel end
            local deadline = uji.os.clock() + 15
            while not result and uji.os.clock() < deadline do uji.sleep(0.01) end
            assert(result, "tool timed out: " .. name)
            return result
        end
        local count = 0
        for _ in pairs(tools) do count = count + 1 end
        assert(count == 7)
        assert(tools.spec_get.policy == "allow")
        assert(tools.spec_update.policy == "ask")
        package.loaded["planmode"] = { active = function() return true end }
        assert(plan_guard({ name = "spec_create" }).deny)
        assert(plan_guard({ name = "spec_update" }).deny)
        assert(plan_guard({ name = "spec_delete" }).deny)
        assert(not plan_guard({ name = "spec_get" }))
        package.loaded["planmode"] = nil
        assert(not plan_guard({ name = "spec_create" }))
        assert(run("spec_create", { path = "SPEC.md", id = "root", type = "module-design", title = "Root" }):find("Created", 1, true))
        assert(run("spec_get", { id = "root" }):find("Root", 1, true))
        local file = assert(io.open("SPEC.md", "a"))
        file:write("\nneedle 外部 🧪\n")
        file:close()
        assert(run("spec_grep", { pattern = "needle" }):find("外部 🧪", 1, true))
        assert(run("spec_graph", { root = "root", direction = "subtree" }):find("root", 1, true))
        assert(run("spec_update", { id = "root", set = { title = "Changed" } }):find("Updated", 1, true))
        assert(run("spec_get", { id = "root" }):find("Changed", 1, true))
        local large = string.rep("🧪", 8000)
        assert(run("spec_update", { id = "root", set = { title = large } }):find("Updated", 1, true))
        assert(run("spec_get", { id = "root" }):find(large, 1, true), "chunked output must reassemble byte-exactly")
        local completed = false
        local cancel = tools.spec_get.run({ id = "root" }, { done = function() completed = true end })
        assert(type(cancel) == "function")
        cancel()
        assert(not completed, "cancelled calls must not deliver results")
        assert(run("spec_get", { id = "root" }):find(large, 1, true), "worker must restart after cancellation")
        assert(not run("spec_validate", {}):find("Error:", 1, true))
        assert(run("spec_delete", { id = "root" }):find("Deleted", 1, true))
        assert(run("spec_get", { id = "root" }):find("Error:", 1, true))
        assert(run("spec_get", {}):find("Invalid parameters", 1, true))
        uji.tool.add = function(name, spec) tools[name] = spec; add(name, spec) end
        require("spec_graph").setup({ bun = "/nonexistent/uji-spec-graph-bun", timeout = 2 })
        uji.tool.add = add
        assert(run("spec_get", { id = "root" }):find("Error:", 1, true))
        print("passed real uji: seven tools, worker reuse, external edits, UTF-8, errors, missing runtime, policies")
    end)
    uji.emit("before_quit", {})
    if not ok then io.stderr:write(tostring(err), "\n") end
    require("uji.sys").os.exit(ok and 0 or 1)
end
