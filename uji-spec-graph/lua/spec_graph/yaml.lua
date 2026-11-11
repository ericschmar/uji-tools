-- A reader for the YAML subset spec frontmatter uses: top-level keys with
-- plain, quoted or block scalars, flow lists and block lists. Nested maps are
-- dropped, as the spec model only keeps scalars and lists of scalars.
local M = {}

local function trim(text)
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function strip_comment(text)
    local quote
    for index = 1, #text do
        local char = text:sub(index, index)
        if quote then
            if char == quote then quote = nil end
        elseif char == '"' or char == "'" then
            if index == 1 or text:sub(index - 1, index - 1):match("[%s,%[{]") then quote = char end
        elseif char == "#" and (index == 1 or text:sub(index - 1, index - 1):match("%s")) then
            return trim(text:sub(1, index - 1))
        end
    end
    return trim(text)
end

local function encode_utf8(code)
    if code < 0x80 then return string.char(code) end
    if code < 0x800 then return string.char(0xC0 + math.floor(code / 0x40), 0x80 + code % 0x40) end
    return string.char(0xE0 + math.floor(code / 0x1000), 0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
end

local function unescape_double(body)
    local escapes = { n = "\n", t = "\t", r = "\r", ['"'] = '"', ["\\"] = "\\", ["/"] = "/", ["0"] = "\0" }
    body = body:gsub("\\u(%x%x%x%x)", function(hex) return encode_utf8(tonumber(hex, 16)) end)
    return (body:gsub("\\(.)", function(char) return escapes[char] or ("\\" .. char) end))
end

-- Parses one scalar. Returns the text, or nil for null, or false when the
-- text is a collection that the model drops.
local function scalar(text)
    text = trim(text)
    if text == "" or text == "~" or text:lower() == "null" then return nil end
    local first = text:sub(1, 1)
    if first == '"' then
        local body = text:match('^"(.*)"$')
        if not body then return nil, "unterminated string" end
        return unescape_double(body)
    elseif first == "'" then
        local body = text:match("^'(.*)'$")
        if not body then return nil, "unterminated string" end
        return (body:gsub("''", "'"))
    elseif first == "[" or first == "{" then
        return false
    end
    return text
end

local function split_flow(body)
    local parts, depth, quote, start = {}, 0, nil, 1
    for index = 1, #body do
        local char = body:sub(index, index)
        if quote then
            if char == quote then quote = nil end
        elseif char == '"' or char == "'" then
            quote = char
        elseif char == "[" or char == "{" then
            depth = depth + 1
        elseif char == "]" or char == "}" then
            depth = depth - 1
        elseif char == "," and depth == 0 then
            parts[#parts + 1] = body:sub(start, index - 1)
            start = index + 1
        end
    end
    local last = body:sub(start)
    if trim(last) ~= "" then parts[#parts + 1] = last end
    return parts
end

local function flow_list(text)
    local body = text:match("^%[(.*)%]$")
    if not body then return nil end
    local items = {}
    for _, part in ipairs(split_flow(body)) do
        local value = scalar(part)
        if value then items[#items + 1] = value end
    end
    return items
end

M.trim = trim

local function indented(line)
    return line:match("^%s") ~= nil
end

-- Splits "key: rest" into the key and the rest, or returns nil.
function M.split_key(line)
    local quoted, after = line:match("^(\"[^\"]*\")(:.*)$")
    if not quoted then quoted, after = line:match("^('[^']*')(:.*)$") end
    if quoted then
        local rest = after:sub(2)
        if rest == "" or rest:match("^%s") then return quoted:sub(2, -2), trim(rest) end
        return nil
    end
    local key, rest = line:match("^([^%s#:%-%[%]{}\"'][^:]-)%s*:(.*)$")
    if key and (rest == "" or rest:match("^%s")) then return trim(key), trim(rest) end
    return nil
end

-- Parses frontmatter text into a table of key to string or list of strings.
-- Returns nil and a message when the text is not usable YAML.
function M.parse(lines)
    local result, seen = {}, {}
    local index, count = 1, #lines
    while index <= count do
        local line = lines[index]
        if trim(line) == "" or line:match("^#") then
            index = index + 1
        else
            if indented(line) or line:match("^%-") then return nil, "unexpected indentation" end
            local key, rest = M.split_key(line)
            if not key then return nil, "not a key: " .. line end
            if seen[key] then return nil, "duplicate key " .. key end
            seen[key] = true

            local children = {}
            index = index + 1
            while index <= count do
                local next_line = lines[index]
                if trim(next_line) == "" or indented(next_line) or next_line:match("^%-") then
                    children[#children + 1] = next_line
                    index = index + 1
                else
                    break
                end
            end
            while #children > 0 and trim(children[#children]) == "" do children[#children] = nil end

            local value_text = strip_comment(rest)
            local value
            if value_text == "" then
                local first
                for _, child in ipairs(children) do
                    if trim(child) ~= "" and not trim(child):match("^#") then first = trim(child) break end
                end
                if first and (first == "-" or first:match("^%-%s")) then
                    value = {}
                    for _, child in ipairs(children) do
                        local item = child:match("^%s*%-%s+(.*)$") or (trim(child) == "-" and "")
                        if item then
                            item = strip_comment(item)
                            if not item:match("^[^%s\"'%[{][^:]*:%s") and not item:match("^[%[{]") then
                                local text = scalar(item)
                                if text then value[#value + 1] = text end
                            end
                        end
                    end
                end
            elseif value_text:sub(1, 1) == "|" or value_text:sub(1, 1) == ">" then
                local folded = value_text:sub(1, 1) == ">"
                local body = {}
                for _, child in ipairs(children) do body[#body + 1] = trim(child) end
                value = table.concat(body, folded and " " or "\n")
                if value == "" then value = nil end
            elseif value_text:sub(1, 1) == "[" then
                local joined = value_text
                for _, child in ipairs(children) do
                    if not joined:match("%]$") then joined = joined .. " " .. strip_comment(child) end
                end
                value = flow_list(joined)
                if not value then return nil, "unterminated flow list" end
            elseif value_text:sub(1, 1) == "{" then
                value = nil
            else
                local joined = value_text
                local first = joined:sub(1, 1)
                local quoted = first == '"' or first == "'"
                for _, child in ipairs(children) do
                    if quoted and joined:match("^" .. first .. ".*" .. first .. "$") and #joined > 1 then break end
                    joined = joined .. " " .. strip_comment(child)
                end
                local text, err = scalar(joined)
                if err then return nil, err end
                value = text or nil
            end
            if value ~= nil and value ~= false then result[key] = value end
        end
    end
    return result
end

return M
