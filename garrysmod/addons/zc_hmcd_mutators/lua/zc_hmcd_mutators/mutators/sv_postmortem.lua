-- One human death -> one native headcrab-zombie life. No zombie counts as a survivor.
local M = ZC_HMCD_MUTATORS
local ID, CLASS, NET = "postmortem", "headcrabzombie", "zc_postmortem"
local MODEL = "models/zcity/player/zombie_classic.mdl"
local DELAY, RETRY_WINDOW, SETTLE_WINDOW = 10, 20, 3
util.AddNetworkString(NET)
local function Scope(ctx)
    return not ctx.stopped and M.current == ctx and CurrentRound() == ctx.mode
        and ctx.mode.Type == ctx.variant and zb.ROUND_START == ctx.stamp
end
local function Actor(ctx, p)
    local s = ctx.data.players[p]
    return s and s.converted and not s.released
end
-- Resolve combat entities without treating an unrelated entity as a protected player.
local function CombatPlayer(ent)
    if not IsValid(ent) then return end
    if ent.IsPlayer and ent:IsPlayer() then return ent end
    local owner=hg.RagdollOwner(ent)
    if IsValid(owner) and owner:IsPlayer() then return owner end
    if IsValid(ent.ply) and ent.ply:IsPlayer() then return ent.ply end
    if ent.GetOwner then
        owner=ent:GetOwner()
        if IsValid(owner) and owner:IsPlayer() then return owner end
    end
end
local function ProtectedDamage(ctx,victim,damage,ent)
    if not Scope(ctx) then return false end
    local attacker=CombatPlayer(damage:GetAttacker()) or (damage.GetInflictor and CombatPlayer(damage:GetInflictor()))
    return Actor(ctx,attacker) or Actor(ctx,CombatPlayer(victim)) or Actor(ctx,CombatPlayer(ent))
end
local function InstallKarmaGuards(ctx)
    local guards=ctx.data.karmaGuards or {}; ctx.data.karmaGuards=guards
    local function priority(event,id)
        local all=hook.GetULibTable and hook.GetULibTable()
        for rank,entries in pairs(all and all[event] or {}) do if entries[id] then return rank end end
        return 0
    end
    local specs={
        {event="HomigradDamage",id="GuiltReg"},
        {event="HomigradDamage",id="ZCITY_GUILT_TrackDamage"},
        {event="PostPlayerDeath",id="ZCITY_GUILT_FinalizeDeath",death=true},
        {event="Player_Death",id="ZCITY_GUILT_FinalizeDeathEarly",death=true},
        {event="PlayerDeath",id="ZCITY_GUILT_FinalizeDeathEngine",death=true,engine=true}
    }
    local function refresh()
        if not Scope(ctx) then return end
        for _,item in ipairs(specs) do
            local spec=item
            local id,event=spec.id,spec.event
            local fn=(hook.GetTable()[event] or {})[id]
            local before=guards[id]
            if type(fn)=="function" and (not before or fn~=before.wrapper) then
                local original=fn -- each wrapper owns its own delegate; never a mutable shared target
                local wrapper=function(victim,damage,hitgroup,ent,...)
                    if spec.death then
                        -- Never build a case for the zombie life, including cleanup deaths.
                        if Actor(ctx,CombatPlayer(victim)) then return end
                        if Scope(ctx) and spec.engine and Actor(ctx,CombatPlayer(hitgroup)) then
                            -- Keep other human attackers eligible; omit only the zombie killer.
                            return original(victim,damage,NULL,ent,...)
                        end
                        return original(victim,damage,hitgroup,ent,...)
                    end
                    if ProtectedDamage(ctx,victim,damage,ent) then
                        ctx.data.karmaBlocked=(ctx.data.karmaBlocked or 0)+1
                        return -- suppress only this guilt callback; other damage hooks still run
                    end
                    return original(victim,damage,hitgroup,ent,...)
                end
                local rank=priority(event,id)
                guards[id]={original=original,wrapper=wrapper,priority=rank,event=event}
                hook.Add(event,id,wrapper,rank)
                if before then ctx.data.karmaRepairs=(ctx.data.karmaRepairs or 0)+1 end
            end
        end
    end
    refresh()
    ctx.data.refreshKarma=refresh
    -- ULib is installed with ULX on this server. Its monitor runs before normal
    -- callbacks, so a reloaded GuiltReg is repaired before the next damage dispatch.
    -- Never return a value here or stop the entire HomigradDamage event.
    local monitor=ctx.prefix.."karma_monitor"
    local monitored={"HomigradDamage","PostPlayerDeath","Player_Death","PlayerDeath"}
    if hook.GetULibTable then for _,event in ipairs(monitored) do hook.Add(event,monitor,refresh,-2) end end
    ctx:Hook("PreHomigradDamage","karma_refresh",function() refresh() end)
    ctx:Cleanup(function()
        for _,event in ipairs(monitored) do
            if (hook.GetTable()[event] or {})[monitor]==refresh then hook.Remove(event,monitor) end
        end
        for id,guard in pairs(guards) do
            if (hook.GetTable()[guard.event] or {})[id]==guard.wrapper then
                hook.Add(guard.event,id,guard.original,guard.priority)
            end
        end
    end)
