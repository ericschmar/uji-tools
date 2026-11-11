local yaml = require("spec_graph.yaml")

local M = {}

M.SPEC_TYPES = { "goal-and-requirements", "architecture-design", "module-design", "submodule-design", "task-spec" }
M.SPEC_STATUSES = { "draft", "active", "stale", "done", "deprecated" }
M.LINK_KINDS = { "parent", "depends-on", "references", "implements" }
M.LIST_FIELDS = { "depends-on", "references", "implements", "covers", "tags" }
M.IDENTITY_FIELDS = { "id", "type" }
M.SLICE_DIRECTIONS = { "subtree", "ancestors", "neighbors" }

local FIELD_ORDER = { "id", "type", "status", "title", "parent", "depends-on", "references", "implements", "covers", "tags" }
local BOM = "\239\187\191"

local function contains(array, value)
    for _, item in ipairs(array) do
        if item == value then return true end
    end
    return false
end
M.contains = contains

local function trim(text)
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function split_lines(text)
    local lines = {}
    for line in (text .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
    return lines
end
M.split_lines = split_lines

local function strip_cr(line)
    return (line:gsub("\r$", ""))
end

-- Splits a file into its frontmatter lines and its body. Returns nil when the
-- file has no closing fence.
local function split_frontmatter(content)
    local text = content:sub(1, 3) == BOM and content:sub(4) or content
    local lines = split_lines(text)
    if trim(strip_cr(lines[1])) ~= "---" then return nil end
    for index = 2, #lines do
        if trim(strip_cr(lines[index])) == "---" then
            local front, body = {}, {}
            for position = 2, index - 1 do front[#front + 1] = strip_cr(lines[position]) end
            for position = index + 1, #lines do body[#body + 1] = lines[position] end
            return { lines = front, body = table.concat(body, "\n") }
        end
    end
    return nil
end

-- Returns the frontmatter table, or nil when there is none or it is not valid.
function M.parse_file(content)
    local parts = split_frontmatter(content)
    if not parts then return nil end
    return (yaml.parse(parts.lines))
end

function M.scalar(frontmatter, key)
    local value = frontmatter[key]
    if type(value) == "string" and value ~= "" then return value end
    return nil
end

function M.list(frontmatter, key)
    local value = frontmatter[key]
    if type(value) == "table" then return value end
    if type(value) == "string" and value ~= "" then return { value } end
    return {}
end

function M.is_spec(frontmatter)
    return frontmatter ~= nil and M.scalar(frontmatter, "id") ~= nil and M.scalar(frontmatter, "type") ~= nil
end

local function needs_quotes(text)
    if text == "" or text:match("^%s") or text:match("%s$") then return true end
    if text:match("^[%-%?:,%[%]{}#&%*!|>'\"%%@`]") then return true end
    if text:find(": ", 1, true) or text:find(" #", 1, true) or text:match(":$") then return true end
    if text:find("[\n\r\t]") then return true end
    local lowered = text:lower()
    if lowered == "true" or lowered == "false" or lowered == "null" or lowered == "yes" or lowered == "no"
        or lowered == "on" or lowered == "off" or lowered == "~" then
        return true
    end
    return tonumber(text) ~= nil
end

local function format_scalar(text)
    if not needs_quotes(text) then return text end
    local escaped = text:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
    return '"' .. escaped .. '"'
end

local function format_value(value)
    if type(value) == "table" then
        local items = {}
        for _, item in ipairs(value) do items[#items + 1] = format_scalar(item) end
        return "[" .. table.concat(items, ", ") .. "]"
    end
    return format_scalar(value)
end

-- Writes frontmatter in canonical field order, then any other keys sorted.
function M.serialize(frontmatter)
    local lines, written = { "---" }, {}
    local function emit(key)
        local value = frontmatter[key]
        if value == nil or value == "" or (type(value) == "table" and #value == 0) then return end
        written[key] = true
        lines[#lines + 1] = key .. ": " .. format_value(value)
    end
    for _, key in ipairs(FIELD_ORDER) do emit(key) end
    local extra = {}
    for key in pairs(frontmatter) do
        if not written[key] then extra[#extra + 1] = key end
    end
    table.sort(extra)
    for _, key in ipairs(extra) do emit(key) end
    lines[#lines + 1] = "---"
    return table.concat(lines, "\n") .. "\n"
end

-- Each top-level key's line range in frontmatter lines.
local function entries(lines)
    local found, current = {}, nil
    for index, line in ipairs(lines) do
        local key
        if not line:match("^%s") and not line:match("^%-") and not line:match("^#") then
            key = yaml.split_key(line)
        end
        if key then
            current = { key = key, first = index, last = index }
            found[#found + 1] = current
        elseif current and (line:match("^%s") or line:match("^%-") or line:match("^%s*$")) then
            current.last = index
        else
            current = nil
        end
    end
    for _, entry in ipairs(found) do
        while entry.last > entry.first and lines[entry.last]:match("^%s*$") do entry.last = entry.last - 1 end
    end
    return found
end

local function replace_entry(lines, key, new_line)
    for _, entry in ipairs(entries(lines)) do
        if entry.key == key then
            local out = {}
            for index = 1, entry.first - 1 do out[#out + 1] = lines[index] end
            if new_line then out[#out + 1] = new_line end
            for index = entry.last + 1, #lines do out[#out + 1] = lines[index] end
            return out
        end
    end
    if new_line then
        local out = { table.unpack(lines) }
        out[#out + 1] = new_line
        return out
    end
    return lines
end

-- Edits frontmatter in place. Comments, unknown fields, ordering, line endings
-- and the body stay as they were. Returns the new text, or nil and a message.
function M.update_text(file_text, edit)
    local parts = split_frontmatter(file_text)
    if not parts then return nil, "File has no frontmatter to update." end
    local current = yaml.parse(parts.lines)
    if not current then return nil, "File frontmatter is not valid YAML." end
    local lines = parts.lines

    for key, value in pairs(edit.set or {}) do
        if key == "id" then return nil, "Cannot rename a spec's id via set." end
        if contains(M.LIST_FIELDS, key) then
            return nil, string.format('Use addList/removeList to edit the list field "%s".', key)
        end
        if type(value) ~= "string" then return nil, string.format('Field "%s" must be a string.', key) end
        lines = replace_entry(lines, key, key .. ": " .. format_scalar(value))
        current[key] = value
    end
    for _, key in ipairs(edit.remove or {}) do
        if contains(M.IDENTITY_FIELDS, key) then return nil, string.format('Cannot remove protected field "%s".', key) end
        lines = replace_entry(lines, key, nil)
        current[key] = nil
    end
    for _, field in ipairs(M.LIST_FIELDS) do
        local add = (edit.addList or {})[field]
        local remove = (edit.removeList or {})[field]
        local items = { table.unpack(M.list(current, field)) }
        local changed = false
        if add and #add > 0 then
            for _, item in ipairs(add) do
                if not contains(items, item) then items[#items + 1] = item end
            end
            changed = true
        end
        if remove and #remove > 0 then
            local kept = {}
            for _, item in ipairs(items) do
                if not contains(remove, item) then kept[#kept + 1] = item end
            end
            items = kept
            changed = true
        end
        if changed then
            lines = replace_entry(lines, field, #items > 0 and (field .. ": " .. format_value(items)) or nil)
            current[field] = #items > 0 and items or nil
        end
    end

    local check = yaml.parse(lines)
    if not check or not M.scalar(check, "id") or not M.scalar(check, "type") then
        return nil, "Update would leave the file without a valid id and type."
    end

    local ending = file_text:find("\r\n", 1, true) and "\r\n" or "\n"
    local out = { "---" }
    for _, line in ipairs(lines) do out[#out + 1] = line end
    out[#out + 1] = "---"
    return (file_text:sub(1, 3) == BOM and BOM or "") .. table.concat(out, ending) .. ending .. parts.body
end

local function push(map, key, value)
    local existing = map[key]
    if existing then existing[#existing + 1] = value else map[key] = { value } end
end

function M.link_targets(frontmatter, kind)
    if kind == "parent" then
        local target = M.scalar(frontmatter, "parent")
        return target and { target } or {}
    end
    return M.list(frontmatter, kind)
end

-- Builds the graph from { path, frontmatter } entries, in the order given.
function M.build_graph(file_entries)
    local graph = { nodes = {}, order = {}, edges = {}, forward = {}, reverse = {}, duplicate_ids = {}, duplicate_order = {} }
    for _, kind in ipairs(M.LINK_KINDS) do
        graph.forward[kind], graph.reverse[kind] = {}, {}
    end
    local paths, path_order = {}, {}
    for _, entry in ipairs(file_entries) do
        local id, kind = M.scalar(entry.frontmatter, "id"), M.scalar(entry.frontmatter, "type")
        if id and kind then
            if not paths[id] then path_order[#path_order + 1] = id end
            push(paths, id, entry.path)
            if not graph.nodes[id] then
                graph.nodes[id] = {
                    id = id, type = kind, title = M.scalar(entry.frontmatter, "title"),
                    path = entry.path, frontmatter = entry.frontmatter,
                }
                graph.order[#graph.order + 1] = id
            end
        end
    end
    for _, id in ipairs(graph.order) do
        local node = graph.nodes[id]
        for _, kind in ipairs(M.LINK_KINDS) do
            for _, to in ipairs(M.link_targets(node.frontmatter, kind)) do
                graph.edges[#graph.edges + 1] = { from = id, to = to, kind = kind }
                push(graph.forward[kind], id, to)
                push(graph.reverse[kind], to, id)
            end
        end
    end
    for _, id in ipairs(path_order) do
        if #paths[id] > 1 then
            graph.duplicate_ids[id] = paths[id]
            graph.duplicate_order[#graph.duplicate_order + 1] = id
        end
    end
    return graph
end

function M.validate(graph)
    local report = { dangling = {}, duplicates = {}, cycles = {} }
    for _, id in ipairs(graph.order) do
        local node = graph.nodes[id]
        for _, kind in ipairs(M.LINK_KINDS) do
            for _, target in ipairs(M.link_targets(node.frontmatter, kind)) do
                if not graph.nodes[target] then
                    report.dangling[#report.dangling + 1] = { from = id, from_path = node.path, kind = kind, target = target }
                end
            end
        end
    end
    for _, id in ipairs(graph.duplicate_order) do
        report.duplicates[#report.duplicates + 1] = { id = id, paths = graph.duplicate_ids[id] }
    end
    local seen, keys = {}, {}
    for _, start in ipairs(graph.order) do
        if not seen[start] then
            local path, on_path = {}, {}
            local current = start
            while current and graph.nodes[current] do
                if on_path[current] then
                    local ring = { table.unpack(path, on_path[current]) }
                    local sorted = { table.unpack(ring) }
                    table.sort(sorted)
                    local key = table.concat(sorted, "\0")
                    if not keys[key] then
                        keys[key] = true
                        report.cycles[#report.cycles + 1] = ring
                    end
                    break
                end
                if seen[current] then break end
                path[#path + 1] = current
                on_path[current] = #path
                current = M.scalar(graph.nodes[current].frontmatter, "parent")
            end
            for _, id in ipairs(path) do seen[id] = true end
        end
    end
    report.valid = #report.dangling == 0 and #report.duplicates == 0 and #report.cycles == 0
    return report
end

-- Returns a bounded slice around root: { nodes, edges, missing }.
function M.slice(graph, root, direction, depth, edge)
    depth = depth or 1
    local included, order = { [root] = true }, { root }
    local edges, seen_edges = {}, {}
    local missing, missing_order = {}, {}

    local function walk(step)
        local frontier = { root }
        for _ = 1, depth do
            local next_frontier = {}
            for _, id in ipairs(frontier) do
                for _, hop in ipairs(step(id)) do
                    local key = hop.edge.from .. "\0" .. hop.edge.kind .. "\0" .. hop.edge.to
                    if not seen_edges[key] then
                        seen_edges[key] = true
                        edges[#edges + 1] = hop.edge
                    end
                    if not graph.nodes[hop.to] and not missing[hop.to] then
                        missing[hop.to] = true
                        missing_order[#missing_order + 1] = hop.to
                    end
                    if not included[hop.to] then
                        included[hop.to] = true
                        order[#order + 1] = hop.to
                        next_frontier[#next_frontier + 1] = hop.to
                    end
                end
            end
            if #next_frontier == 0 then break end
            frontier = next_frontier
        end
    end

    if direction == "subtree" then
        walk(function(id)
            local hops = {}
            for _, child in ipairs(graph.reverse.parent[id] or {}) do
                hops[#hops + 1] = { to = child, edge = { from = child, to = id, kind = "parent" } }
            end
            return hops
        end)
    elseif direction == "ancestors" then
        walk(function(id)
            local hops = {}
            for _, parent in ipairs(graph.forward.parent[id] or {}) do
                hops[#hops + 1] = { to = parent, edge = { from = id, to = parent, kind = "parent" } }
            end
            return hops
        end)
    else
        edge = edge or "depends-on"
        walk(function(id)
            local hops = {}
            for _, to in ipairs(graph.forward[edge][id] or {}) do
                hops[#hops + 1] = { to = to, edge = { from = id, to = to, kind = edge } }
            end
            for _, from in ipairs(graph.reverse[edge][id] or {}) do
                hops[#hops + 1] = { to = from, edge = { from = from, to = id, kind = edge } }
            end
            return hops
        end)
    end

    local nodes = {}
    for _, id in ipairs(order) do
        if graph.nodes[id] then nodes[#nodes + 1] = graph.nodes[id] end
    end
    return { nodes = nodes, edges = edges, missing = missing_order }
end

local function matches_filters(frontmatter, filters)
    if filters.type and M.scalar(frontmatter, "type") ~= filters.type then return false end
    if filters.parent and M.scalar(frontmatter, "parent") ~= filters.parent then return false end
    if filters.tag and not contains(M.list(frontmatter, "tags"), filters.tag) then return false end
    if filters.dependsOn and not contains(M.list(frontmatter, "depends-on"), filters.dependsOn) then return false end
    return true
end

-- Searches spec content line by line. Returns { matches, truncated, next_offset },
-- or nil and a message for a bad pattern.
function M.grep(file_entries, opts)
    local limit = math.floor(opts.limit or 200)
    if limit < 1 then limit = 200 end
    local offset = opts.offset or 0
    local ignore_case = opts.ignoreCase ~= false
    local test
    if opts.regex then
        local matcher, err = uji.regex((ignore_case and "(?i)" or "") .. opts.pattern)
        if not matcher then return nil, err end
        test = function(line) return matcher:test(line) end
    elseif ignore_case then
        local needle = opts.pattern:lower()
        test = function(line) return line:lower():find(needle, 1, true) ~= nil end
    else
        test = function(line) return line:find(opts.pattern, 1, true) ~= nil end
    end

    local matches, skipped, bytes = {}, 0, 0
    for _, entry in ipairs(file_entries) do
        if matches_filters(entry.frontmatter, opts) then
            for number, raw in ipairs(split_lines(entry.content)) do
                if number == 1 and raw:sub(1, 3) == BOM then raw = raw:sub(4) end
                local line = strip_cr(raw)
                if test(line) then
                    if skipped < offset then
                        skipped = skipped + 1
                    else
                        local snippet = trim(line)
                        local size = #(entry.path .. ":" .. number .. ": " .. snippet) + 1
                        if #matches >= limit or (#matches > 0 and bytes + size > (opts.max_bytes or math.huge)) then
                            return { matches = matches, truncated = true, next_offset = offset + #matches }
                        end
                        matches[#matches + 1] = { path = entry.path, line = number, snippet = snippet }
                        bytes = bytes + size
                    end
                end
            end
        end
    end
    return { matches = matches, truncated = false }
end

return M
