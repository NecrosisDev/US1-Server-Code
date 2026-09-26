local J=assert(ZCityGuiltJustice)
local K=assert(ZCityKarmaBounties)
util.AddNetworkString("zc_guilt_review_v3")
util.AddNetworkString("zc_guilt_action_v3")
local function cfg() return ZCITY_GUILT and ZCITY_GUILT.Config or {} end
local function tell() end -- Results stay inside the requested review panel, never chat.
function J.Payload(v)
    if ZCityMetaSafety.Locked() then return {} end
    local rows={};local id=J.ID(v)
    for _,life in pairs(J.cases) do
        if life.victimId==id and life.ready and life.expires>CurTime() then
            for account,p in pairs(life.byAccount) do
                local a=J.Find(account);local balance=a and J.Balance(a)
                local room=balance and math.max(0,zb.MaxKarma-balance) or zb.MaxKarma
                local outstanding=J.Outstanding(p)
                local bounty=(p.bountyPaid or 0)>0 or (p.bountyFace or 0)>0
                local reward=p.respectEligible and not bounty and not J.Claims(life)[life.victimId]
                    and not J.respected[life.round..":"..life.victimId] and 3 or 0
                rows[#rows+1]={justice=true,caseid=life.justiceId,steamid64=account,
                    entindex=a and a:EntIndex() or -1,name=p.name,harm=p.contribution or 0,
                    karma=outstanding,refundable=math.min(outstanding,room),loss=p.automaticLoss or outstanding,
                    bounty=p.bountyPaid or 0,victimKarma=life.deathKarma,
                    decided=p.decision~=nil,decision=p.decision or "pending",reported=p.reported==true,
                    canForgive=outstanding>0 and not p.decision and cfg().AllowForgive~=false,
                    respectEligible=p.respectEligible==true,respectReward=math.min(reward,room),
                    canReport=not p.reported and cfg().AllowReport~=false,bountyCase=bounty}
            end
        end
    end
    table.sort(rows,function(a,b)return a.caseid>b.caseid or a.caseid==b.caseid and a.steamid64<b.steamid64 end)
    while #rows>64 do table.remove(rows) end
    return rows
end
function J.Sync(v)
    if not J.Player(v) then return end
    local count=0
    for _,r in ipairs(J.Payload(v)) do if not r.decided then count=count+1 end end
    if v:GetNWInt("ZCITY_GUILT_PENDING_COUNT",0)~=count then v:SetNWInt("ZCITY_GUILT_PENDING_COUNT",count) end
end
function J.Open(v)
    if cfg().MenuEnabled ~= true then return end
    if not J.Player(v) then return end
    J.openNext=J.openNext or setmetatable({}, {__mode="k"})
    if (J.openNext[v] or 0)>CurTime() then return end
    J.openNext[v]=CurTime()+0.1
    local payload=util.TableToJSON(J.Payload(v))
    if not payload or #payload>55000 then return end
    net.Start("zc_guilt_review_v3");net.WriteString(payload);net.Send(v)
    J.Sync(v)
end
function J.Resolve(v,caseId,account,action)
    if ZCityMetaSafety.Locked() then return false,"This case is not available." end
    local life=J.cases[caseId]
    if not J.Player(v) or not life or life.victimId~=J.ID(v) or not life.ready
        or life.expires<=CurTime() then return false,"This case is not available." end
    local p=life.byAccount[account]
    if not p then return false,"That player is not in this case." end
    if action~="report" and p.decision then return false,"This financial decision is already complete." end
    if action=="forgive" then
        if cfg().AllowForgive==false or J.Outstanding(p)<=0 then return false,"There is no automatic loss to forgive." end
        local amount=J.Outstanding(p)
        local ok,paid=J.ReturnLoss(p,amount,"forgive")
        if not ok then return false,"Refund could not be saved. No decision was consumed." end
        J.Mirror(p,-amount);p.decision="forgive"
        J.Log("forgive",{case=caseId,victim=life.victimId,attacker=account,waived=amount,paid=paid})
        local a=J.Find(account);if IsValid(a) then hook.Run("ZC_RoundStars_RecordForgive",v,a) end
    elseif action=="keep" or action=="acknowledge" then
        p.decision="keep"
        J.Log("keep",{case=caseId,victim=life.victimId,attacker=account})
    elseif action=="respect" then
        if not p.respectEligible then return false,"Respect is not available for this incident." end
        local a=J.Find(account)
        if not a then return false,"The player must be connected to receive Respect." end
        local key=life.round..":"..life.victimId
        local reward=(p.bountyFace or 0)>0 or (p.bountyPaid or 0)>0
            or J.Claims(life)[life.victimId] or J.respected[key]
        local paid=0
        if not reward and not a:IsBot() and not v:IsBot() then
            J.respected[key]=true
            J.Claims(life)[life.victimId]=true
            paid=math.max(0,J.Change(a,3))
        end
        p.decision="respect";p.respectPaid=paid
        J.Log("respect",{case=caseId,victim=life.victimId,attacker=account,paid=paid})
    elseif action=="report" then
        if cfg().AllowReport==false or p.reported then return false,"This incident has already been reported or reporting is disabled." end
        local id=J.ID(v);local last=J.limits[id] or -100
        if CurTime()-last<10 then return false,"Wait a moment before another report." end
        J.limits[id]=CurTime();p.reported=true
        local text=string.format("[GUILT REPORT] %s reported %s; case %d.",v:Nick(),p.name,caseId)
        for _,staff in ipairs(player.GetAll()) do if staff:IsAdmin() or staff:IsSuperAdmin() then staff:ChatPrint(text) end end
        J.Log("report",{case=caseId,victim=life.victimId,attacker=account})
    else return false,"Additional player-selected penalties have been retired." end
    K.Publish();J.Sync(v)
    return true,"Saved. No extra punishment was added."
end
net.Receive("zc_guilt_action_v3",function(bits,v)
    if cfg().MenuEnabled ~= true then return end
    if bits>2048 or bits<48 or not J.Player(v) then return end
    J.actionNext=J.actionNext or setmetatable({}, {__mode="k"})
    if (J.actionNext[v] or 0)>CurTime() then return end
    J.actionNext[v]=CurTime()+0.15
    local caseId,account,action=net.ReadUInt(32),net.ReadString(),net.ReadString()
    local ok,text=J.Resolve(v,caseId,account,action)
    tell(v,text);J.Open(v)
end)
timer.Create("ZCityGuiltJustice_Review",1,0,function()
    for id,life in pairs(J.cases) do
        if ZCityMetaSafety.Locked() and life.ready and life.expires>CurTime() then
            life.metaHeld=true;life.expires=math.huge
        end
        if (life.expires and life.expires+120<CurTime())
            or (not life.ready and life.round~=K.RoundKey() and CurTime()-(life.created or 0)>180) then J.cases[id]=nil end
    end
    for _,v in ipairs(player.GetAll()) do J.Sync(v) end
end)
concommand.Add("zc_guilt_justice_status",function(p)
    if IsValid(p) and not p:IsAdmin() then return end
    print("[GuiltJustice]",J.Version,"cases",table.Count(J.cases),"extra penalties",false)
end)
