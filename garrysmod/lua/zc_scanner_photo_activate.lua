-- One-map deployment bridge. Not an autorun and not a gameplay input channel.
if not SERVER then return end
local version = "20260915.7"
local digest = "0bb5d4b722264c1ee0540b51803f94e398b5bff98b192a5e0cebdc974b41a92a"
local source = assert(file.Read("zc_scanner_photo_payload.lua", "LUA"))
assert(util.SHA256(source) == digest, "scanner payload checksum mismatch")
local fn = CompileString(source, "zc_scanner_photo_payload.lua", false)
assert(isfunction(fn), tostring(fn)); fn()
local c = assert(ZCityPillCompat)
assert(c.Version == version); c.Install(); c.InstallScannerPhoto()
local form = assert(pk_pills.getPillTable("cityscanner"))
assert(form.attack2 and form.attack2.func == c.ScannerPhoto)
for _, ent in ipairs(ents.FindByClass("pill_ent_phys")) do
    if ent:GetPillForm() == "cityscanner" and istable(ent.formTable) then
        ent.formTable.attack2 = { mode = "trigger", func = c.ScannerPhoto }
    end
end
AddCSLuaFile("zc_scanner_photo_payload.lua")
local channel, ack = "zc_scanner_refresh_7", "zc_scanner_refresh_ack_7"
util.AddNetworkString(channel); util.AddNetworkString(ack)
local payload = util.Compress(source); assert(#payload < 60000)
local targets = {}
ZCityScannerDeploy = { version = version, sent = 0, received = 0, passed = 0, clients = {} }
local result = ZCityScannerDeploy
local function save() file.Write("zc_scanner_deployment.json", util.TableToJSON(result, true)) end
net.Receive(ack, function(bits, ply)
    if bits > 4096 or not targets[ply] or targets[ply].acked then return end
    local ok, message = net.ReadBool(), string.sub(net.ReadString(), 1, 200)
    targets[ply].acked = true; result.received = result.received + 1
    if ok then result.passed = result.passed + 1 end
    result.clients[tostring(ply:EntIndex())] = { ok = ok, detail = message }
    print("[ZCityScannerDeploy] client", ply:EntIndex(), ok and "PASS" or "FAIL", message)
    save()
end)
local bootstrap = [[
net.Receive("zc_scanner_refresh_7", function()
    local src = util.Decompress(net.ReadData(net.ReadUInt(16)))
    local ok, message = false, "scanner checksum mismatch"
    if src and util.SHA256(src) == "__DIGEST__" then
        local run = CompileString(src, "ZCityScannerPhoto20260915", false)
        if isfunction(run) then ok, message = pcall(run) else message = run end
    end
    timer.Simple(2, function()
        if ok then
            local c = ZCityPillCompat
            c.Install(); c.InstallScannerPhoto()
            local f = pk_pills.getPillTable("cityscanner")
            ok = c.Version == "20260915.7" and f and f.attack2 and f.attack2.func == c.ScannerPhoto
                and hg and isfunction(hg.AddFlash) and istable(hg.flashes)
                and isfunction(net.Receivers.zc_pill_scanner_photo)
            message = ok and "scanner secondary flash and visual receiver active" or "scanner verification failed"
        end
        net.Start("zc_scanner_refresh_ack_7")
        net.WriteBool(ok == true); net.WriteString(string.sub(tostring(message or ""), 1, 200))
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
-- Supersede the old pill refresh bridge without touching drone control delivery.
hook.Add("PlayerInitialSpawn", "ZCityPillSelection_LiveUpdate", function(ply)
    timer.Simple(10, function() send(ply) end)
end)
hook.Add("PlayerDisconnected", "ZCityPillSelection_LiveUpdate", function(ply) targets[ply] = nil end)
timer.Simple(8, function() for _, ply in ipairs(player.GetHumans()) do send(ply) end end)
save()
print("[ZCityScannerDeploy] server active", version, "clients present", #player.GetHumans())
