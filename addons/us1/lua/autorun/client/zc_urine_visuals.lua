if not CLIENT then return end
if ZCityUrineVisuals and ZCityUrineVisuals.Version=="20260919.visual1"then
    net.Start("ZCUrineReadyV1");net.WriteUInt(4,8);net.SendToServer();return
end
-- Hot reload must not orphan models from the previous effect table.
for _,pkt in ipairs(ZCityUrineVisuals and ZCityUrineVisuals.packets or {}) do
    if IsValid(pkt.anchor) then pkt.anchor:StopParticles();pkt.anchor:Remove() end
end
local V={Version="20260919.visual1",packets={},activeAnchors=0,MaxPackets=192,MaxAnchors=0}
ZCityUrineVisuals=V
V.Gravity=386.1
V.Tail=0.12
V.ColorOuter=Color(156,148,112,32)
V.ColorInner=Color(177,169,132,92)
V.Beam=CreateMaterial("zc_urine_stream_visual1","UnlitGeneric",{
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
-- Flight is a dim, translucent beam only. Splashes are server-confirmed.
local function point(pkt,t)
    return pkt.origin+pkt.velocity*t+Vector(0,0,-0.5*V.Gravity*t*t)
end
-- The beam shader uses vertex color; sample world lighting once per short packet.
-- No additive blending, dynamic light, self-illumination, or bright white core.
function V.GetColors(pkt,position)
    if not pkt.outerColor then
        local light=render.ComputeLighting(position)
        local level=light.x*0.2126+light.y*0.7152+light.z*0.0722
        if level~=level or math.abs(level)==math.huge then level=0.05 end
        level=math.Clamp(level,0.05,0.85)
        pkt.outerColor=Color(V.ColorOuter.r*level,V.ColorOuter.g*level,V.ColorOuter.b*level,V.ColorOuter.a)
        pkt.innerColor=Color(V.ColorInner.r*level,V.ColorInner.g*level,V.ColorInner.b*level,V.ColorInner.a)
    end
    return pkt.outerColor,pkt.innerColor
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
    while #V.packets>=V.MaxPackets do table.remove(V.packets,1) end
    V.packets[#V.packets+1]=pkt
end)
hook.Add("Think","ZCityUrineVisuals_Move",function()
    local now=CurTime()
    for i=#V.packets,1,-1 do
        local pkt=V.packets[i]
        local age=now-pkt.born
        if age<0 or age>pkt.flight+0.16 then
            table.remove(V.packets,i)

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
            local outer,inner=V.GetColors(pkt,b)
            render.DrawBeam(a,b,1.2,0,1,outer)
            render.DrawBeam(a,b,0.45,0,1,inner)
        end
    end
end)
function V.Reset()
    V.packets={};V.activeAnchors=0
end
hook.Add("PostCleanupMap","ZCityUrineVisuals_Reset",V.Reset)
hook.Add("ShutDown","ZCityUrineVisuals_Reset",V.Reset)
net.Start("ZCUrineReadyV1");net.WriteUInt(4,8);net.SendToServer()
