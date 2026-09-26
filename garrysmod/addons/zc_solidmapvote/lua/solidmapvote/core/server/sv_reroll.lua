-- Shared RTV rerolls; existing map winner selection and Random stay separate.
local M=SolidMapVote
M.RerollVersion="20260915.1"
M.ballotRevision=M.ballotRevision or 0
M.rerolls=M.rerolls or 0
M.rerollRequests=M.rerollRequests or {}
M.rerollSeen=M.rerollSeen or {}
function M.beginBallotRevision()
    M.ballotRevision=(M.ballotRevision%4294967294)+1
    M.rerollRequests={};M.rerollReady=RealTime()+3
    for _,name in ipairs(M.maps)do M.rerollSeen[name]=true end
end
function M.rerollThreshold()
    return math.max(1,math.ceil(#M.humans()*M.number("RTV Percentage",0.6,0.01,1)))
end
function M.rerollOptions()
    local exclude={};local unseen=0
    for _,name in ipairs(M.mapPool or {})do
        if not M.rerollSeen[name] and not M.ballotSet[name] then unseen=unseen+1 end
    end
    for _,name in ipairs(M.mapPool or {})do
        if M.ballotSet[name] or (unseen>0 and M.rerollSeen[name]) then exclude[name]=true end
    end
    local available=0
    for _,name in ipairs(M.mapPool or {})do if not exclude[name]then available=available+1 end end
    return exclude,available
end
function M.rerollSupport()
    local count=0;local ids={}
    for _,p in ipairs(M.humans())do
        local id=p:SteamID64()
        if M.rerollRequests[id] and not ids[id]then count=count+1;ids[id]=true end
    end
    return count,ids
end
function M.rerollStatus()
    local count,ids=M.rerollSupport()
    local _,available=M.rerollOptions()
    local limit=math.floor(M.number("Maximum Rerolls",2,0,5))
    return {revision=M.ballotRevision,count=count,needed=M.rerollThreshold(),used=M.rerolls,
        limit=limit,voters=ids,available=available,
        enabled=M.phase=="voting" and RealTime()<M.deadline and M.rerolls<limit and available>0,
        ready=CurTime()+math.max(0,(M.rerollReady or 0)-RealTime())}
end
util.AddNetworkString("SolidMapVote.rerollState")
function M.sendReroll(all,ply)
    if not M.initialized then return end
    net.Start("SolidMapVote.rerollState");net.WriteTable(M.rerollStatus())
    if all then net.Broadcast()elseif IsValid(ply)then net.Send(ply)end
end
function M.performReroll()
    local status=M.rerollStatus()
    if not status.enabled or RealTime()<(M.rerollReady or 0) or status.count<status.needed then return false end
    local exclude=M.rerollOptions()
    local oldMaps,oldSet=M.maps,M.ballotSet
    M.selectMaps(exclude,true)
    if #M.maps==0 then M.maps,M.ballotSet=oldMaps,oldSet;return false end
    M.rerolls=M.rerolls+1;M.votes={};M.beginBallotRevision()
    M.deadline=RealTime()+M.number("Length",25,5,120)
    M.endTime=CurTime()+(M.deadline-RealTime());M.startTime=CurTime()
    M.sendStart(true);M.sendPlayCounts(M.createWeightedPool(M.maps,M.mapPlayCounts),true)
    M.sendVotes(true);M.sendNominations(true);M.sendReroll(true)
    M.sendMessage({color_white,"Maps rerolled. Choose again from the new ballot."},true)
    return true
end
function M.requestReroll(ply,revision)
    if not M.acceptRequest(ply,"reroll",1) or tonumber(revision)~=M.ballotRevision then return false end
    local status=M.rerollStatus()
    if not status.enabled or RealTime()<(M.rerollReady or 0) then return false end
    local id=ply:SteamID64()
    M.rerollRequests[id]=not M.rerollRequests[id] or nil
    if not M.performReroll()then M.sendReroll(true)end
    return true
end
concommand.Add("solidmapvote_reroll",function(ply,_,args)M.requestReroll(ply,args[1])end)
hook.Add("PlayerDisconnected","SolidMapVote.RerollDisconnect",function(ply)
    M.rerollRequests[ply:SteamID64()]=nil
    timer.Simple(0,function()
        if M.phase=="voting" then if not M.performReroll()then M.sendReroll(true)end end
    end)
end)
hook.Add("PlayerInitialSpawn","SolidMapVote.RerollJoin",function()
    timer.Simple(2,function()if M.phase=="voting"then M.sendReroll(true)end end)
end)
