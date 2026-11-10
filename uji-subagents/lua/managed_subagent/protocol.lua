local M = { version = 1, max_bytes = 1024 * 1024, max_steering = 32 * 1024 }
local assemblies = {}

function M.encode_event(value)
    local line = uji.json.encode(value)
    if #line <= M.max_bytes then return { line } end
    local size = math.floor(M.max_bytes / 2)
    local parts = {}
    for start = 1, #line, size do parts[#parts + 1] = line:sub(start, start + size - 1) end
    assert(#parts <= 64, "worker event exceeds 32 MiB")
    local lines = {}
    for index, part in ipairs(parts) do
        lines[index] = uji.json.encode({ version = M.version, type = "chunk", seq = value.seq,
            task_id = value.task_id, index = index, total = #parts,
            data = require("uji.sys").base64.encode(part) })
    end
    return lines
end

function M.terminal(status)
    return status == "completed" or status == "failed" or status == "cancelled"
end

function M.decode(line, pending)
    local assemblies = pending or assemblies
    if type(line) ~= "string" or #line > M.max_bytes then return nil, "event exceeds size limit" end
    local ok, value = pcall(uji.json.decode, line)
    if not ok or type(value) ~= "table" or value.version ~= M.version
        or type(value.type) ~= "string" or type(value.seq) ~= "number" or value.seq < 1 then
        return nil, "invalid worker event"
    end
    if value.type == "chunk" then
        if type(value.task_id) ~= "string" or type(value.index) ~= "number" or type(value.total) ~= "number"
            or value.total < 1 or value.total > 64 or value.index < 1 or value.index > value.total
            or value.index % 1 ~= 0 or value.total % 1 ~= 0 or type(value.data) ~= "string" then
            return nil, "invalid worker event chunk"
        end
        local key = value.task_id .. ":" .. value.seq
        local assembly = assemblies[key]
        if not assembly then
            assembly = { total = value.total, parts = {}, count = 0 }
            assemblies[key] = assembly
        end
        if assembly.total ~= value.total or assembly.parts[value.index] then
            assemblies[key] = nil
            return nil, "invalid worker event chunk sequence"
        end
        local decoded, part = pcall(require("uji.sys").base64.decode, value.data)
        if not decoded then assemblies[key] = nil; return nil, "invalid chunk encoding" end
        assembly.parts[value.index], assembly.count = part, assembly.count + 1
        if assembly.count ~= assembly.total then return nil end
        assemblies[key] = nil
        local line = table.concat(assembly.parts)
        if #line > 64 * M.max_bytes then return nil, "event exceeds size limit" end
        local ok_event, event = pcall(uji.json.decode, line)
        if not ok_event or type(event) ~= "table" or event.version ~= M.version
            or type(event.type) ~= "string" or type(event.seq) ~= "number" or event.seq < 1
            or event.type == "chunk" then
            return nil, "invalid reassembled worker event"
        end
        return event
    end
    return value
end

function M.command(value)
    if type(value) ~= "table" or type(value.id) ~= "string" or #value.id > 128 then
        return nil, "invalid command id"
    end
    if value.action == "stop" then return value end
    if value.action ~= "steer" or type(value.text) ~= "string" or not value.text:find("%S")
        or #value.text > M.max_steering then
        return nil, "steering must contain 1–32768 bytes of nonblank text"
    end
    return value
end

function M.request(port, token, command)
    local response, err = uji.net.request({
        url = "http://127.0.0.1:" .. port .. "/control",
        method = "POST",
        headers = { ["Authorization"] = "Bearer " .. token, ["Content-Type"] = "application/json" },
        body = uji.json.encode(command),
        timeout = 5,
    })
    if not response then return nil, err end
    if response.status ~= 200 then return nil, "worker rejected control request (" .. response.status .. ")" end
    local ok, value = pcall(uji.json.decode, response.body)
    if not ok or type(value) ~= "table" then return nil, "invalid control response" end
    if value.error then return nil, value.error end
    return value
end

function M.serve(conn, token, handle)
    local function reply(code, body)
        local text = uji.json.encode(body)
        conn:write("HTTP/1.1 " ..
        code ..
        "\r\nContent-Type: application/json\r\nConnection: close\r\nContent-Length: " .. #text .. "\r\n\r\n" .. text)
    end
    if (conn:line(3) or ""):gsub("\r$", "") ~= "POST /control HTTP/1.1" then
        return reply("400 Bad Request", { error = "invalid request" })
    end
    local headers, bytes = {}, 0
    while true do
        local line = conn:line(3)
        if type(line) ~= "string" then return end
        line = line:gsub("\r$", "")
        bytes = bytes + #line
        if bytes > 8192 then return reply("431 Request Header Fields Too Large", { error = "headers too large" }) end
        if line == "" then break end
        local key, value = line:match("^([^:]+):%s*(.-)%s*$")
        if not key then return reply("400 Bad Request", { error = "invalid header" }) end
        headers[key:lower()] = value
    end
    if headers.authorization ~= "Bearer " .. token then
        return reply("403 Forbidden", { error = "unauthorized" })
    end
    local length = tonumber(headers["content-length"])
    if not length or length < 1 or length > M.max_steering * 6 + 1024 or length % 1 ~= 0 then
        return reply("413 Content Too Large", { error = "invalid content length" })
    end
    local ok, value = pcall(uji.json.decode, conn:read(length))
    local command, err
    if ok then command, err = M.command(value) end
    if not command then return reply("400 Bad Request", { error = err or "invalid JSON" }) end
    local result, after = handle(command)
    reply("200 OK", result)
    if after then after() end
end

return M
