-- Small native entry point. Existing clients can fetch missing parts after a live update.
if not CLIENT then return end
local VERSION="42a386300e22641e3334094097c90a569942586d5df06e5c92c88279ef5e156a"
local function ack(ok,detail)
    local function send()
        if util.NetworkStringToID("ZCKCViewerAck")==0 then return false end
        net.Start("ZCKCViewerAck");net.WriteBool(ok);net.WriteString(tostring(detail):sub(1,240));net.SendToServer()
        return true
    end
    if send() then timer.Remove("ZCKCViewerAck");return end
    timer.Create("ZCKCViewerAck",1,10,function()
        if send() then timer.Remove("ZCKCViewerAck") end
    end)
end
if ZCKillcamViewerDelivery and ZCKillcamViewerDelivery.version==VERSION and ZCKillcamViewerDelivery.complete then ack(true,VERSION);return end
local state={version=VERSION,parts={},requests=0}
ZCKillcamViewerDelivery=state
local function apply(source)
    if state.complete or ZCKillcamViewerDelivery~=state then return end
    if util.SHA256(source)~=VERSION then ack(false,"checksum");ErrorNoHalt("[Replay delivery] Source checksum failed.\n");return end
    local active=ZCKillcamView and ZCKillcamView.ObserverState and ZCKillcamView.ObserverState()
    if active and active.active then
        state.pending=source
        timer.Create("ZCKCViewerApply",.5,0,function()apply(state.pending)end)
        return
    end
    timer.Remove("ZCKCViewerApply")
    local fn=CompileString(source,"zc_killcam/cl_viewer.lua",false)
    if not isfunction(fn) then ack(false,fn);ErrorNoHalt(tostring(fn).."\n");return end
    local ok,err=xpcall(fn,debug.traceback)
    if not ok then ack(false,err);ErrorNoHalt("[Replay delivery] "..tostring(err).."\n");return end
    state.complete=true;state.parts={};state.pending=nil
    timer.Remove("ZCKCViewerRequest");ack(true,VERSION)
end
net.Receive("ZCKCViewerPart",function()
    local version=net.ReadString()
    local i,n,length=net.ReadUInt(8),net.ReadUInt(8),net.ReadUInt(16)
    if version~=VERSION or state.complete or n<1 or n>32 or i<1 or i>n or length>8192 then return end
    if state.count and state.count~=n then return end
    state.count=n;state.parts[i]=net.ReadData(length)
    for k=1,n do if not state.parts[k] then return end end
    local source=util.Decompress(table.concat(state.parts))
    if not isstring(source) or #source>600000 then ack(false,"payload");return end
    apply(source)
end)
local native={}
for i=1,9 do
    local path=string.format("zc_killcam/viewer_parts/cl_part_%02d.lua",i)
    -- A mounted filename can exist before its client payload has arrived.
    local chunk=file.Read(path,"LUA")
    if not isstring(chunk) or chunk=="" then native=nil;break end
    local fn=CompileString(chunk,path,false)
    if not isfunction(fn) then native=nil;break end
    local ok,value=pcall(fn)
    if not ok or not isstring(value) then native=nil;break end
    native[i]=value
end
if native then
    local source=table.concat(native)
    -- A running client may still have the previous native fragment set when a new
    -- loader is sent to it. Let the versioned server transport supply the match.
    if util.SHA256(source)==VERSION then apply(source) end
end
if not state.complete then
    timer.Create("ZCKCViewerRequest",2,15,function()
        if ZCKillcamViewerDelivery~=state or state.complete then timer.Remove("ZCKCViewerRequest");return end
        if util.NetworkStringToID("ZCKCViewerRequest")==0 then return end
        if state.requests>=3 or (state.nextRequest or 0)>CurTime() then return end
        state.requests=state.requests+1
        state.nextRequest=CurTime()+6
        net.Start("ZCKCViewerRequest");net.SendToServer()
    end)
end
