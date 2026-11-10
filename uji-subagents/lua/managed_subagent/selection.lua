local M = {}
local installed = setmetatable({}, { __mode = "k" })

function M.install(selection, width)
    if installed[selection] then return end
    installed[selection] = true
    local press, drag, row, rects = selection.press, selection.drag, selection.row, selection.rects
    local limit
    selection.press = function(self, x, y, now)
        local available = width()
        limit = available and x < available and available or nil
        return press(self, x, y, now)
    end
    selection.drag = function(self, x, y)
        return drag(self, limit and math.max(0, math.min(x, limit)) or x, y)
    end
    selection.row = function(self, y)
        local chars = row(self, y)
        if limit then
            for index = #chars, limit + 1, -1 do chars[index] = nil end
        end
        return chars
    end
    selection.rects = function(self, panes, screen_width)
        local result = rects(self, panes, limit or screen_width)
        if limit then
            for _, rect in ipairs(result) do
                rect.width = math.max(0, math.min(rect.width, limit - rect.x))
            end
        end
        return result
    end
end

return M
