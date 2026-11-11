require("uji.builtin.defaults")
local root = require("uji.core.paths").config() .. "/../.."
uji.pack.add({ { dir = root } })
local tools = {}
local add = uji.tool.add
uji.tool.add = function(name, spec) tools[name] = spec; add(name, spec) end
local on = uji.on
local plan_guard
uji.on = function(event, handler, opts)
    if opts and opts.name == "spec-graph-planmode" then plan_guard = handler end
    return on(event, handler, opts)
end
require("spec_graph").setup()
uji.tool.add = add
uji.on = on
package.loaded["uji.core.run"] = function()
    require("uji.core.task").release()
    local ok, err = pcall(function()
        local function run(name, args) return tools[name].run(args) end
        local function has(text, needle) assert(text:find(needle, 1, true), needle .. " not in: " .. text) end
        local count = 0
        for _ in pairs(tools) do count = count + 1 end
        assert(count == 7)
        assert(tools.spec_get.policy == "allow")
        assert(tools.spec_update.policy == "ask")
        package.loaded["planmode"] = { active = function() return true end }
        assert(plan_guard({ name = "spec_create" }).deny)
        assert(not plan_guard({ name = "spec_get" }))
        package.loaded["planmode"] = nil

        has(run("spec_create", { path = "SPEC.md", id = "root", type = "goal-and-requirements", title = "Root: the goal", tags = { "a", "b" } }), "Created")
        has(uji.fs.read("SPEC.md"), 'title: "Root: the goal"')
        has(run("spec_create", { path = "sub/child.md", id = "child", type = "module-design", title = "Child", parent = "root", dependsOn = { "root" }, status = "active" }), "Created")
        has(run("spec_create", { path = "node_modules/x.md", id = "x", type = "module-design", title = "X" }), "ignored")
        has(run("spec_create", { path = "../x.md", id = "x", type = "module-design", title = "X" }), "inside the project")
        has(run("spec_create", { path = "SPEC.md", id = "y", type = "module-design", title = "X" }), "already exists")
        has(run("spec_create", { path = "z.md", id = "root", type = "module-design", title = "X" }), "in use")
        has(run("spec_get", { id = "child" }), "depends-on -> root (SPEC.md)")
        has(run("spec_get", { id = "root" }), "referenced by:")
        has(run("spec_get", { id = "nope" }), "Error: No spec")

        local file = assert(io.open("SPEC.md", "a"))
        file:write("\nNeedle 外部 🧪\n")
        file:close()
        has(run("spec_grep", { pattern = "needle" }), "外部 🧪")
        has(run("spec_grep", { pattern = "ne+dle", regex = true }), "SPEC.md:")
        has(run("spec_grep", { pattern = "(", regex = true }), "Invalid search pattern")
        has(run("spec_grep", { pattern = "Responsibility", type = "module-design" }), "sub/child.md")
        has(run("spec_grep", { pattern = "zzz" }), "No matches.")
        has(run("spec_graph", { root = "root", direction = "subtree" }), "child --parent--> root")
        has(run("spec_graph", { root = "child", direction = "ancestors" }), "root [goal")
        has(run("spec_graph", { root = "child", direction = "neighbors" }), "child --depends-on--> root")
        has(run("spec_validate", {}), "valid")

        local child = uji.fs.read("sub/child.md")
        uji.fs.write("sub/child.md", (child:gsub("title: Child\n", "# keep me\ntitle: Child\nowner: eric # trailing\n")))
        has(run("spec_update", { id = "child", set = { title = "Changed: yes" }, addList = { tags = { "t1" }, references = { "root" } }, removeList = { ["depends-on"] = { "root" } } }), "Updated")
        local after = uji.fs.read("sub/child.md")
        has(after, "# keep me")
        has(after, "owner: eric # trailing")
        has(after, 'title: "Changed: yes"')
        has(after, "tags: [t1]")
        assert(not after:find("depends-on", 1, true), after)
        has(run("spec_update", { id = "child", set = { id = "z" } }), "Cannot rename")
        has(run("spec_update", { id = "child", remove = { "type" } }), "protected")
        has(run("spec_update", { id = "child", set = { tags = "x" } }), "addList")

        uji.fs.write("a.md", "---\nid: a\ntype: task-spec\ntitle: A\nparent: b\nreferences: [missing]\n---\nbody\n")
        uji.fs.write("b.md", "---\nid: b\ntype: task-spec\ntitle: B\nparent: a\n---\n")
        uji.fs.write("dup.md", "---\nid: child\ntype: task-spec\ntitle: D\n---\n")
        uji.fs.write("legacy.md", "---\ntitle: nope\n---\nneedle\n")
        local report = run("spec_validate", {})
        has(report, "Duplicate ids")
        has(report, "[missing]")
        has(report, "Parent cycles")
        has(run("spec_grep", { pattern = "needle" }), "1 match")

        uji.fs.write("crlf.md", "\239\187\191---\r\nid: crlf\r\ntype: task-spec\r\ntitle: \"Q \\\"x\\\"\"\r\n---\r\nbody\r\n")
        has(run("spec_get", { id = "crlf" }), 'crlf [task-spec] — Q "x"')
        has(run("spec_update", { id = "crlf", addList = { tags = { "n" } } }), "Updated")
        local crlf = uji.fs.read("crlf.md")
        has(crlf, "tags: [n]\r\n---\r\nbody\r\n")
        assert(crlf:sub(1, 3) == "\239\187\191")
        has(run("spec_delete", { id = "crlf" }), "Deleted")
        has(run("spec_get", { id = "crlf" }), "Error:")

        local big = {}
        for index = 1, 3000 do big[#big + 1] = "bulk line " .. index end
        uji.fs.write("big.md", "---\nid: big\ntype: task-spec\ntitle: B\n---\n" .. table.concat(big, "\n"))
        has(run("spec_grep", { pattern = "bulk" }), "More matches: repeat spec_grep")
        print("passed real uji: seven tools, in-place edits, external edits, UTF-8, validation, bounds, policies")
    end)
    if not ok then io.stderr:write(tostring(err), "\n") end
    require("uji.sys").os.exit(ok and 0 or 1)
end
