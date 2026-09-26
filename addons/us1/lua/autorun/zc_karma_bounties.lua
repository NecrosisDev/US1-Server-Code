-- Goob's ZCity: one authoritative target-karma curve and confirmed-kill bounties.
if SERVER then AddCSLuaFile("autorun/zc_karma_bounties.lua");AddCSLuaFile("zc_guilt_justice/client.lua") end
ZCityKarmaBounties = ZCityKarmaBounties or {}
local K = ZCityKarmaBounties
K.Version = "20260916.1"
if SERVER then include("zc_guilt_justice/core.lua") end
local knots = { {0,10}, {25,0}, {50,-10}, {100,-20}, {120,-30} }
local slopes = {0}
for i=2,#knots-1 do
    local a=(knots[i][2]-knots[i-1][2])/(knots[i][1]-knots[i-1][1])
    local b=(knots[i+1][2]-knots[i][2])/(knots[i+1][1]-knots[i][1])
    slopes[i]=a*b>0 and 2*a*b/(a+b) or 0
end
slopes[#knots]=0
function K.Finite(n) return isnumber(n) and n==n and math.abs(n)<math.huge end
function K.Value(karma)
    if not K.Finite(karma) then return nil end
    karma=math.Clamp(karma,0,120)
    for i=1,#knots-1 do
        local a,b=knots[i],knots[i+1]
        if karma<=b[1] then
            local h=b[1]-a[1]; local t=(karma-a[1])/h
            return (2*t^3-3*t^2+1)*a[2]+(t^3-2*t^2+t)*h*slopes[i]
                +(-2*t^3+3*t^2)*b[2]+(t^3-t^2)*h*slopes[i+1]
        end
    end
end
local teamModes={tdm=true,cstrike=true,hl2dm=true,gwars=true,criresp=true,
    wildcard=true,riot=true,uncontainedriot=true,coop=true,defense=true}
function K.Kind(mode)
    local seen={}
    for _=1,12 do
        if not istable(mode) or seen[mode] then return nil end
        seen[mode]=true
        if mode.name=="hmcd" or mode.name=="fear" or mode.SubRoles then return "homicide" end
        if teamModes[mode.name] then return "team" end
        mode=zb and zb.modes and zb.modes[mode.base]
    end
end
local function playerEntity(p) return IsValid(p) and p:IsPlayer() end
if SERVER then
    local enabled=CreateConVar("zc_karma_bounties","1",FCVAR_ARCHIVE,
        "Target-karma loss curve and confirmed-kill bounties",0,1)
    K.lives=K.lives or setmetatable({}, {__mode="k"})
    K.claimed=K.claimed or {}
    function K.Karma(p)
        if not playerEntity(p) then return nil end
        local n=ZCityMetaSafety and ZCityMetaSafety.Public(p) or p.Karma
        if not K.Finite(n) and p.guilt_GetValue then n=p:guilt_GetValue() end
        return K.Finite(n) and n or nil
    end
    function K.Active()
        local mode=isfunction(CurrentRound) and CurrentRound()
        return enabled:GetBool() and zb and zb.ROUND_STATE==1 and K.Kind(mode)~=nil
            and not mode.GuiltDisabled and not (GetConVar("zb_dev") and GetConVar("zb_dev"):GetBool())
    end
    function K.Excluded(p)
        return ZC_POSTMORTEM_KARMA and ZC_POSTMORTEM_KARMA.players[p]~=nil
    end
    function K.RoundKey()
        local mode=isfunction(CurrentRound) and CurrentRound()
        return tostring(zb and zb.ROUND_START)..":"..tostring(mode and mode.name)
    end
    function K.RefreshRound()
        local key=K.RoundKey()
        if K.roundKey~=key then
            K.roundKey=key; K.claimed={}; K.lives=setmetatable({}, {__mode="k"})
        end
    end
    function K.Identity(p) return p:IsBot() and ("bot:"..p:UserID()) or p:SteamID64() end
    function K.GetLife(v)
        K.RefreshRound()
        local life=K.lives[v]
        if not life then
            life={round=K.roundKey, attackers={}, created=CurTime()}; K.lives[v]=life
        end
        return life
    end
    function K.Observe(a,v,info,harm,accepted)
        if not K.Active() or not playerEntity(a) or not playerEntity(v) then return end
        if a==v then
            local life=K.lives[v]; if life then life.selfDamageAt=CurTime() end
            return
        end
        if (not v:Alive() and not accepted) or K.Excluded(a) or K.Excluded(v) then return end
        if v:Team()>=1000 or a:Team()>=1000 then return end
        if not K.Finite(harm) or harm<0 or not K.Finite(info:GetDamage()) or info:GetDamage()<=0 then return end
        local life=K.GetLife(v); if life.settled then return end
        local pair=life.attackers[a] or {charged=0}; life.attackers[a]=pair
        pair.contribution=(pair.contribution or 0)+harm
        pair.time=CurTime(); pair.chargeEligible=false
        pair.attackerTraitor=a.isTraitor==true; pair.victimTraitor=v.isTraitor==true
        life.last=a; life.lastTime=CurTime(); return pair
    end
    function K.HarmCharge(a,v,harm,oldGuilt,modeMultiplier)
        if not K.Active() then return nil end
        if K.Excluded(a) or K.Excluded(v) then return 0,0 end
        local value=K.Value(K.Karma(v)); if not value then return nil end
        local life=K.GetLife(v); local pair=life.attackers[a]
        if not pair or life.settled or not v:Alive() then return 0,0 end
        local retaliation=zb.GuiltTable[v] and zb.GuiltTable[v][a] or 0
        pair.chargeEligible=modeMultiplier~=0 and retaliation<1
        if not pair.chargeEligible or value>=0 then return 0,0 end
        local before=pair.harm or 0
        pair.harm=math.min(10,before+math.max(0,K.Finite(harm) and harm or 0))
        -- The requested fixed curve replaces old armed/class/variant price multipliers.
        -- Explicit no-karma modes, zero multipliers and native defence exemptions remain.
        local charge=math.min(-value*(pair.harm-before)/10, math.max(0,-value-pair.charged))
        return charge,oldGuilt
    end
    function K.RecordCharge(a,v,before,after)
        local life=K.lives[v]; local pair=life and life.attackers[a]
        if pair and K.Finite(before) and K.Finite(after) then
            pair.charged=pair.charged+math.max(0,before-after)
        end
    end
    function K.Change(a,delta)
        local before=K.Karma(a); if not before or not K.Finite(delta) then return 0 end
        local maximum=zb and zb.MaxKarma or 120
        a.Karma=math.Clamp(before+delta,-60,maximum); a:SetNetVar("Karma",a.Karma)
        if a.guilt_SetValue then a:guilt_SetValue(a.Karma) end
        return a.Karma-before
    end
    function K.ModeAllowsCharge(a,v)
        local mode=CurrentRound()
        if not isfunction(mode.GuiltCheck) then return true end
        local ok,mul=pcall(mode.GuiltCheck,a,v,0,0,0)
        return ok and mul~=0
    end
    function K.BountyEligible(a,v)
        return playerEntity(a) and playerEntity(v) and a~=v and not a:IsBot() and not v:IsBot()
            and K.Identity(a)~=K.Identity(v) and not K.Excluded(a) and not K.Excluded(v)
            and not K.claimed[K.Identity(v)]
    end
    function K.RefundLedger(a,v,change)
        zb.HarmDoneKarma[v]=zb.HarmDoneKarma[v] or {}
        zb.HarmDoneKarma[v][a]=math.max(0,(zb.HarmDoneKarma[v][a] or 0)-change)
    end
    function K.Settle(v,attacker)
        local life=K.lives[v]
        if not K.Active() or not life or life.settled or life.round~=K.RoundKey() then return end
        if life.suicideAt and CurTime()-life.suicideAt<1 then return end
        if life.selfDamageAt and CurTime()-life.selfDamageAt<1 then return end
        if attacker==v then
            -- ZCity calls Kill() for lethal organ failure; that is not a user suicide.
            if not v.organism or v.organism.alive~=false then return end
            attacker=nil
        end
        local a=playerEntity(attacker) and attacker or nil
        if not a and (not v.organism or v.organism.alive~=false) then return end
        if not a then
            local best=0
            for source,pair in pairs(life.attackers) do
                if playerEntity(source) and CurTime()-pair.time<=120 and (pair.contribution or 0)>best then
                    a=source; best=pair.contribution
                end
            end
        end
        local pair=a and life.attackers[a]
        if not pair or not playerEntity(a) or CurTime()-pair.time>120 then return end
        if K.Excluded(a) or K.Excluded(v) then return end
        local value=K.Value(K.Karma(v)); if not value then return end
        life.settled=true
        local wanted=0
        if value>0 and K.BountyEligible(a,v) then
            K.claimed[K.Identity(v)]=true; wanted=value
        elseif value<0 and pair.chargeEligible then wanted=value end
        -- Credit back this attacker's partial charges before settling the kill price.
        -- Exempt enemy/defence kills never acquire a new negative charge.
        if value<0 and not pair.chargeEligible then return end
        local refundable=zb.HarmDoneKarma[v] and zb.HarmDoneKarma[v][a] or 0
        pair.charged=math.min(pair.charged,math.max(0,refundable))
        local adjustment=wanted+pair.charged
        local changed=K.Change(a,adjustment)
        local refund=math.min(math.max(changed,0),pair.charged)
        K.RefundLedger(a,v,changed<0 and changed or refund)
        K.lastSettlement={attacker=K.Identity(a),victim=K.Identity(v),karma=K.Karma(v),
            price=wanted,adjustment=changed,round=life.round,time=os.time()}
        if ZCityGuiltJustice then ZCityGuiltJustice.Log("bounty_settlement",K.lastSettlement) end
        -- Preserve the existing below-zero enforcement on a newly charged killing blow.
        if a.Karma<=0 and not a:IsAdmin() and not a:IsSuperAdmin()
            and not timer.Exists("simplewaitforkarmadrop"..a:EntIndex()) then
            if a.guilt_SetValue then a:guilt_SetValue(10) end
            if ULib and ULib.addBan then
                ULib.addBan(a:SteamID(),60,"Karma exhausted by friendly kills.",a:Nick(),"System")
            else a:Ban(60,false); a:Kick("Karma exhausted by friendly kills.") end
        end
        K.Publish()
    end
    K.pending=K.pending or setmetatable({}, {__mode="k"})
    hook.Add("PreHomigradDamage","ZCityKarmaBounties_LethalContext",function(v,info,group,body)
        v=ZCityFFBrain and (ZCityFFBrain.PlayerBody(v) or ZCityFFBrain.PlayerBody(body)) or v
        local a=ZCityFFBrain and ZCityFFBrain.Attacker(info) or info:GetAttacker()
        if K.Active() and playerEntity(v) and playerEntity(a) and v:Alive() and a~=v
            and info:GetDamage()>0 and not K.Excluded(v) and not K.Excluded(a) then
            K.pending[v]={attacker=a,tick=engine.TickCount()}
        end
    end,-2)
    hook.Add("PlayerDeath","ZCityKarmaBounties_Settle",function(v,inf,a)
        local pending=K.pending[v]
        if (a==v or not playerEntity(a)) and v.organism and v.organism.alive==false
            and pending and pending.tick==engine.TickCount() then a=pending.attacker end
        K.pending[v]=nil
        if K.Active() and playerEntity(a) and a~=v and not K.Excluded(a) and not K.Excluded(v) then
            local life=K.GetLife(v)
            if not life.attackers[a] then
                local kind=K.Kind(CurrentRound())
                local allied=kind=="homicide" and ((not not a.isTraitor)==(not not v.isTraitor))
                    or kind=="team" and a:Team()==v:Team()
                life.attackers[a]={charged=0,time=CurTime(),contribution=1,
                    chargeEligible=allied and K.ModeAllowsCharge(a,v) and not (v.Guilt and v.Guilt>1) and not a:IsBerserk()
                        and ((zb.GuiltTable[v] and zb.GuiltTable[v][a]) or 0)<1}
            end
        end
        K.Settle(v,a)
    end,-2)
    hook.Add("PlayerSilentDeath","ZCityKarmaBounties_NoSilentReward",function(v)
        local life=K.lives[v]; if life then life.settled=true end
    end,-2)
    hook.Add("CanPlayerSuicide","ZCityKarmaBounties_NoSuicideReward",function(v)
        if K.Active() then K.GetLife(v).suicideAt=CurTime() end
    end,-2)
    hook.Add("PlayerSpawn","ZCityKarmaBounties_NewLife",function(v)
        if OverrideSpawn or (ZCityPillCompat and IsValid(ZCityPillCompat.Morph(v))) then return end
        K.lives[v]=nil; K.pending[v]=nil
    end)
    function K.BeginPill(v,info)
        if not K.Active() or not playerEntity(v) or not v:Alive() then return nil end
        local a=ZCityFFBrain and ZCityFFBrain.Attacker(info)
        if not playerEntity(a) or a==v or K.Excluded(a) or K.Excluded(v) then return nil end
        local kind=K.Kind(CurrentRound())
        local allied=kind=="homicide" and ((not not a.isTraitor)==(not not v.isTraitor))
            or kind=="team" and a:Team()==v:Team()
        local morph=ZCityPillCompat and ZCityPillCompat.Morph(v)
        local health=IsValid(morph) and morph.formTable and morph.formTable.health
        return {a=a,v=v,allied=allied,hp=v:Health(),maximum=math.max(tonumber(health) or v:GetMaxHealth(),v:Health(),1)}
    end
    function K.EndPill(context,info,loss,killed)
        if not context or loss<=0 then return end
        local a,v=context.a,context.v
        if not playerEntity(a) or not playerEntity(v) then return end
        local harm=math.min(10,loss/context.maximum*10)
        local pair=K.Observe(a,v,info,harm,true); if not pair then return end
        if context.allied and K.ModeAllowsCharge(a,v) and not ZCityGuiltJustice.Defending(a,v) and not (v.Guilt and v.Guilt>1) then
            zb.GuiltTable[v]=zb.GuiltTable[v] or {}; zb.GuiltTable[a]=zb.GuiltTable[a] or {}
            pair.chargeEligible=true
            local cost,guilt=K.HarmCharge(a,v,harm,harm*6,1)
            if cost and cost>0 then
                local before=K.Karma(a); K.Change(a,-cost)
                K.RecordCharge(a,v,before,K.Karma(a)); K.RefundLedger(a,v,K.Karma(a)-before)
                a.Guilt=(a.Guilt or 0)+guilt
                zb.GuiltTable[a][v]=(zb.GuiltTable[a][v] or 0)+guilt
            end
        end
        -- A creature that merely unmorphs is not a player kill and pays no bounty.
        if killed and not v:Alive() then K.Settle(v,a) end
    end
    function K.Publish()
        K.RefreshRound()
        SetGlobalBool("zkb_live",K.Active()==true)
        SetGlobalFloat("zkb_max_karma",zb and zb.MaxKarma or 120)
        SetGlobalString("zkb_kind",K.Kind(isfunction(CurrentRound) and CurrentRound()) or "")
        for _,p in ipairs(player.GetAll()) do
            local karma=K.Karma(p)
            if karma then
                local exempt=not not K.Excluded(p)
                if p:GetNW2Bool("zkb_exempt")~=exempt then p:SetNW2Bool("zkb_exempt",exempt) end
                if math.abs(p:GetNW2Float("zkb_karma",-999)-karma)>0.0001 then p:SetNW2Float("zkb_karma",karma) end
                local available=p:Alive() and p:Team()<1000 and not p:IsBot()
                    and not K.Excluded(p) and not K.claimed[K.Identity(p)]
                if p:GetNW2Bool("zkb_open")~=available then p:SetNW2Bool("zkb_open",available) end
            end
        end
    end
    -- Reconcile only confirmed current-life deductions during the first hot activation.
    function K.AdoptCurrentLifeCharges()
        if K.adopted then return end
        K.adopted=true; K.RefreshRound()
        if not K.Active() or not ZCITY_GUILT or not ZCITY_GUILT.Data then return end
        for _,v in ipairs(player.GetAll()) do
            local data=ZCITY_GUILT.Data[v:SteamID64()]
            if v:Alive() and istable(data) and istable(data.karmaBaseline) and not K.Excluded(v) then
                local life=K.GetLife(v)
                for a,total in pairs(zb.HarmDoneKarma[v] or {}) do
                    if playerEntity(a) and a~=v and K.Finite(total) then
                        local entry=data.attackers and data.attackers[a:SteamID64()]
                        local baseline=tonumber(data.karmaBaseline[a:SteamID64()]) or 0
                        local charged=math.max(0,total-baseline)
                        if charged>0 and entry and CurTime()-(entry.last or 0)<120 then
                            life.attackers[a]={charged=charged,chargeEligible=true,
                                contribution=tonumber(entry.harm) or 1,time=entry.last}
                        end
                    end
                end
            end
        end
    end
    K.JusticeLoading=true
    include("zc_guilt_justice/runtime.lua")
    include("zc_guilt_justice/menu.lua")
    K.JusticeLoading=nil
    timer.Create("ZCityKarmaBounties_Public",0.5,0,K.Publish)
    hook.Add("PlayerDisconnected","ZCityKarmaBounties_Cleanup",function(p) K.lives[p]=nil end)
    concommand.Add("zc_karma_bounty_status",function(p)
        if IsValid(p) and not p:IsAdmin() then return end
        print("[KarmaBounty]",K.Version,"active",K.Active(),"round",K.RoundKey())
        for _,point in ipairs(knots) do print("[KarmaBounty] target",point[1],"value",K.Value(point[1])) end
    end)
    K.Publish()
    ZCityMetaSafety.Tick()
else
    function K.Karma(p)
        local n=p:GetNW2Float("zkb_karma",-999)
        return n~=-999 and K.Finite(n) and n or nil
    end
    function K.Preview(viewer,target)
        if not GetGlobalBool("zkb_live",false) then return end
        if viewer:GetNW2Bool("zkb_exempt",false) or target:GetNW2Bool("zkb_exempt",false) then return end
        local value=K.Value(K.Karma(target))
        if value and value>0 and target:GetNW2Bool("zkb_open",false) then
            return "BOUNTY",1
        end
    end
    local colors={[-1]=Color(255,165,135),[0]=Color(210,210,210),[1]=Color(140,235,155)}
    local fontHeight=0
    function K.DrawPreview(target,x,y,name,alpha)
        local viewer=LocalPlayer()
        local text,sign=K.Preview(viewer,target); if not text then return end
        local size=math.max(12,math.floor(ScreenScale(7)))
        if fontHeight~=size then
            fontHeight=size; surface.CreateFont("ZCKarmaBountySmall",{font="Bahnschrift",size=size,weight=500})
        end
        surface.SetFont("HomigradFontLarge")
        local _,nameHeight=surface.GetTextSize(name)
        local color=colors[sign]; color.a=math.Clamp(alpha,0,255)
        draw.SimpleTextOutlined(text,"ZCKarmaBountySmall",x,y+30+nameHeight+3,
            color,TEXT_ALIGN_CENTER,TEXT_ALIGN_TOP,1,Color(0,0,0,color.a))
    end
    hook.Add("HUDPaint","ZCityKarmaBounties_TargetLine",function()
        if not GetGlobalBool("zkb_live",false) then return end
        local p=LocalPlayer()
        if not playerEntity(p) or not p:Alive() or p:Team()>=1000 then return end
        if p.organism and p.organism.otrub then return end
        if p:GetNetVar("disappearance",nil) or not hg or not hg.eyeTrace then return end
        local tr=hg.eyeTrace(p)
        if not tr or not tr.Hit or not IsValid(tr.Entity) then return end
        local ent=tr.Entity
        if not (ent:IsPlayer() or ent:IsRagdoll()) then return end
        if ent.PlayerClassName=="sc_infiltrator" or ent:GetNetVar("disappearance",nil) then return end
        local target=ent:IsPlayer() and ent or (hg.RagdollOwner and hg.RagdollOwner(ent))
        if not playerEntity(target) or target==p or not target:Alive() or target:Team()>=1000 then return end
        if ent~=target and target:GetNWEntity("FakeRagdoll")~=ent then return end
        local screen=tr.HitPos:ToScreen(); if not screen.visible then return end
        local name=ent:GetPlayerName() or ""; if name=="" then return end
        local alpha=255*math.max(math.min(1-tr.Fraction,1),0.1)*1.5
        K.DrawPreview(target,screen.x,screen.y,name,alpha)
    end)
end
-- Normal loads are silent. Use the explicit status command for diagnostics.

if CLIENT then
-- Read-only incident summaries; every action is validated by the server.
if not CLIENT then return end
ZCityGuiltReview = ZCityGuiltReview or {}
local C=ZCityGuiltReview
C.Version="20260916.1"
if IsValid(C.frame) then C.frame:Remove() end
local rows={}
local function send(row,action)
    net.Start("zc_guilt_action_v3")
    net.WriteUInt(row.caseid,32)
    net.WriteString(row.steamid64)
    net.WriteString(action)
    net.SendToServer()
end
local function text(parent,value,size)
    local p=vgui.Create("DLabel",parent)
    p:Dock(TOP);p:DockMargin(12,5,12,5);p:SetTall(size or 25)
    p:SetText(value);p:SetWrap(true);p:SetAutoStretchVertical(true)
    return p
end
local function button(parent,label,fn,enabled)
    local b=vgui.Create("DButton",parent)
    b:Dock(TOP);b:DockMargin(12,4,12,4);b:SetTall(34)
    b:SetText(label);b:SetEnabled(enabled~=false);b.DoClick=fn
    return b
end
function C.Show(inputRows)
    if GetGlobalBool("zc_meta_review_hold",false) then inputRows={} end
    rows=inputRows
    if IsValid(C.frame) then C.frame:Remove() end
    if #rows==0 then return end
    local f=vgui.Create("DFrame");C.frame=f
    f:SetSize(math.min(860,ScrW()-40),math.min(570,ScrH()-60))
    f:Center();f:SetTitle("Incident review and forgiveness");f:MakePopup()
    local list=vgui.Create("DListView",f)
    list:Dock(LEFT);list:SetWide(280);list:DockMargin(8,8,8,8)
    list:SetMultiSelect(false);list:AddColumn("Player");list:AddColumn("State"):SetFixedWidth(88)
    local detail=vgui.Create("DScrollPanel",f);detail:Dock(FILL);detail:DockMargin(0,8,8,8)
    local function select(row)
        detail:Clear()
        text(detail,row.name or "Disconnected player",30)
        text(detail,string.format("Target karma used: %.1f",row.victimKarma or 0))
        text(detail,string.format("Automatic loss: %.1f karma",row.loss or 0))
        text(detail,string.format("Bounty paid: +%.1f karma",row.bounty or 0))
        text(detail,string.format("Available refund: %.1f karma",row.refundable or 0))
        if not row.decided then
            if row.canForgive then
                button(detail,string.format("Forgive (+%.1f karma)",row.refundable or 0),function()send(row,"forgive")end)
            end
            if row.respectEligible then
                local n=row.respectReward or 0
                button(detail,n>0 and string.format("Give Respect (+%.1f karma)",n) or "Give Respect (acknowledgement)",function()send(row,"respect")end)
            end
            button(detail,(row.karma or 0)>0 and "Keep penalty" or "Acknowledge",function()send(row,"keep")end)
        else text(detail,"Decision saved: "..tostring(row.decision)) end
        if row.canReport then button(detail,"Report abuse to staff",function()send(row,"report")end) end
        text(detail,"Closing or ignoring this menu adds no penalty. Forgiveness returns only this incident's remaining loss. It does not heal injuries or revoke a valid bounty.",70)
    end
    for _,row in ipairs(rows) do
        local line=list:AddLine(row.name or "Disconnected player",row.decided and "Reviewed" or "Pending")
        line.review=row
    end
    list.OnRowSelected=function(_,_,line)select(line.review)end
    select(rows[1])
end
net.Receive("zc_guilt_review_v3",function()
    local raw=net.ReadString();if #raw>55000 then return end
    local data=util.JSONToTable(raw,false,true)
    if not istable(data) or #data>64 then return end
    for _,r in ipairs(data) do
        if not istable(r) or not isnumber(r.caseid) or not isstring(r.steamid64) then return end
    end
    C.Show(data)
end)
hook.Remove("HUDPaint","ZCITY_GUILT_Prompt")
hook.Remove("Think","ZCITY_GUILT_CloseResolvedMenu")
local pressed=false
hook.Add("HUDPaint","ZCityGuiltReview_Prompt",function()
    if not (ZCITY_GUILT and ZCITY_GUILT.Config and ZCITY_GUILT.Config.MenuEnabled == true) then pressed=false;return end
    if GetGlobalBool("zc_meta_review_hold",false) then pressed=false;return end
    local p=LocalPlayer()
    if not IsValid(p) or p:GetNWInt("ZCITY_GUILT_PENDING_COUNT",0)<=0 then pressed=false;return end
    if IsValid(C.frame) or gui.IsGameUIVisible() or IsValid(vgui.GetKeyboardFocus()) then pressed=false;return end
    draw.SimpleText("Press F to review this incident","DermaDefaultBold",ScrW()/2,ScrH()-42,color_white,TEXT_ALIGN_CENTER)
    local down=input.IsKeyDown(KEY_F)
    if down and not pressed then RunConsoleCommand("zcity_guilt_menu") end
    pressed=down
end)
local function installReviewPrompt()
    hook.Remove("HUDPaint","ZCITY_GUILT_Prompt")
    hook.Remove("Think","ZCITY_GUILT_CloseResolvedMenu")
end
hook.Add("InitPostEntity","ZCityGuiltReview_Install",installReviewPrompt)
hook.Add("OnReloaded","ZCityGuiltReview_Reload",function()timer.Simple(0,installReviewPrompt)end)
timer.Simple(0,installReviewPrompt)

hook.Add("Think","ZCityGuiltReview_MetaGuard",function()
    if GetGlobalBool("zc_meta_review_hold",false) and IsValid(C.frame) then C.frame:Remove() end
end)

end
