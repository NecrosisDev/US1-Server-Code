-- One-off live drift audit (docs/HANDOFF_PLAN.md WP-1.0). NOT shipped.
-- Upload to garrysmod/lua/, run `lua_openscript us1_live_hashes.lua` in the server console, wait for "done",
-- download garrysmod/data/us1_live_hashes.txt, then delete this file from the server.
-- Walks the physical garrysmod/ folder ("MOD"), so each line says which folder a file really lives in.
local out, queue, n = {}, {"lua/", "gamemodes/"}, 0
local _, addons = file.Find("addons/*", "MOD")
for _, a in ipairs(addons or {}) do queue[#queue + 1] = "addons/" .. a .. "/lua/"; queue[#queue + 1] = "addons/" .. a .. "/gamemodes/" end

local co = coroutine.create(function()
    while #queue > 0 do
        local dir = table.remove(queue)
        local files, dirs = file.Find(dir .. "*", "MOD")
        for _, d in ipairs(dirs or {}) do queue[#queue + 1] = dir .. d .. "/" end
        for _, f in ipairs(files or {}) do
            if string.EndsWith(f, ".lua") then
                local data = file.Read(dir .. f, "MOD")
                if data then out[#out + 1] = util.SHA256(data) .. "\t" .. dir .. f end
                n = n + 1
                if n % 50 == 0 then coroutine.yield() end
            end
        end
    end
end)

timer.Create("us1_live_hashes", 0, 0, function()
    local ok, err = coroutine.resume(co)
    if not ok then timer.Remove("us1_live_hashes") print("[us1_live_hashes] failed: " .. tostring(err)) return end
    if coroutine.status(co) == "dead" then
        timer.Remove("us1_live_hashes")
        file.Write("us1_live_hashes.txt", table.concat(out, "\n") .. "\n")
        print("[us1_live_hashes] done: " .. #out .. " files -> data/us1_live_hashes.txt")
    end
end)
