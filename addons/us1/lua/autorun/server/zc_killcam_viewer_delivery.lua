-- Bounded client-code transport; does not reload recorder, clips, rounds or active players.
if not SERVER then return end
local VERSION="b0b37c4755aa1357ba3165fbb91c95fafd89b49ee3c8bd742cc6338232d481ef"
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
-- Review 2026-09-26 (amplification): a zero-byte request made the server send the whole viewer (~17 x 8 KB) every
-- 5 s, forever, per client. Now: nothing once that player acked this VERSION, at most 3 transfers per player per
-- connection, and at most 4 transfers in flight server-wide (a refused request is not counted; the client retries).
local sentTo=setmetatable({}, {__mode="k"})
local inFlight={}
local MAX_PER_PLAYER,MAX_IN_FLIGHT=3,4
local transferSeconds=count*.08+.5
net.Receive("ZCKCViewerRequest",function(bits,ply)
    if bits~=0 or not IsValid(ply) or not ply:IsPlayer() or ply:IsBot() or (nextRequest[ply] or 0)>CurTime() then return end
    local st=ZCKillcamViewerDeliveryStatus[ply]
    if st and st.ok and st.detail==VERSION then return end
    if (sentTo[ply] or 0)>=MAX_PER_PLAYER then return end
    local now=RealTime()
    local busy=0
    for k,untilAt in pairs(inFlight) do if untilAt<=now then inFlight[k]=nil else busy=busy+1 end end
    if busy>=MAX_IN_FLIGHT then return end
    nextRequest[ply]=CurTime()+5
    sentTo[ply]=(sentTo[ply] or 0)+1
    inFlight[ply:UserID()]=now+transferSeconds
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
