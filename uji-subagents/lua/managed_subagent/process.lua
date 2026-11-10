local M = {}

local function command(argv)
    local proc, err = uji.proc.spawn(argv)
    assert(proc, err)
    proc:close()
    local lines = {}
    for line, stream in proc:lines() do
        if stream == "stdout" then lines[#lines + 1] = line end
    end
    return proc:wait().success, lines
end

function M.kill(proc)
    local pid = proc.pid
    if not pid then return proc:kill() end
    local ok, problem = pcall(function()
        command({ "/bin/kill", "-STOP", tostring(pid) })
        local success, lines = command({ "/bin/ps", "-A", "-o", "pid=", "-o", "ppid=", "-o", "pgid=" })
        assert(success, "could not inspect worker subprocesses")
        local processes, owned = {}, { [pid] = true }
        for _, line in ipairs(lines) do
            local child, parent, group = line:match("^%s*(%d+)%s+(%d+)%s+(%d+)")
            if child then processes[#processes + 1] = { pid = tonumber(child), parent = tonumber(parent), group = tonumber(group) } end
        end
        local changed = true
        while changed do
            changed = false
            for _, process in ipairs(processes) do
                if owned[process.parent] and not owned[process.pid] then
                    owned[process.pid], changed = true, true
                    command({ "/bin/kill", "-STOP", tostring(process.pid) })
                end
            end
        end
        local groups = {}
        for _, process in ipairs(processes) do
            if owned[process.pid] and owned[process.group] and process.group ~= pid then
                groups[process.group] = true
            end
        end
        for group in pairs(groups) do command({ "/bin/kill", "-KILL", "--", "-" .. group }) end
    end)
    proc:kill()
    if not ok then uji.notify("Worker cleanup: " .. tostring(problem)) end
end

return M
