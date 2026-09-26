-- One-map hot deployment bridge; not an autorun or a client input channel.
if not SERVER then return end
local source = assert(file.Read("zc_drone_controls_payload.lua", "LUA"))
local digest = "09089e4866987d8443eccc8baa7841995186c355919aa5af5846b0a063d28715"
assert(util.SHA256(source) == digest, "drone control payload mismatch")
local run = CompileString(source, "zc_drone_controls_payload.lua", false)
assert(isfunction(run), tostring(run)); run()
assert(ZCityDronesCompat.Version == "20260915.6")
AddCSLuaFile("zc_drone_controls_payload.lua")
local payload = util.Compress(source)
assert(#payload < 60000)
local channel, ack = "zc_drone_controls_20260915", "zc_drone_controls_ack_20260915"
util.AddNetworkString(channel); util.AddNetworkString(ack)
local targets = {}
ZCityDroneControlsResult = { version = "20260915.6", sent = 0, received = 0, passed = 0, clients = {} }
local result = ZCityDroneControlsResult
local function save()
    file.Write("zc_drone_controls_deployment.json", util.TableToJSON(result, true))
end
net.Receive(ack, function(bits, ply)
    if bits > 4096 or not targets[ply] or targets[ply].acked then return end
    local ok, message = net.ReadBool(), string.sub(net.ReadString(), 1, 256)
    targets[ply].acked = true; result.received = result.received + 1
    if ok then result.passed = result.passed + 1 end
    result.clients[tostring(ply:EntIndex())] = { ok = ok, detail = message }
    print("[ZCityDroneControls] client", ply:EntIndex(), ok and "PASS" or "FAIL", message)
    save()
end)
local bootstrap = [[
net.Receive("zc_drone_controls_20260915", function()
    local source = util.Decompress(net.ReadData(net.ReadUInt(16)))
    local ok, message = false, "payload mismatch"
    if source and util.SHA256(source) == "__DIGEST__" then
        local fn = CompileString(source, "ZCityDroneMouseControls20260915", false)
        if isfunction(fn) then ok, message = pcall(fn) else message = fn end
    end
    timer.Simple(2, function()
        if ok then
            local d = ZCityDronesCompat
            d.InstallFlightInput()
            local row = d.Controls.inputHooks.InputMouseApply
            ok = d.Version == "20260915.6" and d.Controls.Version == "20260915.6"
                and isfunction(d.ApplyFlightMouse) and row
                and hook.GetTable().InputMouseApply.fakeCameraAngles == row.wrapper
                and GetConVar("zc_drone_mouse_sensitivity") ~= nil
            message = ok and "corrected physics frame and mouse/roll controls installed" or "input verification failed"
        end
        net.Start("zc_drone_controls_ack_20260915")
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
for _, ply in ipairs(player.GetHumans()) do send(ply) end
-- Until map change, new clients also get the update even if the engine retains an old GMA mount.
hook.Add("PlayerInitialSpawn", "ZCityDroneControls_LiveUpdate", function(ply)
    timer.Simple(5, function() send(ply) end)
end)
hook.Add("PlayerDisconnected", "ZCityDroneControls_LiveUpdate", function(ply) targets[ply] = nil end)
print("[ZCityDroneControls] server controls active; sending to", result.sent, "clients")
timer.Simple(12, function()
    print("[ZCityDroneControls] deployment", result.passed, "/", result.sent, "passed")
    save()
end)
