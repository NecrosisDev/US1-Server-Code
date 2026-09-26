-- Original HMCD Alt+E abilities must not inherit the optional interaction trial gate.
-- Server-only compatibility repair; generated native bodies preserve current MAIN behavior.
ZCLegacyAltE=ZCLegacyAltE or {Necks=setmetatable({}, {__mode="k"})}
local P=ZCLegacyAltE
P.Version="20260922.2"
local function install()
    local I=ZCityInteractions
    local MODE=zb and zb.modes and zb.modes.hmcd
    if not I or not MODE or not I.BeginDisarm or not MODE.StartBreakingOtherNeck then return false end
    if I.Version~="20260920.interactions3" then return false end
    if P.Mode==MODE and P.InstalledVersion==P.Version
        and MODE.StartBreakingOtherNeck==P.StartNeck
        and I.BeginDisarm==P.BeginDisarm and I.DisarmValid==P.DisarmValid then return true end
    local oldStopNeck=MODE.StopBreakingOtherNeck
    local oldContinueNeck=MODE.ContinueBreakingOtherNeck
    local function legacyPolicy(a,intent,target)
        if not IsValid(a) or not a:IsPlayer() or not a:Alive() then return false end
        local mode,name=I.PolicyContext()
        if name~="hmcd" or mode~=MODE or (intent~="legacy_neck" and intent~="disarm") then return false end
        -- The existing adapter validates the role assignment's life, round, class and mode.
        local caps=I.ModeAdapters.hmcd(a,mode)
        if not caps[intent] then return false end
        return I.RoundAllowsHostility()
    end
    local function ready(a)
        local w=IsValid(a) and a:GetActiveWeapon()
        return IsValid(a) and a:Alive() and I.HandsAvailable(a) and not a.organism.otrub
            and not IsValid(a.FakeRagdoll) and not a:InVehicle() and IsValid(w)
            and w:GetClass()=="weapon_hands_sh" and not IsValid(a:GetNetVar("carryent")) and not IsValid(a:GetNetVar("carryent2"))
    end
    local function contextualAllowed(a)
        local cv=GetConVar("zsf_enabled")
        local stealth=ZCityStealth
        return cv and cv:GetBool() and I.TrialAllowed(a) and stealth and stealth.TrialAllowed(a)
    end
    local function disarmPolicy(a,v,contextual)
        if contextual then return contextualAllowed(a) and I.PolicyAllowed(a,"disarm",v) end
        return legacyPolicy(a,"disarm",v)
    end
    local function disarmHostile(a,v,session,contextual)
        if contextual then return contextualAllowed(a) and I.HostileAllowed(a,v,session,"disarm") end
        if not legacyPolicy(a,"disarm",v) or not I.Available(a,session) then return false end
        local receiver=I.Receiver(v)
        if receiver and (I.Recovery[receiver] or 0)>CurTime() and not session then return false end
        return true
    end

function MODE.CanPlayerBreakOtherNeck(ply, aim_ent)
    if SERVER and ZCityInteractions and not legacyPolicy(ply,"legacy_neck",ZCityInteractions.Receiver(aim_ent)) then return false end
	if(aim_ent:IsRagdoll())then
		local bone_id = aim_ent:LookupBone("ValveBiped.Bip01_Head1")
		
		if(bone_id)then
			local bone_matrix = aim_ent:GetBoneMatrix(bone_id)
			
			if(bone_matrix)then
				local pos, ang = bone_matrix:GetTranslation(), bone_matrix:GetAngles()
				local other_normal = -ang:Right()
				local ply_normal = pos - ply:GetShootPos()
				local dist_z = math.abs(pos.z - ply:GetShootPos().z)
				
				if(dist_z < 50) then
					ply_normal:Normalize()
					
					local ang_diff = -(math.deg(math.acos(ply_normal:DotProduct(other_normal))) - 180)
					
					if(ang_diff < 100)then
						return true
					end
				end
			end
		end
	elseif(aim_ent:IsPlayer())then
		local other_angle = aim_ent:EyeAngles()[2]
		local ply_angle = (aim_ent:GetPos() - ply:GetPos()):Angle()[2] --ply:EyeAngles()[2]
		local ang_diff = math.abs(math.AngleDifference(other_angle, ply_angle))
		
		if(ang_diff < 100)then
			return true
		end
	end
	
	return false
end

local function nativeStartNeck(ply, other_ply)

	ply.Ability_NeckBreak = {
		Victim = other_ply,
		Progress = 0,
	}
	other_ply.BeingVictimOfNeckBreak = true
	
	if(SERVER)then
		other_ply:ViewPunch(Angle(0, -10, -10))
		
		net.Start("HMCD_BeingVictimOfNeckBreak")
			net.WriteBool(true)
		net.Send(other_ply)
		
		net.Start("HMCD_BreakingOtherNeck")
			net.WriteBool(true)
			net.WriteEntity(ply)
			net.WriteEntity(other_ply)
		net.SendPVS(ply:GetShootPos())
	end
