require("uji.builtin.defaults")
local root = require("uji.core.paths").config() .. "/../.."
uji.pack.add({ { dir = root } })
uji.provider.add({
  id = "goal-test", name = "Model-free goal test provider", api = uji.api.openai(),
  base_url = "http://127.0.0.1:1", models = { { id = "fake", context = 100000 } },
})
require("uji.core.model").stream = function()
  uji.sleep(0.08)
  return { text = "Test turn finished without completing the goal.", tool_calls = {} }
end
package.loaded["uji.core.run"] = function(store, parsed)
  require("uji.core.task").release()
  local mode = parsed.positional[1] or "integration"
  local ok, err = pcall(function()
    assert(loadfile(root .. "/tests/" .. mode .. ".lua"))(store)
  end)
  if not ok then io.stderr:write(tostring(err), "\n") end
  require("uji.sys").os.exit(ok and 0 or 1)
end
