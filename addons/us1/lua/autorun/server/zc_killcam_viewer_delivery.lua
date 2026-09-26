-- Bounded client-code transport; does not reload recorder, clips, rounds or active players.
if not SERVER then return end
local VERSION="9c709ff6940d76fb6c74bb22d2d2a49c827d62bcc4535f32f75f3278c2ff9c57"
util.AddNetworkString("ZCKCViewerRequest")
util.AddNetworkString("ZCKCViewerPart")
util.AddNetworkString("ZCKCViewerAck")
local parts={}
for i=1,9 do
    local path=string.format("zc_killcam/viewer_parts/cl_part_%02d.lua",i)
    AddCSLuaFile(path)
    local fn=CompileString(assert(file.Read(path,"LUA")),path,false)
    assert(isfunction(fn),tostring(fn));parts[i]=fn()
end
AddCSLuaFile("zc_killcam/cl_viewer.lua")
local source=table.concat(parts)
assert(util.SHA256(source)==VERSION,"Replay transport source checksum failed")
local packed=assert(util.Compress(source))
assert(#packed<=262144,"Replay transport exceeds bounded capacity")
local count=math.ceil(#packed/8192)
local nextRequest=setmetatable({}, {__mode="k"})
ZCKillcamViewerDeliveryStatus=ZCKillcamViewerDeliveryStatus or setmetatable({}, {__mode="k"})
net.Receive("ZCKCViewerRequest",function(bits,ply)
    if bits~=0 or not IsValid(ply) or not ply:IsPlayer() or ply:IsBot() or (nextRequest[ply] or 0)>CurTime() then return end
    nextRequest[ply]=CurTime()+5
    for i=1,count do
        local index=i
        local data=packed:sub((i-1)*8192+1,i*8192)
        timer.Simple((i-1)*.08,function()
            if not IsValid(ply) then return end
            net.Start("ZCKCViewerPart");net.WriteString(VERSION)
            net.WriteUInt(index,8);net.WriteUInt(count,8);net.WriteUInt(#data,16)
            net.WriteData(data,#data);net.Send(ply)
        end)
    end
end)
net.Receive("ZCKCViewerAck",function(bits,ply)
    if bits>2048 or not IsValid(ply) or ply:IsBot() then return end
    local ok,detail=net.ReadBool(),net.ReadString()
    if #detail>240 or (ok and detail~=VERSION) then return end
    ZCKillcamViewerDeliveryStatus[ply]={ok=ok,detail=detail,at=os.time()}
end)
