local paths = {"zc_bots/sv_chatter.lua", "zc_bots/sv_fill.lua"}
local out = { time = os.time(), files = {}, ok = false }
local function activate()
    assert(hg and hg.botdriver and hg.botdriver.lib and isfunction(hg.botdriver.lib.VisualContact), "Missing bot perception API")
    assert(hg.botdriver.personalitySchema == 2, "Unexpected personality schema")
    local compiled = {}
    for _, path in ipairs(paths) do
        compiled[path] = CompileFile(path)
        assert(isfunction(compiled[path]), "Compile failure: " .. path)
    end
    for _, path in ipairs(paths) do
        compiled[path]()
        out.files[path] = "loaded"
    end
end
out.ok, out.error = xpcall(activate, debug.traceback)
file.Write("zc_bot_immersion_activation.json", util.TableToJSON(out, true))
print("[Bot immersion] activation " .. tostring(out.ok))
