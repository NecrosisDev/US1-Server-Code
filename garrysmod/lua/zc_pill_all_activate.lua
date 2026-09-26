-- One-map hot deployment bridge; not an autorun or a client input channel.
if not SERVER then return end
local source = assert(file.Read("zc_pill_all_payload.lua", "LUA"))
local digest = "9f3c395e207f639e01a59d918a47accce7f8202dee84b5f9793c1d5625f27ef3"
assert(util.SHA256(source) == digest, "pill selection payload mismatch")
local run = CompileString(source, "zc_pill_all_payload.lua", false)
assert(isfunction(run), tostring(run)); run()
assert(ZCityPillCompat.Version == "20260915.5")
AddCSLuaFile("zc_pill_all_payload.lua")
local payload = util.Compress(source)
assert(#payload < 60000)
local channel, ack = "zc_pill_selection_20260915", "zc_pill_selection_ack_20260915"
util.AddNetworkString(channel); util.AddNetworkString(ack)
local targets = {}
ZCityPillSelectionResult = { version = "20260915.5", sent = 0, received = 0, passed = 0, clients = {} }
local result = ZCityPillSelectionResult
local function save()
    file.Write("zc_pill_selection_deployment.json", util.TableToJSON(result, true))
end
net.Receive(ack, function(bits, ply)
    if bits > 4096 or not targets[ply] or targets[ply].acked then return end
    local ok, message = net.ReadBool(), string.sub(net.ReadString(), 1, 256)
    targets[ply].acked = true; result.received = result.received + 1
    if ok then result.passed = result.passed + 1 end
    result.clients[tostring(ply:EntIndex())] = { ok = ok, detail = message }
    print("[ZCityPillSelection] client", ply:EntIndex(), ok and "PASS" or "FAIL", message)
    save()
end)
local bootstrap = [[
net.Receive("zc_pill_selection_20260915", function()
    local source = util.Decompress(net.ReadData(net.ReadUInt(16)))
    local ok, message = false, "payload mismatch"
    if source and util.SHA256(source) == "__DIGEST__" then
        local fn = CompileString(source, "ZCityPillSelection20260915", false)
        if isfunction(fn) then ok, message = pcall(fn) else message = fn end
    end
    timer.Simple(2, function()
        if ok then
            local c = ZCityPillCompat
            c.Install()
            local audit = c.ResolveAllDefinitions()
            ok = c.Version == "20260915.5" and isfunction(c.ResolveAllDefinitions)
                and audit and audit.count >= 95 and audit.valid == audit.count and next(audit.invalid) == nil
            message = ok and "complete pill registry and compatibility active" or "pill verification failed"
        end
        net.Start("zc_pill_selection_ack_20260915")
        net.WriteBool(ok == true); net.WriteString(string.sub(tostring(message or ""), 1, 256))
        net.SendToServer()
    end)
end)
]]
bootstrap = string.Replace(bootstrap, "__DIGEST__", digest)
assert(#bootstrap < 6000)
local function send(ply)
    if not IsValid(ply) or ply:IsBot() or targets[ply] then return end
    targets[ply] = { acked = false }; result.sent = result.sent + 1
    ply:SendLua(bootstrap)
    timer.Simple(1, function()
        if not IsValid(ply) then return end
        net.Start(channel); net.WriteUInt(#payload, 16); net.WriteData(payload, #payload); net.Send(ply)
    end)
    save()
end
timer.Simple(8, function() for _, ply in ipairs(player.GetHumans()) do send(ply) end end)
-- Until map change, new clients also get the update even if the engine retains an old GMA mount.
hook.Add("PlayerInitialSpawn", "ZCityPillSelection_LiveUpdate", function(ply)
    timer.Simple(5, function() send(ply) end)
end)
hook.Add("PlayerDisconnected", "ZCityPillSelection_LiveUpdate", function(ply) targets[ply] = nil end)
print("[ZCityAllPills] server active; existing-client refresh in 8 seconds")
timer.Simple(18, function()
    print("[ZCityPillSelection] deployment", result.passed, "/", result.sent, "passed")
    save()
end)

local audit = ZCityPillCompat.ResolveAllDefinitions()
print("[ZCityAllPills] definitions", audit.valid, audit.count, "invalid", table.Count(audit.invalid))
