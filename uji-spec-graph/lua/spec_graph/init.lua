local model = require("spec_graph.model")

local M = {}

local IGNORED_DIRS = {
    ["node_modules"] = true, [".git"] = true, ["dist"] = true, ["build"] = true, [".claude"] = true,
    [".superpowers"] = true, [".gsd"] = true, [".mockups"] = true, [".playwright-mcp"] = true,
}
local MAX_BYTES = 50 * 1024
local MAX_LINES = 2000
local DEFAULT_LIMIT = 200

local SCAFFOLD_HEADINGS = {
    ["module-design"] = { "Responsibility", "Boundary" },
    ["submodule-design"] = { "Responsibility", "Boundary" },
    ["architecture-design"] = { "Drivers", "Decisions", "Invariants", "Out of scope" },
    ["goal-and-requirements"] = { "Goal", "Scope" },
    ["task-spec"] = { "Purpose", "Open items" },
}

local RULE = table.concat({
    "Specs are this project's ground truth.",
    "- Consult the relevant spec when work is governed by or may alter a documented boundary, contract, invariant, behavior, or architecture decision; localized work need not read unrelated specs.",
    "- Treat applicable decisions and contracts as authoritative; reconcile contradictions instead of diverging.",
    "- When a change alters a boundary, contract, invariant, or decision, update the owning spec as part of that change.",
}, "\n")

local WRITING = { spec_create = true, spec_update = true, spec_delete = true }

local function project_root()
    local ok, info = pcall(uji.session.info)
    if ok and type(info) == "table" and type(info.directory) == "string" and info.directory ~= "" then
        return (info.directory:gsub("/+$", ""))
    end
    return uji.os.cwd()
end

