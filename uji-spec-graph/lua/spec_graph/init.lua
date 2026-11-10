local M = {}
local root
for _, directory in ipairs(uji.pack.list()) do
    local file = io.open(directory .. "/lua/spec_graph/init.lua", "r")
    if file then
        file:close()
        root = directory
        break
    end
end
assert(root, "spec-graph pack directory not found")
local shutdown

local RULE = table.concat({
    "Specs are this project's ground truth.",
    "- Consult the relevant spec when work is governed by or may alter a documented boundary, contract, invariant, behavior, or architecture decision; localized work need not read unrelated specs.",
    "- Treat applicable decisions and contracts as authoritative; reconcile contradictions instead of diverging.",
    "- When a change alters a boundary, contract, invariant, or decision, update the owning spec as part of that change.",
}, "\n")

function M.setup(opts)
    opts = opts or {}
    if shutdown then shutdown() end
    local file = assert(io.open(root .. "/tools.json", "r"), "spec-graph: run bun install && bun run manifest in " .. root)
    local definitions = uji.json.decode(file:read("*a"))
    file:close()
    local worker
    local pending = {}
    local sequence = 0

    local function fail(message)
        local waiting = pending
        pending = {}
        for _, call in pairs(waiting) do
            if call.cancel then call.cancel() end
            call.done("Error: " .. message .. ". A mutation may have completed; inspect the file before retrying.")
        end
    end

    shutdown = function()
        local job = worker
        worker = nil
        if job then job.stop() end
        fail("spec-graph worker stopped")
    end

    local function start()
        if worker then return worker end
        local stderr = {}
        local job
        job = uji.job.start({
            cmd = { opts.bun or "bun", root .. "/bridge.ts" },
            on_stdout = function(line)
                if worker ~= job then return end
                local ok, message = pcall(uji.json.decode, line)
                if not ok or type(message) ~= "table" then
                    shutdown()
                    return
                end
                local call = pending[message.id]
                if not call then return end
                if message.text then call.parts[#call.parts + 1] = message.text end
                if message.done then
                    pending[message.id] = nil
                    call.cancel()
                    call.done(table.concat(call.parts))
                end
            end,
            on_stderr = function(line)
                if #stderr < 10 then stderr[#stderr + 1] = line end
            end,
            on_exit = function(code)
                if worker ~= job then return end
                worker = nil
                fail("spec-graph worker exited (" .. tostring(code) .. "): " .. table.concat(stderr, "\n"))
            end,
        })
        worker = job
        return job
    end

    for _, definition in ipairs(definitions) do
        local name = definition.name
        local writing = name == "spec_create" or name == "spec_update" or name == "spec_delete"
        uji.tool.add(name, {
            description = definition.description,
            parameters = definition.parameters,
            policy = writing and "ask" or "allow",
            subject = function(args) return args.path or args.id or args.root or args.pattern or name end,
            path = name == "spec_create",
            display = { label = definition.label },
            run = function(args, ctx)
                local ok, job = pcall(start)
                if not ok then return "Error: cannot start spec-graph worker: " .. tostring(job) end
                sequence = sequence + 1
                local id = sequence
                local call = { done = ctx.done, parts = {} }
                pending[id] = call
                call.cancel = uji.defer(opts.timeout or 60, function()
                    shutdown()
                end)
                local sent, err = pcall(job.send, uji.json.encode({ id = id, name = name, params = args }))
                if not sent then
                    pending[id] = nil
                    call.cancel()
                    shutdown()
                    return "Error: cannot send to spec-graph worker: " .. tostring(err)
                end
                return function()
                    if not pending[id] then return end
                    pending[id] = nil
                    call.cancel()
                    shutdown()
                end
            end,
        })
    end

    uji.context.add("uji-spec-graph", function() return RULE end)
    uji.on("before_tool", function(event)
        local writing = event.name == "spec_create" or event.name == "spec_update" or event.name == "spec_delete"
        local planmode = package.loaded["planmode"]
        if writing and planmode and planmode.active and planmode.active() then
            return { deny = "Spec mutations are unavailable in plan mode." }
        end
    end, { name = "spec-graph-planmode", priority = 5 })
    uji.on("before_quit", function() shutdown() end, { name = "spec-graph-shutdown" })
end

return M
