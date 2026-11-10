local M = {}
local directory

local function root()
    if directory then return directory end
    for _, candidate in ipairs(uji.pack.list()) do
        local file = io.open(candidate .. "/lua/uji_tools/init.lua", "r")
        if file then
            file:close()
            directory = candidate
            return directory
        end
    end
    error("uji-tools pack directory not found")
end

function M.path(relative)
    assert(type(relative) == "string" and relative ~= "", "a relative pack path is required")
    assert(relative:sub(1, 1) ~= "/" and not relative:find("\\", 1, true), "a relative pack path is required")
    for part in relative:gmatch("[^/]+") do
        assert(part ~= "..", "pack paths must stay inside uji-tools")
    end
    return root() .. "/" .. relative
end

function M.setup()
    uji.pack.add({
        { dir = M.path("uji-subagents") },
        { dir = M.path("uji-goal") },
        { dir = M.path("uji-spec-graph") },
    })
    return M
end

return M