end

local function nativeBreakNeck(ply, other_ply, aim_ent)
	if(other_ply:Alive())then
		other_ply:Kill()
		other_ply:ViewPunch(Angle(0, 0, -10))
		
		if aim_ent.organism then aim_ent.organism.spine3 = 1 end
		
		aim_ent:EmitSound("neck_snap_01.wav", 60, 100, 1, CHAN_AUTO)

		local life,round=I.PolicyLives[other_ply],I.PolicyRound
		timer.Simple(0.1, function()
            if not IsValid(other_ply) or I.PolicyLives[other_ply]~=life or I.PolicyRound~=round then return end
			local ent = other_ply:GetNWEntity("RagdollDeath")

			if IsValid(ent) then
				local headBone,spineBone=ent:LookupBone("ValveBiped.Bip01_Head1"),ent:LookupBone("ValveBiped.Bip01_Spine2")
                if not headBone or not spineBone then return end
                ent:RemoveInternalConstraint(ent:TranslateBoneToPhysBone(headBone))

				local spine = ent:TranslateBoneToPhysBone(ent:LookupBone("ValveBiped.Bip01_Spine2"))
				local head = ent:TranslateBoneToPhysBone(ent:LookupBone("ValveBiped.Bip01_Head1"))

				local pspine = ent:GetPhysicsObjectNum(spine)
				local phead = ent:GetPhysicsObjectNum(head)

				if not IsValid(pspine) or not IsValid(phead) then return end
				local lpos, lang = WorldToLocal(phead:GetPos() + phead:GetAngles():Forward() * -2 + phead:GetAngles():Up() * -1.5, angle_zero, pspine:GetPos(), pspine:GetAngles())
                
				phead:SetPos(pspine:GetPos() + pspine:GetAngles():Forward() * 12.9 + pspine:GetAngles():Right() * -1)

				local cons = constraint.AdvBallsocket(ent, ent, spine, head, lpos, nil, 0, 0, -55, -90, -50, 55, 35, 50, 0, 0, 0, 0, 0)
			end
		end)
	end
end

function MODE.CanPlayerDisarmOther(ply, aim_ent)
    if SERVER and ZCityInteractions and not legacyPolicy(ply,"disarm",ZCityInteractions.Receiver(aim_ent)) then return false end
	if(aim_ent:IsRagdoll())then
		local bone_id = aim_ent:LookupBone("ValveBiped.Bip01_Spine2")
		
		if(bone_id)then
			local bone_matrix = aim_ent:GetBoneMatrix(bone_id)
			
			if(bone_matrix)then
				local pos, ang = bone_matrix:GetTranslation(), bone_matrix:GetAngles()
				local other_normal = ang:Right()
				local ply_normal = pos - ply:GetShootPos()
				local dist_z = math.abs(pos.z - ply:GetShootPos().z)
				
				if(dist_z < 50) then
					ply_normal:Normalize()
					
					local ang_diff = -(math.deg(math.acos(ply_normal:DotProduct(other_normal))) - 180)
					
					if(ang_diff < 90)then
						return 2
					else
						return 1.5
					end
				end
			end
		end
	elseif(aim_ent:IsPlayer())then
		local other_angle = aim_ent:EyeAngles()[2]
		local ply_angle = (aim_ent:GetPos() - ply:GetPos()):Angle()[2] --ply:EyeAngles()[2]
		local ang_diff = math.abs(math.AngleDifference(other_angle, ply_angle))
		
		if(ang_diff < 70)then
			return 2
		else
			return 1.5
		end
	end
	
	return false
end

function I.DisarmValid(s,predecessor)
    if not s or s.done or not ready(s.a) or not IsValid(s.v) or not s.v:Alive() then return false end
    if s.a:GetActiveWeapon()~=s.weapon or s.v:GetActiveWeapon()~=s.targetWeapon then return false end
    if s.scale and (s.a:GetModelScale()~=1 or s.a:GetModel()~=s.model or s.a.organism~=s.organism) then return false end
    if not disarmHostile(s.a,s.v,predecessor or s,s.contextual) then return false end
    local body=IsValid(s.v.FakeRagdoll) and s.v.FakeRagdoll or s.v
    if body~=s.targetBody or not I.Available(body,s) then return false end
    if s.a:GetPos():DistToSqr(body:GetPos())>90*90 then return false end
    local trace=util.TraceLine({start=s.a:EyePos(),endpos=body:WorldSpaceCenter(),filter=s.a,mask=MASK_SOLID})
    return not trace.Hit or trace.Entity==body