local function walk(directory, found)
    local entries = uji.fs.list(directory)
    if not entries then return end
    for _, entry in ipairs(entries) do
        local name = entry.name
        if entry.type == "dir" then
            if not IGNORED_DIRS[name] then walk(directory .. "/" .. name, found) end
        elseif entry.type == "file" and name:sub(-3) == ".md" then
            found[#found + 1] = directory .. "/" .. name
        end
    end
end

-- Reads every spec under root. The filesystem is read on every call, so
-- external edits are always seen.
local function scan(root)
    local files = {}
    walk(root, files)
    local specs = {}
    for _, abs in ipairs(files) do
        local content = uji.fs.read(abs)
        if content then
            local frontmatter = model.parse_file(content)
            if model.is_spec(frontmatter) then
                specs[#specs + 1] = { abs = abs, path = abs:sub(#root + 2), content = content, frontmatter = frontmatter }
            end
        end
    end
    return specs
end

local function graph_of(specs)
    local entries = {}
    for _, spec in ipairs(specs) do entries[#entries + 1] = { path = spec.path, frontmatter = spec.frontmatter } end
    return model.build_graph(entries)
end

local function find_spec(specs, id)
    for _, spec in ipairs(specs) do
        if spec.frontmatter.id == id then return spec end
    end
end

local function bounded(text)
    local lines = model.split_lines(text)
    if #text <= MAX_BYTES and #lines <= MAX_LINES then return text end
    local note
    local path = os.tmpname() .. ".txt"
    if uji.fs.write(path, text) then
        note = "Full output saved to: " .. path .. "\nTemporary file; may expire. Read only relevant offset/limit ranges."
    else
        note = "Full output unavailable: temporary-file capture failed. Narrow the query."
    end
    local footer = string.format("\n\n[Output truncated: %d lines, %d bytes total. %s]", #lines, #text, note)
    local keep, size = {}, 0
    local budget = MAX_BYTES - #footer
    for index = 1, math.min(#lines, MAX_LINES - 4) do
        size = size + #lines[index] + 1
        if size > budget then break end
        keep[#keep + 1] = lines[index]
    end
    return table.concat(keep, "\n") .. footer
end

local function failure(message)
    return bounded("Error: " .. message)
end

local function describe(node)
    return string.format("%s [%s]%s", node.id, node.type, node.title and (" — " .. node.title) or "")
end

local function check_path(root, path)
    if path:match("^%s*$") then return nil, "Path must not be empty." end
    if path:sub(1, 1) == "/" or path:match("^%a:") or path:find("\\", 1, true) then
        return nil, "Path must be root-relative, not absolute: " .. path
    end
    if path:sub(-3) ~= ".md" then return nil, "Spec files must end in .md: " .. path end
    local segments = {}
    for segment in path:gmatch("[^/]+") do
        if segment == ".." then return nil, "Path must stay inside the project root: " .. path end
        if segment ~= "." then
            if IGNORED_DIRS[segment:lower()] then
                return nil, string.format('Path is inside an ignored directory ("%s") and would not be indexed: %s', segment, path)
            end
            segments[#segments + 1] = segment
        end
    end
    local walked = root
    for _, segment in ipairs(segments) do
        local listed = uji.fs.list(walked)
        if listed then
            local kind
            for _, entry in ipairs(listed) do
                if entry.name == segment then kind = entry.type end
            end
            if kind == "link" then
                return nil, "Path passes through a symlink, which the index never follows: " .. path
            end
            if not kind then break end
        else
            break
        end
        walked = walked .. "/" .. segment
    end
    return table.concat(segments, "/"), nil
end

local handlers = {}

function handlers.spec_get(args, root)
    local specs = scan(root)
    local graph = graph_of(specs)
    local node = graph.nodes[args.id]
    if not node then return failure(string.format('No spec with id "%s".', args.id)) end
    local links, reverse = {}, {}
    local function link_line(kind, target)
        local found = graph.nodes[target]
        return string.format("  %s -> %s%s", kind, target, found and (" (" .. found.path .. ")") or " (missing)")
    end
    for _, kind in ipairs(model.LINK_KINDS) do
        for _, target in ipairs(model.link_targets(node.frontmatter, kind)) do links[#links + 1] = link_line(kind, target) end
    end
    for _, kind in ipairs(model.LINK_KINDS) do
        for _, source in ipairs(graph.reverse[kind][args.id] or {}) do reverse[#reverse + 1] = link_line(kind, source) end
    end
    return bounded(table.concat({
        describe(node),
        "path: " .. node.path,
        #links > 0 and ("links:\n" .. table.concat(links, "\n")) or "links: (none)",
        #reverse > 0 and ("referenced by:\n" .. table.concat(reverse, "\n")) or "referenced by: (none)",
    }, "\n"))
end

function handlers.spec_grep(args, root)
    local offset = args.offset or 0
    if type(offset) ~= "number" or offset < 0 or offset ~= math.floor(offset) then
        return failure("Use a nonnegative integer offset.")
    end
    local specs = scan(root)
    local result, err = model.grep(specs, {
        pattern = args.pattern, regex = args.regex, ignoreCase = args.ignoreCase,
        type = args.type, tag = args.tag, parent = args.parent, dependsOn = args.dependsOn,
        limit = math.min(args.limit or DEFAULT_LIMIT, DEFAULT_LIMIT), offset = offset, max_bytes = MAX_BYTES - 2048,
    })
    if not result then return failure("Invalid search pattern: " .. tostring(err)) end
    local lines = {}
    for _, match in ipairs(result.matches) do
        lines[#lines + 1] = string.format("%s:%d: %s", match.path, match.line, match.snippet)
    end
    local header = #result.matches == 0 and "No matches."
        or string.format("%d match(es)%s:", #result.matches, result.truncated and " (truncated)" or "")
    local text = header .. (#lines > 0 and ("\n" .. table.concat(lines, "\n")) or "")
    if result.next_offset then
        text = text .. string.format(
            "\nMore matches: repeat spec_grep with the same filters and offset: %d, or narrow the search.",
            result.next_offset)
    end
    return bounded(text)
end

function handlers.spec_graph(args, root)
    local graph = graph_of(scan(root))
    if not graph.nodes[args.root] then return failure(string.format('No spec with id "%s".', args.root)) end
    local slice = model.slice(graph, args.root, args.direction, args.depth, args.edge)
    local node_lines, edge_lines = {}, {}
    for _, node in ipairs(slice.nodes) do node_lines[#node_lines + 1] = string.format("  %s (%s)", describe(node), node.path) end
    for _, edge in ipairs(slice.edges) do edge_lines[#edge_lines + 1] = string.format("  %s --%s--> %s", edge.from, edge.kind, edge.to) end
    local parts = {
        string.format('Slice of "%s" (%s, depth %s):', args.root, args.direction, tostring(args.depth or 1)),
        string.format("nodes (%d):", #slice.nodes),
    }
    for _, line in ipairs(node_lines) do parts[#parts + 1] = line end
    parts[#parts + 1] = string.format("edges (%d):", #slice.edges)
    for _, line in ipairs(edge_lines) do parts[#parts + 1] = line end
    if #slice.missing > 0 then parts[#parts + 1] = "missing targets: " .. table.concat(slice.missing, ", ") end
    return bounded(table.concat(parts, "\n"))
end

function handlers.spec_validate(_, root)
    local report = model.validate(graph_of(scan(root)))
    if report.valid then return "Spec-graph is valid: no issues found." end
    local sections = {}
    if #report.duplicates > 0 then
        local lines = {}
        for _, item in ipairs(report.duplicates) do lines[#lines + 1] = string.format("  %s: %s", item.id, table.concat(item.paths, ", ")) end
        sections[#sections + 1] = string.format("Duplicate ids (%d):\n%s", #lines, table.concat(lines, "\n"))
    end
    if #report.dangling > 0 then
        local lines = {}
        for _, item in ipairs(report.dangling) do
            lines[#lines + 1] = string.format("  %s (%s) --%s--> %s [missing]", item.from, item.from_path, item.kind, item.target)
        end
        sections[#sections + 1] = string.format("Dangling links (%d):\n%s", #lines, table.concat(lines, "\n"))
    end
    if #report.cycles > 0 then
        local lines = {}
        for _, ring in ipairs(report.cycles) do lines[#lines + 1] = string.format("  %s -> %s", table.concat(ring, " -> "), ring[1]) end
        sections[#sections + 1] = string.format("Parent cycles (%d):\n%s", #lines, table.concat(lines, "\n"))
    end
    return bounded(table.concat(sections, "\n\n"))
end

function handlers.spec_create(args, root)
    local rel, err = check_path(root, args.path)
    if not rel then return failure(err) end
    local abs = root .. "/" .. rel
    if uji.fs.read(abs) then return failure("File already exists: " .. rel) end
    if graph_of(scan(root)).nodes[args.id] then return failure(string.format('Spec id "%s" is already in use.', args.id)) end
    if not model.contains(model.SPEC_TYPES, args.type) then return failure("Unknown spec type: " .. tostring(args.type)) end
    if args.status and not model.contains(model.SPEC_STATUSES, args.status) then
        return failure("Unknown spec status: " .. tostring(args.status))
    end

    local frontmatter = { id = args.id, type = args.type, status = args.status, title = args.title, parent = args.parent }
    frontmatter["depends-on"] = args.dependsOn
    frontmatter.references, frontmatter.implements = args.references, args.implements
    frontmatter.covers, frontmatter.tags = args.covers, args.tags
    local headings = {}
    for _, heading in ipairs(SCAFFOLD_HEADINGS[args.type] or {}) do headings[#headings + 1] = "## " .. heading .. "\n" end
    local content = model.serialize(frontmatter) .. "\n" .. table.concat(headings, "\n")
    if not model.is_spec(model.parse_file(content)) then
        return failure(string.format(
            "Refusing to write %s: the frontmatter would not be a spec (id and type must be non-empty).", rel))
    end
    local written, write_err = uji.fs.write(abs, content)
    if not written then return failure(string.format("Failed to write %s: %s", rel, tostring(write_err))) end
    return string.format("Created %s (id: %s).", rel, args.id)
end

function handlers.spec_update(args, root)
    local spec = find_spec(scan(root), args.id)
    if not spec then return failure(string.format('No spec with id "%s".', args.id)) end
    local content, err = model.update_text(spec.content, args)
    if not content then return failure(err) end
    local written, write_err = uji.fs.write(spec.abs, content)
    if not written then return failure(string.format("Failed to write %s: %s", spec.path, tostring(write_err))) end
    return string.format("Updated frontmatter of %s (id: %s).", spec.path, args.id)
end

function handlers.spec_delete(args, root)
    local spec = find_spec(scan(root), args.id)
    if not spec then return failure(string.format('No spec with id "%s".', args.id)) end
    local removed, err = os.remove(spec.abs)
    if not removed then return failure(string.format("Failed to delete %s: %s", spec.path, tostring(err))) end
    return string.format("Deleted %s (id: %s).", spec.path, args.id)
end

local function array(items)
    return { type = "array", items = { type = "string" }, description = items }
end

local function enum(values, description)
    return { type = "string", enum = values, description = description }
end

local list_group = {
    type = "object",
    properties = {
        ["depends-on"] = array(), references = array(), implements = array(), covers = array(), tags = array(),
    },
}

local definitions = {
    {
        name = "spec_grep", label = "Spec Grep",
        description = "Search the project's spec-graph: regex or substring match within spec files (files whose frontmatter carries `id` + `type`), optionally narrowed by metadata (type / tag / parent / depends-on). Returns size-bounded pages of path:line matches; follow the returned offset only if needed. Oversized text is capped at 2,000 lines / 50 KiB with full output in a temporary file. Read a matched file's body with the normal read tool.",
        parameters = {
            type = "object", required = { "pattern" },
            properties = {
                pattern = { type = "string", description = "Regex or substring to search for within spec files." },
                regex = { type = "boolean", description = "Treat pattern as a regular expression (default: substring)." },
                ignoreCase = { type = "boolean", description = "Case-insensitive match (default: true)." },
                type = { type = "string", description = "Only search specs with this frontmatter type." },
                tag = { type = "string", description = "Only search specs carrying this tag." },
                parent = { type = "string", description = "Only search specs whose parent is this id." },
                dependsOn = { type = "string", description = "Only search specs that depend-on this id." },
                limit = { type = "integer", minimum = 1, description = "Matches per page (default/max: 200; the byte limit may return fewer)." },
                offset = { type = "integer", minimum = 0, description = "Zero-based match offset (default: 0). Continue with the offset given in the result and the same filters; restart after source changes." },
            },
        },
    },
    {
        name = "spec_get", label = "Spec Get",
        description = "Get one spec node by id: its frontmatter, path, and resolved links (forward + reverse edges across parent/depends-on/references/implements). Returns no prose body — read the file at the returned path with the read tool.",
        parameters = { type = "object", required = { "id" }, properties = { id = { type = "string", description = "The spec id to look up." } } },
    },
    {
        name = "spec_graph", label = "Spec Graph",
        description = "Return a bounded slice of the spec-graph rooted at a node: `subtree` (down the parent tree), `ancestors` (up to the tree root), or `neighbors` (across a chosen edge and its reverse). Bounded by `depth` (default 1).",
        parameters = {
            type = "object", required = { "root", "direction" },
            properties = {
                root = { type = "string", description = "Id of the node to start from." },
                direction = enum(model.SLICE_DIRECTIONS, "subtree = down the parent tree; ancestors = up the parent chain; neighbors = across an edge and its reverse."),
                depth = { type = "number", description = "How many hops to expand (default: 1)." },
                edge = enum(model.LINK_KINDS, "For direction=neighbors: which edge kind to traverse (default: depends-on)."),
            },
        },
    },
    {
        name = "spec_create", label = "Spec Create",
        description = "Create a new spec file with scaffolded frontmatter (id, type, title, an optional status, and any links) and a heading-only body stub chosen by type. Fails if the file already exists, the id is already in use, or the path is not an indexable root-relative .md path. Edit prose afterward with the write/edit tools.",
        parameters = {
            type = "object", required = { "path", "id", "type", "title" },
            properties = {
                path = { type = "string", description = "Root-relative path for the new spec file, ending in .md (e.g. src/foo/SPEC.md). Must stay inside the project root." },
                id = { type = "string", description = "Unique spec id." },
                type = enum(model.SPEC_TYPES, "Spec type: goal-and-requirements | architecture-design | module-design | submodule-design | task-spec."),
                title = { type = "string", description = "Human-readable title." },
                status = enum(model.SPEC_STATUSES, "Lifecycle status: draft | active | stale | done | deprecated."),
                parent = { type = "string", description = "Parent id (the tree edge)." },
                dependsOn = array("depends-on link ids."),
                references = array("references link ids."),
                implements = array("implements link ids."),
                covers = array("covers ids."),
                tags = array("tags."),
            },
        },
    },
    {
        name = "spec_update", label = "Spec Update",
        description = "Edit a spec's frontmatter only (never its prose): set/overwrite scalar fields, remove fields, and add/remove entries in the list fields (depends-on/references/implements/covers/tags). Comments and any non-dialect fields are preserved. Prose is edited with the write/edit tools.",
        parameters = {
            type = "object", required = { "id" },
            properties = {
                id = { type = "string", description = "Id of the spec to update." },
                set = {
                    type = "object", additionalProperties = { type = "string" },
                    description = "Scalar frontmatter fields to set/overwrite (e.g. title, status, parent). For list fields (depends-on/references/implements/covers/tags) use addList/removeList.",
                },
                remove = array("Frontmatter field names to remove entirely."),
                addList = list_group,
                removeList = list_group,
            },
        },
    },
    {
        name = "spec_delete", label = "Spec Delete",
        description = "Delete a spec file by id. Other specs may still reference it afterward — run spec_validate to find dangling links.",
        parameters = { type = "object", required = { "id" }, properties = { id = { type = "string", description = "Id of the spec to delete." } } },
    },
    {
        name = "spec_validate", label = "Spec Validate",
        description = "Validate the spec-graph: report dangling parent/depends-on/references/implements links, duplicate ids, and parent cycles.",
        parameters = { type = "object", properties = {} },
    },
}

function M.setup()
    for _, definition in ipairs(definitions) do
        local name = definition.name
        uji.tool.add(name, {
            description = definition.description,
            parameters = definition.parameters,
            policy = WRITING[name] and "ask" or "allow",
            subject = function(args) return args.path or args.id or args.root or args.pattern or name end,
            path = name == "spec_create",
            display = { label = definition.label },
            run = function(args)
                local ok, result = pcall(handlers[name], args or {}, project_root())
                if not ok then return "Error: " .. uji.message(result) end
                return result
            end,
        })
    end

    uji.context.add("uji-spec-graph", function() return RULE end)
    uji.on("before_tool", function(event)
        local planmode = package.loaded["planmode"]
        if WRITING[event.name] and planmode and planmode.active and planmode.active() then
            return { deny = "Spec mutations are unavailable in plan mode." }
        end
    end, { name = "spec-graph-planmode", priority = 5 })
end

M._handlers = handlers

return M
