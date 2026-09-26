if not CLIENT then return end
if ZCPoopSmearClient and ZCPoopSmearClient.Version=="20260918.h1" then
    net.Start("ZCPoopSmearReadyV1");net.SendToServer();return
end
local S={Version="20260918.h1",queue={},seen={},order={},MaxSeen=2048,QueueTTL=30}
ZCPoopSmearClient=S
local function paint(d)
    local P=ZCPoopVisuals
    if not P or not P.ready or not P.stain or P.stain:IsError()then return false end
    local target=d.world and game.GetWorld() or d.ent
    if not d.world and not IsValid(target)then return true end
    util.DecalEx(P.stain,target,d.pos+d.normal*0.15,d.normal,Color(255,255,255),0.22,0.22)
    return true
end
local function enqueue(d)
    if S.seen[d.id]then return end
    S.seen[d.id]=true
    S.order[#S.order+1]=d.id
    if #S.order>S.MaxSeen then S.seen[table.remove(S.order,1)]=nil end
    d.expires=CurTime()+S.QueueTTL
    if paint(d)then return end
    if #S.queue<128 then S.queue[#S.queue+1]=d end
end
net.Receive("ZCPoopSmearV1",function()
    local d={id=net.ReadUInt(32),world=net.ReadBool()}
    if not d.world then d.ent=net.ReadEntity()end
    d.pos=net.ReadVector();d.normal=net.ReadNormal()
    enqueue(d)
end)
timer.Create("ZCityPoopSmear_Flush",0.5,0,function()
    if #S.queue==0 then return end
    local keep={}
    for _,d in ipairs(S.queue)do
        if CurTime()<d.expires and not paint(d)then keep[#keep+1]=d end
    end
    S.queue=keep
end)
hook.Add("PostCleanupMap","ZCityPoopSmear_Reset",function()
    S.queue={};S.seen={};S.order={}
end)
net.Start("ZCPoopSmearReadyV1");net.SendToServer()