end

function I.BeginDisarm(a,v,mode,contextual,predecessor,dropItem)
    if I.DisarmSessions[a] or not ready(a) or not IsValid(v) or v==a or not v:IsPlayer() or not v:Alive() then return false end
    if contextual and not contextualAllowed(a) then return false end
    local stealth=ZCityStealth
    if predecessor and (not contextual or not stealth or not stealth.CanSoloHandoff(a,predecessor,false,dropItem)) then return false end
    local targetWeapon=v:GetActiveWeapon()
    if not IsValid(targetWeapon) or targetWeapon.NoDrop or targetWeapon:GetClass()=="weapon_hands_sh" then return false end
    if not disarmHostile(a,v,predecessor,contextual) or not I.Available(v) or (I.Recovery[v] or 0)>CurTime() then return false end
    local stamina=a.organism.stamina
    if not stamina or (stamina[1] or 0)<8 then return false end
    local body=IsValid(v.FakeRagdoll) and v.FakeRagdoll or v
    local s={a=a,v=v,weapon=a:GetActiveWeapon(),targetWeapon=targetWeapon,targetBody=body,mode=mode,
        system="disarm",phase="attempt",policyIntent="disarm",contextual=contextual==true,start=CurTime(),
        cancel=function(session)
            if session.done or session.ending then return end
            session.ending=true
            local ok,err=pcall(mode.StopDisarmingOther,a)
            I.EndDisarm(a)
            if not ok then ErrorNoHalt("[Interactions] Disarm cleanup failed: "..tostring(err).."\n") end
        end}
    if not I.DisarmValid(s,predecessor) or not mode.CanPlayerDisarmOther(a,body) or not mode.CanPlayerDisarmOtherPly(a,v) then return false end
    local actors={a,v} if body~=v then actors[#actors+1]=body end
    s.actors=actors
    if not I.Reserve(s,actors,predecessor) then return false end
    I.DisarmSessions[a]=s I.DisarmFollowups[a]=nil
    if predecessor then
        s.scale=predecessor.scales[a] s.model=predecessor.models[a] s.organism=a.organism
        predecessor.scales[a]=nil I.TransferScale(predecessor,s,a)
        stealth.End(predecessor,nil,true)
        if s.done then return false end
        if not I.DisarmValid(s) then s.cancel(s) return false end
    end
    for _,p in ipairs({a,v}) do
        p:SetNWString("zci_native","disarm") p:SetNWBool("zci_native_initiator",p==a)
        p:SetNWEntity("zci_native_partner",p==a and v or a)
    end
    return true
end

function I.CommitDisarm(a,v)
    local s=I.DisarmSessions[a]
    if not s or s.v~=v or s.committed or CurTime()-s.start<.45 or not I.DisarmValid(s) then return false end
    local stamina=a.organism.stamina
    if not stamina or (stamina[1] or 0)<8 then s.cancel(s) return false end
    s.committed=true s.phase="commit" stamina.subadd=(stamina.subadd or 0)+8
    I.DisarmFollowups[a]={v=v,life=I.PolicyLives[v] or 0,actorLife=I.PolicyLives[a] or 0,contextual=s.contextual,round=I.PolicyRound,at=CurTime()}
    return true
end

function I.DisarmFollowupAllowed(a,v)
    local row=I.DisarmFollowups[a]
    return row and row.v==v and row.round==I.PolicyRound and row.life==(I.PolicyLives[v] or 0)
        and row.actorLife==(I.PolicyLives[a] or 0) and CurTime()-row.at<.2 and ready(a)
        and I.Available(a) and I.Available(v) and disarmPolicy(a,v,row.contextual)
end

    local function neckValid(s)
        if not s or s.done or not ready(s.a) or not IsValid(s.v) or not s.v:Alive() then return false end
        if s.round~=I.PolicyRound or s.life~=(I.PolicyLives[s.a] or 0) or s.vlife~=(I.PolicyLives[s.v] or 0)
            or s.organism~=s.a.organism or s.vorganism~=s.v.organism then return false end
        if not s.a:KeyDown(IN_WALK) or not s.a:KeyDown(IN_USE) then return false end
        if not legacyPolicy(s.a,"legacy_neck",s.v) or not I.Available(s.a,s) or not I.Available(s.v,s) then return false end
        if (IsValid(s.v.FakeRagdoll) and s.v.FakeRagdoll or s.v)~=s.body or not I.Available(s.body,s) then return false end
        local body,victim=MODE.GetPlayerTraceToOtherVictim(s.a,s.v)
        return IsValid(body) and body==s.body and victim==s.v and MODE.CanPlayerBreakOtherNeck(s.a,body)
    end
    function MODE.StopBreakingOtherNeck(a)
        local s=P.Necks[a]
        oldStopNeck(a)
        if not s then return end
        P.Necks[a]=nil s.done=true
        I.EndObservedControl(s) I.Release(s) I.Protect(s.v,2)
    end
    function MODE.StartBreakingOtherNeck(a,v)
        if P.Necks[a] or not ready(a) or not IsValid(v) or not v:IsPlayer() or v==a or not v:Alive() then return end
        if not I.Available(a) or not I.Available(v) or (I.Recovery[v] or 0)>CurTime() then return end
        local body=IsValid(v.FakeRagdoll) and v.FakeRagdoll or v
        local s={a=a,v=v,body=body,system="legacy_neck",phase="control",start=CurTime(),
            round=I.PolicyRound,life=I.PolicyLives[a] or 0,vlife=I.PolicyLives[v] or 0,
            organism=a.organism,vorganism=v.organism}
        s.cancel=function() MODE.StopBreakingOtherNeck(a) end
        if not neckValid(s) or not I.Reserve(s,{a,v,body}) then return end
        P.Necks[a]=s
        local ok,err=pcall(nativeStartNeck,a,v)
        if not ok then MODE.StopBreakingOtherNeck(a);ErrorNoHalt("[Legacy Alt+E] "..tostring(err).."\n");return end
        I.StartObservedControl(s,"dangerous_melee","danger")
    end
    function MODE.BreakOtherNeck(a,v,body)
        local s=P.Necks[a]
        if not neckValid(s) or s.v~=v or s.body~=body or s.committed or CurTime()-s.start<.30
            or not a.Ability_NeckBreak or a.Ability_NeckBreak.Progress<100 then return false end
        s.committed=true
        return I.WithObservedDamage(s,a,v,function() return nativeBreakNeck(a,v,body) end)
    end
    function MODE.ContinueBreakingOtherNeck(a)
        if not neckValid(P.Necks[a]) then MODE.StopBreakingOtherNeck(a);return end
        oldContinueNeck(a)
    end
    hook.Add("Think","ZCLegacyAltE.NeckLifetime",function()
        for a,s in pairs(P.Necks) do
            if not neckValid(s) or not a.Ability_NeckBreak or CurTime()-s.start>2 then MODE.StopBreakingOtherNeck(a)
            else I.StepObservedControl(s) end
        end
    end)
    for _,event in ipairs({"PlayerSpawn","PlayerDeath","PlayerSilentDeath","PlayerDisconnected"}) do
        hook.Add(event,"ZCLegacyAltE.NeckCleanup",function(p)
            for a,s in pairs(P.Necks) do if a==p or s.v==p then MODE.StopBreakingOtherNeck(a) end end
        end)
    end
    for _,event in ipairs({"ZB_EndRound","ZB_PreRoundStart","PreCleanupMap","ShutDown"}) do
        hook.Add(event,"ZCLegacyAltE.NeckRound",function()
            for a in pairs(P.Necks) do MODE.StopBreakingOtherNeck(a) end
        end)
    end
    hook.Add("PostEntityTakeDamage","ZCLegacyAltE.NeckInjury",function(p,dmg,took)
        if took and dmg:GetDamage()>0 then
            for a,s in pairs(P.Necks) do if not s.committed and (a==p or s.v==p) then MODE.StopBreakingOtherNeck(a) end end
        end
    end)
    P.Mode=MODE P.InstalledVersion=P.Version P.LegacyPolicyAllowed=legacyPolicy
    P.StartNeck=MODE.StartBreakingOtherNeck P.BeginDisarm=I.BeginDisarm P.DisarmValid=I.DisarmValid
    print("[Legacy Alt+E] installed",P.Version)
    return true
end
hook.Add("InitPostEntity","ZCLegacyAltE.Install",function() install() end)
-- Gamemode and addon loaders can replace these functions after autorun.
-- Keep the adapter attached while the native owners are loaded.
timer.Create("ZCLegacyAltE.InstallRetry",1,0,install)
install()
concommand.Add("zc_legacy_alt_e_status",function(p)
    if IsValid(p) and not p:IsAdmin() then return end
    local I=ZCityInteractions local mode=zb and zb.modes and zb.modes.hmcd
    print("[Legacy Alt+E] status",P.Version,P.InstalledVersion==P.Version and mode==P.Mode
        and mode.StartBreakingOtherNeck==P.StartNeck and I.BeginDisarm==P.BeginDisarm and I.DisarmValid==P.DisarmValid,
        "neck sessions",table.Count(P.Necks),"hostage",GetConVar("zch_gameplay_enabled"):GetString(),"stealth",GetConVar("zsf_enabled"):GetString())
end)
