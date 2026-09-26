if not CLIENT then return end
if ZCityUrineVisuals and ZCityUrineVisuals.Version=="20260918.material1"then
    net.Start("ZCUrineReadyV1");net.WriteUInt(2,8);net.SendToServer();return
end
-- Hot reload must not orphan models from the previous effect table.
for _,pkt in ipairs(ZCityUrineVisuals and ZCityUrineVisuals.packets or {}) do
    if IsValid(pkt.anchor) then pkt.anchor:StopParticles();pkt.anchor:Remove() end
end
local V={Version="20260918.material1",packets={},activeAnchors=0,MaxPackets=192,MaxAnchors=32}
ZCityUrineVisuals=V
V.Gravity=386.1
V.Tail=0.12
V.ColorOuter=Color(226,205,92,95)
V.ColorInner=Color(246,232,145,150)
V.Beam=CreateMaterial("zc_urine_stream_material1","UnlitGeneric",{
    ["$basetexture"]="sprites/physbeam",
    ["$translucent"]="1",
    ["$vertexalpha"]="1",
    ["$vertexcolor"]="1",
    ["$additive"]="0",
})
-- $basetexture names a VTF texture, not the cable/physbeam VMT material.
local function usableMaterial(mat)
    if not mat or mat:IsError() then return false end
    local texture=mat:GetTexture("$basetexture")
    return texture~=nil and not texture:IsError()
end
V.MaterialFallback=false
if not usableMaterial(V.Beam) then
    V.Beam=Material("color")
    V.MaterialFallback=true
end
V.MaterialValid=usableMaterial(V.Beam)
if not V.MaterialValid then
    ErrorNoHalt("[ZCityUrine] Missing stream and fallback textures; beam rendering disabled.\n")
end
pcall(game.AddParticles,"particles/antlion_worker.pcf")
pcall(PrecacheParticleSystem,"antlion_spit_trail")
local function point(pkt,t)
    return pkt.origin+pkt.velocity*t+Vector(0,0,-0.5*V.Gravity*t*t)
end
local function killAnchor(pkt)
    if IsValid(pkt.anchor)then
        pkt.anchor:StopParticles()
        pkt.anchor:Remove()
    end
    pkt.anchor=nil
    if pkt.anchorCounted then V.activeAnchors=math.max(0,V.activeAnchors-1);pkt.anchorCounted=nil end
end
local function makeAnchor(pkt)
    if pkt.serial%2~=0 or V.activeAnchors>=V.MaxAnchors then return end
    local a=ClientsideModel("models/props_junk/PopCan01a.mdl",RENDERGROUP_OTHER)
    if not IsValid(a)then return end
    a:SetNoDraw(true)
    a:SetPos(pkt.origin)
    pkt.anchor=a
    pkt.anchorCounted=true;V.activeAnchors=V.activeAnchors+1
    pcall(ParticleEffectAttach,"antlion_spit_trail",PATTACH_ABSORIGIN_FOLLOW,a,0)
end
net.Receive("ZCUrinePacketV1",function()
    local owner=net.ReadEntity()
    local pkt={
        owner=owner,
        serial=net.ReadUInt(16),
        origin=net.ReadVector(),
        velocity=net.ReadVector(),
        flight=math.Clamp(net.ReadFloat(),0.01,1.2),
        born=CurTime()
    }
    local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
    if not finite(pkt.flight) or not finite(pkt.origin.x) or not finite(pkt.origin.y)
        or not finite(pkt.origin.z) or not finite(pkt.velocity.x)
        or not finite(pkt.velocity.y) or not finite(pkt.velocity.z) then return end
    while #V.packets>=V.MaxPackets do killAnchor(table.remove(V.packets,1)) end
    makeAnchor(pkt)
    V.packets[#V.packets+1]=pkt
end)
hook.Add("Think","ZCityUrineVisuals_Move",function()
    local now=CurTime()
    for i=#V.packets,1,-1 do
        local pkt=V.packets[i]
        local age=now-pkt.born
        if age<0 or age>pkt.flight+0.16 then
            killAnchor(pkt)
            table.remove(V.packets,i)
        elseif IsValid(pkt.anchor)then
            pkt.anchor:SetPos(point(pkt,math.min(age,pkt.flight)))
        end
    end
end)
hook.Add("PostDrawTranslucentRenderables","ZCityUrineVisuals_Draw",function(depth,skybox)
    if depth or skybox or not V.MaterialValid or #V.packets==0 then return end
    render.SetMaterial(V.Beam)
    local now=CurTime()
    for _,pkt in ipairs(V.packets)do
        local age=now-pkt.born
        local head=math.min(math.max(age,0),pkt.flight)
        local tail=math.max(0,head-V.Tail)
        if head>0 and tail<=pkt.flight then
            local a=point(pkt,tail)
            local b=point(pkt,head)
            render.DrawBeam(a,b,1.8,0,1,V.ColorOuter)
            render.DrawBeam(a,b,0.65,0,1,V.ColorInner)
        end
    end
end)
function V.Reset()
    for _,pkt in ipairs(V.packets)do killAnchor(pkt)end
    V.packets={};V.activeAnchors=0
end
hook.Add("PostCleanupMap","ZCityUrineVisuals_Reset",V.Reset)
hook.Add("ShutDown","ZCityUrineVisuals_Reset",V.Reset)
net.Start("ZCUrineReadyV1");net.WriteUInt(2,8);net.SendToServer()