end
local function Excluded(ctx, p)
    return Actor(ctx, p) or (IsValid(p) and p.PlayerClassName == CLASS)
end
local function Identity(p)
    return p:IsBot() and ("bot:" .. p:UserID()) or p:SteamID64()
end
local function Sync(ctx, p, active)
    if not IsValid(p) then return end
    net.Start(NET)
    net.WriteUInt(M.generation % 4294967296, 32)
    net.WriteBool(active)
    net.WriteString(ctx.variant)
    net.WriteFloat(ctx.stamp) -- match ZCity RoundInfo timestamp precision exactly
    net.Send(p)
end
local function RestoreFlags(s)
    local p = s.ply
    if not IsValid(p) or not s.converted or s.released then return end
    -- Only restore fields still carrying our neutral zombie value.
    for _, key in ipairs({"isTraitor", "MainTraitor", "isPolice", "isGunner"}) do
        if p[key] == false then p[key] = s.flags[key] end
    end
    -- Never restore living traitor abilities to the corpse or to another spawn.
end
local function Retire(ctx, s, kill)
    if s.released then return end
    local p = s.ply
    ZC_POSTMORTEM_KARMA.Release(p)
    if IsValid(p) then
        if s.freezeOwned then p:Freeze(false); s.freezeOwned = nil end
        if s.hidden then p:SetNoDraw(false); s.hidden=nil end
        if kill and s.converted and p:Alive() and (s.phase == "rising" or p.PlayerClassName == CLASS) then
            p:KillSilent()
        end
        if kill and not p:Alive() then RestoreFlags(s) end
        if p.PlayerClassName == CLASS then p:SetPlayerClass("none") end
        -- Release zombie-only setup on every exit, including a new police/Guard life.
        -- Role flags above remain restricted to dead-player cleanup.
        if s.converted then
            if p.PreZombClass == s.preZombSet then p.PreZombClass = s.preZombOld end
            if p.SpeedGainMul == 70 then p.SpeedGainMul = s.speedOld end
        end
        Sync(ctx, p, false)
    end
    s.released = true
    s.phase = "spent"
end
local function Requirements(mode)
    if not player.classList or not player.classList[CLASS] or type(player.classList[CLASS].On) ~= "function"
        or not util.IsValidModel(MODEL) then return false, "Native ZCity headcrab zombie class/model is unavailable" end
    local hooks = hook.GetTable()
    if not hooks.HomigradDamage or type(hooks.HomigradDamage.GuiltReg) ~= "function" then
        return false, "Native karma damage hook is unavailable"
    end
    if type(mode.CheckAlivePlayers) ~= "function" or type(mode.EndRound) ~= "function"
        or type(zb.CheckAlive) ~= "function" then return false, "Native survivor counting is unavailable" end
    if not hg or not hg.CreateInv or not hg.weaponInv or not hg.weaponInv.Sync then
        return false, "Native inventory API is unavailable"
    end
    return true
end
local function BodyValid(p, body)
    if not IsValid(body) or not body:IsRagdoll() or body.ply ~= p then return false end
    local owner = hg.RagdollOwner(body)
    local networkOwner = body:GetNWEntity("ply")
    if IsValid(networkOwner) and networkOwner:Alive() and networkOwner.FakeRagdoll == body then return false end
    return not IsValid(owner) -- a corpse possessed/revived by another system is no longer ours to consume
