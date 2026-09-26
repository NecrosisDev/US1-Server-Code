-- Private half-size gas-can presentation. Ordinary hg_booom explosions are untouched.
local CHANNEL = "zc_explosive_blood_fx"
local PCF = "particles/zc_explosive_blood_half.pcf"
local EFFECT = "zc_eb_half_pcf_jack_incendiary_ground_sm2"
if SERVER then
    AddCSLuaFile()
    resource.AddFile(PCF)
    util.AddNetworkString(CHANNEL)
    return
end

-- Existing clients cannot download a new PCF through Lua hotload. Keep their native
-- fireball until reconnect/download, then use the private half-size asset.
local effect = "pcf_jack_incendiary_ground_sm2"
if file.Exists(PCF, "GAME") then
    game.AddParticles(PCF)
    effect = EFFECT
end
PrecacheParticleSystem(effect)
local near = {"ied/ied_detonate_01.wav", "ied/ied_detonate_02.wav", "ied/ied_detonate_03.wav"}
local far = {"ied/ied_detonate_dist_01.wav", "ied/ied_detonate_dist_02.wav", "ied/ied_detonate_dist_03.wav"}
local window, count = 0, 0
local function FiniteVector(pos)
    return isvector(pos) and pos.x == pos.x and pos.y == pos.y and pos.z == pos.z
        and math.abs(pos.x) < math.huge and math.abs(pos.y) < math.huge and math.abs(pos.z) < math.huge
end
net.Receive(CHANNEL, function()
    local pos = net.ReadVector()
    if not FiniteVector(pos) then return end
    local now = CurTime()
    if now >= window then window, count = now + 0.2, 0 end
    if count >= 10 then return end -- bound both expensive particles and delayed sound callbacks
    count = count + 1
    ParticleEffect(effect, pos, vector_up:Angle())
    local view = render.GetViewSetup(true)
    if not view or not FiniteVector(view.origin) then return end
    local delay = pos:Distance(view.origin) / 17836
    local snd, distant = table.Random(near), table.Random(far)
    timer.Simple(delay, function()
        EmitSound(distant, pos, 0, CHAN_WEAPON, 1, 110, 0, 100, 0, nil)
        EmitSound(snd, pos, 0, CHAN_AUTO, 1, delay > 0.6 and 140 or 110, 0, 100, 0, nil)
    end)
end)