end
-- Nearest positions first. Precompute the bounded 25-point search once.
local OFFSETS = {Vector(0,0,0)}
for _,radius in ipairs({32,64,96}) do
    for i=0,7 do
        local angle = i * math.pi / 4
        OFFSETS[#OFFSETS+1] = Vector(math.cos(angle)*radius, math.sin(angle)*radius, 0)
    end
end
local function Position(p, body)
    local bone = body:LookupBone("ValveBiped.Bip01_Pelvis")
    local matrix = bone and body:GetBoneMatrix(bone)
    local center = matrix and matrix:GetTranslation() or body:GetPos()
    if not isvector(center) or not M.Finite(center.x) or not M.Finite(center.y) or not M.Finite(center.z)
        or not util.IsInWorld(center) then return nil, "body position invalid or outside map" end
    local filter = {p,body}
    for _,offset in ipairs(OFFSETS) do
        local at = center + offset
        local ground = util.TraceLine({start=at+Vector(0,0,48), endpos=at-Vector(0,0,128), mask=MASK_PLAYERSOLID, filter=filter})
        if ground.Hit and not ground.StartSolid and not ground.AllSolid and not ground.HitSky and ground.HitNormal.z >= 0.65 then
            local pos = ground.HitPos + Vector(0,0,2)
            if util.IsInWorld(pos) then
                local hull = util.TraceHull({start=pos,endpos=pos,mins=Vector(-16,-16,0),maxs=Vector(16,16,72),mask=MASK_PLAYERSOLID,filter=filter})
                if not hull.Hit and not hull.StartSolid and not hull.AllSolid then
                    -- A clear destination alone could be on the other side of a wall/floor.
                    local path = util.TraceLine({start=center+Vector(0,0,16),endpos=pos+Vector(0,0,36),mask=MASK_PLAYERSOLID,filter=filter})
                    if not path.Hit and not path.StartSolid and not path.AllSolid then return pos end
                end
            end
        end
    end
    return nil, "no clear reachable standing space within 96 units of body"
end
local function ClearKit(p)
    p:StripWeapons(); p:StripAmmo()
    -- Rebuild slot limits without references to a previous human loadout.
    local slots = {}
    for category, slot in pairs(p.weaponInv or {}) do slots[category] = {limit=slot.limit} end
    local aliased = p.ammoInv == p.weaponInv
    p.weaponInv = slots
    p.ammoInv = aliased and slots or {}
    p.armors, p.armors_health = {}, {}
    p:SetNetVar("Armor", {}); p:SetNetVar("HideArmorRender", false)
    p:SyncArmor(); hg.CreateInv(p); hg.weaponInv.Sync(p)
    local hands = p:Give("weapon_hands_sh", true)
    if not IsValid(hands) then error("Postmortem could not give native zombie hands") end
    p:SelectWeapon("weapon_hands_sh")
end
local function Neutralize(p)
    p.isTraitor, p.MainTraitor, p.isPolice, p.isGunner = false, false, false, false
    p.SubRole, p.Profession = nil, nil
    p.Ability_NeckBreak, p.Ability_Disarm, p.PassiveAbility_ChemicalAccumulation = nil, nil, nil
end
local function Skip(ctx, s, reason)
    s.reason = reason
    if s.converted then Retire(ctx, s, true) else s.phase = "spent" end
    M:Log("Postmortem return skipped for " .. (IsValid(s.ply) and s.ply:Nick() or "disconnected player") .. ": " .. reason)
end
local function CaptureBody(s)
    if s.body then return BodyValid(s.ply, s.body) end
    local body = s.ply:GetNWEntity("RagdollDeath")
    if BodyValid(s.ply, body) then s.body = body; return true end
    return false
end
local function RetryOrSkip(ctx, s, reason)
    s.reason = reason
    local deadline = s.phase == "rising" and s.settleUntil or s.retryUntil
    if deadline and CurTime() >= deadline then Skip(ctx, s, reason .. " (retry expired)") end
end
local function Finish(ctx, s)
    local p, body = s.ply, s.body
    if s.phase ~= "rising" or s.released then return end
    if CurTime() > s.settleUntil then Skip(ctx, s, (s.reason or "spawn settling delayed") .. " (retry expired)"); return end
    if not IsValid(p) or not p:Alive() or p:Team() == TEAM_SPECTATOR or not BodyValid(p, body) then
        Skip(ctx, s, "return interrupted or body removed/claimed"); return
    end
    local pos, reason = Position(p, body)
    if not pos then RetryOrSkip(ctx, s, reason); return end
    Neutralize(p)
    ClearKit(p)
    -- Native On reads old clothing. Use the body appearance when available, otherwise its supported Rebel fallback.
    if type(body.CurAppearance) == "table" then p.CurAppearance = table.Copy(body.CurAppearance) end
    local clothes = p.CurAppearance and p.CurAppearance.AClothes
    if type(clothes) ~= "table" or not next(clothes) then
        p.CurAppearance = p.CurAppearance or {}; p.CurAppearance.AClothes = {}
        s.preZombSet = "Rebel"
    else s.preZombSet = s.humanClass or "none" end
    p.PreZombClass = s.preZombSet
    p:SetPlayerClass(CLASS)
    if p.PlayerClassName ~= CLASS or not p:Alive() then error("Postmortem native class conversion failed") end
    p:SetPos(pos); p:SetEyeAngles(Angle(0, s.yaw, 0)); p:SetLocalVelocity(vector_origin)
    zb.GiveRole(p, "Zombie", Color(150,0,0))
    -- Keep existing, unlooted weapon entities rather than granting copies to the zombie.
    for _, weapon in pairs(body.inventory and body.inventory.Weapons or {}) do
        if isentity(weapon) and IsValid(weapon) and weapon:IsWeapon() and weapon:GetParent() == body then
            weapon:SetParent(NULL); weapon:SetOwner(NULL); weapon:SetPos(pos+Vector(0,0,8))
            weapon:SetNoDraw(false); weapon:DrawShadow(true); weapon:RemoveSolidFlags(FSOLID_NOT_SOLID)
            local phys = weapon:GetPhysicsObject(); if IsValid(phys) then phys:Wake() end
        end
    end
    s.phase, s.reason = "zombie", nil
    p.RagdollDeath = nil; p:SetNWEntity("RagdollDeath", NULL)
    body:Remove()
    if s.freezeOwned then p:Freeze(false); s.freezeOwned = nil end
    if s.hidden then p:SetNoDraw(false); s.hidden=nil end
    Sync(ctx, p, true)
end
local function Return(ctx, s)
    local p = s.ply
    if s.phase ~= "waiting" or s.released then return end
    if not IsValid(p) or p:Alive() or p:Team() == TEAM_SPECTATOR then
        Skip(ctx, s, "disconnected, spectator or already respawned"); return
    end
    if s.body and (not BodyValid(p, s.body) or p:GetNWEntity("RagdollDeath") ~= s.body) then
        Skip(ctx, s, "body removed, replaced or claimed"); return
    end
    -- Start the retry allowance when a callback actually attempts the return.
    -- A delayed initial timer must not spend the entire allowance before one try.
    s.retryUntil = s.retryUntil or (CurTime() + RETRY_WINDOW)
    if CurTime() > s.retryUntil then Skip(ctx, s, (s.reason or "body/space unavailable") .. " (retry expired)"); return end
    s.attempts = (s.attempts or 0) + 1
    if not CaptureBody(s) then RetryOrSkip(ctx, s, "waiting for valid death body"); return end
    local pos, reason = Position(p, s.body)
    if not pos then RetryOrSkip(ctx, s, reason); return end
    s.reason = nil
    ZC_POSTMORTEM_KARMA.Capture(p,ctx)
    s.converted, s.phase = true, "rising" -- excluded before any native spawn hook can observe an alive player
    s.preZombOld, s.speedOld = p.PreZombClass, p.SpeedGainMul
    Neutralize(p)
    p.gottarespawn = true -- same corpse-preserving flag used by ZCity's body revival tool
    s.spawning = true
    local ok, err = xpcall(function() p:Spawn() end, debug.traceback)
    s.spawning = nil; p.gottarespawn = nil
    if not ok then error(err) end
    if not ctx:Valid() or not p:Alive() then Retire(ctx, s, true); return end
    s.settleUntil = CurTime() + SETTLE_WINDOW
    p:SetPos(pos)
    p:SetNoDraw(true); s.hidden=true -- keep the human spawn model hidden during native initialization
    if not p:IsFrozen() then p:Freeze(true); s.freezeOwned = true end
    -- Let native spawn/organism/appearance initialization settle, then apply the zombie class once.
    ctx:Timer("finish_"..s.serial, 0.2, 1, function(c) Finish(c, s) end)
end
local function QueueReturn(ctx, s, delay, body)
    local p = s.ply
    s.used = true
    ctx.data.used[Identity(p)] = true
    s.phase, s.deadAt, s.flags = "waiting", CurTime(), {}
    s.returnAt, s.body = s.deadAt + delay, body
    for _, key in ipairs({"isTraitor", "MainTraitor", "isPolice", "isGunner"}) do s.flags[key] = p[key] end
    s.yaw = p:EyeAngles().y
    -- Ragdoll and inventory are finalized in post-death hooks; capture only this death's body.
    ctx:Timer("body_"..s.serial, 0.05, 1, function(c)
        if s.phase ~= "waiting" or not IsValid(p) or p:Alive() then return end
        if not CaptureBody(s) then s.reason = "waiting for valid death body" end
    end)
    ctx:Timer("return_"..s.serial, delay, 1, function(c) Return(c,s) end)
end
local function OnDeath(ctx, p)
    local s = ctx.data.players[p]
    if s and (s.converted or s.used) then
        if s.converted then
            ZC_POSTMORTEM_KARMA.Release(p)
            s.phase = "spent"
            if s.freezeOwned then p:Freeze(false); s.freezeOwned=nil end
            if s.hidden then p:SetNoDraw(false); s.hidden=nil end
            -- Reinforcement waves may still select this dead player; our used record prevents another zombie life.
            Sync(ctx,p,false)
        end
        return
    end
    if not s or p:Team() == TEAM_SPECTATOR or s.wasZombie or p.PlayerClassName == CLASS then return end
    QueueReturn(ctx, s, DELAY)
end

local function Enroll(ctx, p, allowDead)
    if not IsValid(p) or (not p:Alive() and not allowDead) or p:Team() == TEAM_SPECTATOR then return end
    if ctx.data.players[p] or ctx.data.used[Identity(p)] then return end
    ctx.data.serial = ctx.data.serial + 1
    local s = {ply=p,serial=ctx.data.serial,phase="human",wasZombie=p.PlayerClassName==CLASS,humanClass=p.PlayerClassName}
    ctx.data.players[p] = s
    -- Separate callbacks let framework cleanup continue if one player addon throws.
    ctx:Cleanup(function() if s.converted then Retire(ctx,s,true) end end)
    return s
end
local function QueueExistingDead(ctx)
    if not ctx.midRound then return end
    local pending = {}
    for _, p in ipairs(player.GetAll()) do
        if IsValid(p) and not p:Alive() and p:Team() ~= TEAM_SPECTATOR and p.PlayerClassName ~= CLASS then
            local body = p:GetNWEntity("RagdollDeath")
            if BodyValid(p, body) then pending[#pending + 1] = {ply=p, body=body} end
        end
    end
    -- Shuffle once, then balance the backlog across 5/10/15-second activation waves.
    for i = #pending, 2, -1 do
        local j = math.floor(M:Random() * i) + 1
        pending[i], pending[j] = pending[j], pending[i]
    end
    local queued = 0
    for _, entry in ipairs(pending) do
        local s = Enroll(ctx, entry.ply, true)
        if s then
            s.preexisting = true
            QueueReturn(ctx, s, 5 * (queued % 3 + 1), entry.body)
            queued = queued + 1
        end
    end
    ctx.data.backlogQueued = queued
end
M:Register({
    MidRound = true,
    ID=ID, Title="Postmortem",
    Description="Deaths return after ten seconds as headcrab zombies. Mid-round activation returns existing corpses in 5/10/15-second waves. One return only. Zombies hunt everyone, cost no combat karma, and do not count as survivors or traitors.",
    Types={standard=true,wildwest=true,soe=true}, MinPlayers=3, Weight=1,
    CanStart=Requirements,
    Start=function(ctx)
        local ok, why = Requirements(ctx.mode); if not ok then error(why) end
        ctx.data.players, ctx.data.used, ctx.data.serial = {}, {}, 0
        -- Wrappers are cleaned up after transformed lives are retired (reverse cleanup order).
        local originalCount = ctx.mode.CheckAlivePlayers
        ctx:SetField(ctx.mode,"CheckAlivePlayers",function(mode,...)
            local groups = originalCount(mode,...)
            if not Scope(ctx) then return groups end
            local out = {}
            for key, list in pairs(groups) do
                out[key] = {}; for _,p in ipairs(list) do if not Excluded(ctx,p) then out[key][#out[key]+1]=p end end
            end
            return out
        end)
        local originalAlive = zb.CheckAlive
        ctx:SetField(zb,"CheckAlive",function(self,...)
            local list = originalAlive(self,...)
            if not Scope(ctx) then return list end
            local out = {}; for _,p in ipairs(list) do if not Excluded(ctx,p) then out[#out+1]=p end end
            return out
        end)
        local originalEnd = ctx.mode.EndRound
        ctx:SetField(ctx.mode,"EndRound",function(mode,...)
            if Scope(ctx) then
                -- Native EndRound counts raw Alive() separately. End zombie lives before that tally;
                -- original traitor flags are restored on dead players for the final identity reveal.
                for _,s in pairs(ctx.data.players) do if s.converted and not s.released then Retire(ctx,s,true) end end
            end
            return originalEnd(mode,...)
        end)
        InstallKarmaGuards(ctx)
        for _,p in ipairs(ctx.participants) do Enroll(ctx,p) end
        QueueExistingDead(ctx)
        ctx:Hook("PlayerSilentDeath","postmortem_silent",OnDeath)
        ctx:Hook("DoPlayerDeath","postmortem_class",function(c,p)
            local s=c.data.players[p]
            if s and not s.used then s.wasZombie=p.PlayerClassName==CLASS; s.humanClass=p.PlayerClassName end
        end)
        ctx:Hook("PlayerCanPickupWeapon","postmortem_pickup",function(c,p,w)
            if Actor(c,p) and w:GetClass()~="weapon_hands_sh" then return false end
        end)
        ctx:Timer("postmortem_sync",1,0,function(c)
            c.data.refreshKarma()
            for p,s in pairs(c.data.players) do
                if s.phase == "waiting" and not s.released then
                    if CurTime() >= s.returnAt then Return(c, s)
                    elseif IsValid(p) and not p:Alive() then CaptureBody(s) end
                elseif s.phase == "rising" and s.reason then Finish(c, s) end
                if s.converted and not s.released and IsValid(p) then
                    if p:Alive() and s.phase=="zombie" and p.PlayerClassName~=CLASS then
                        Retire(c,s,false) -- respect another system's class change
                    else Sync(c,p,s.phase=="zombie" and p:Alive()) end
                end
            end
        end)
    end,
    PlayerDeath=OnDeath,
    PlayerSpawn=function(ctx,p)
        local s=ctx.data.players[p]
        if s then
            if s.spawning or OverrideSpawn then return end -- native ragdoll get-up is not another life
            if s.used then
                if s.converted then Retire(ctx,s,false) else s.phase="spent"; s.released=true; s.reason="already respawned by another system" end
            end
        else Enroll(ctx,p) end
    end,
    PlayerDisconnected=function(ctx,p)
        local s=ctx.data.players[p]; if s then s.phase="spent"; s.released=true; s.reason="disconnected" end
    end
})
concommand.Add("zc_mutator_postmortem_status",function(p)
    if IsValid(p) and not (p:IsAdmin() or p:IsSuperAdmin()) then return end
    local ctx=M.current
    local function say(text) if IsValid(p) then p:PrintMessage(HUD_PRINTCONSOLE,text) else print(text) end end
    if not ctx or ctx.definition.ID~=ID then say("[zc_mutators] Postmortem is not active."); return end
    local callbacks=hook.GetTable().HomigradDamage or {}
    local function guardState(id)
        local guard=ctx.data.karmaGuards and ctx.data.karmaGuards[id]
        if not callbacks[id] then return "absent" end
        return guard and callbacks[id]==guard.wrapper and "protected" or "REPLACED/unprotected"
    end
    say("[Postmortem] v"..ZC_HMCD_MUTATOR_INFO.Version.." native="..guardState("GuiltReg").." pats="..guardState("ZCITY_GUILT_TrackDamage")
        .." blocked="..(ctx.data.karmaBlocked or 0).." repairs="..(ctx.data.karmaRepairs or 0))
    for who,s in pairs(ctx.data.players) do
        if IsValid(who) then
            local progress = ""
            if s.phase == "waiting" then
                progress = s.retryUntil and string.format(" retry_left=%.1fs attempts=%d",math.max(0,s.retryUntil-CurTime()),s.attempts or 0)
                    or string.format(" return_in=%.1fs",math.max(0,s.returnAt-CurTime()))
            elseif s.phase == "rising" then progress = string.format(" settle_left=%.1fs",math.max(0,s.settleUntil-CurTime())) end
            say("[Postmortem] "..who:Nick()..": "..s.phase..(s.reason and " reason="..s.reason or "").." karma="..ZC_POSTMORTEM_KARMA.Status(who)..progress)
        end
    end
end)
