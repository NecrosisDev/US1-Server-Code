-- ZCity Traitor Admin Tool - Server Side
-- Supports up to 2 forced traitors per round

util.AddNetworkString("traitoradmin_open")
util.AddNetworkString("traitoradmin_playerlist")
util.AddNetworkString("traitoradmin_settraitor")
util.AddNetworkString("traitoradmin_forcenow")
util.AddNetworkString("traitoradmin_clearforced")
util.AddNetworkString("traitoradmin_sethomelander")
util.AddNetworkString("traitoradmin_spawnpolice")
util.AddNetworkString("traitoradmin_forcepolice")
util.AddNetworkString("traitoradmin_restart")

local MAX_FORCED = 2

local function IsAdmin(ply)
    return ply:IsAdmin() or ply:IsSuperAdmin()
end

-- Store forced SteamIDs separately so they survive ZCity's reset
TraitorAdmin = TraitorAdmin or {}
TraitorAdmin.ForcedSteamIDs = TraitorAdmin.ForcedSteamIDs or {}
TraitorAdmin.ForcedHomelander = TraitorAdmin.ForcedHomelander or nil

-- Re-inject forced traitors after ZCity's intermission resets things
hook.Add("ZB_PreRoundStart", "TraitorAdmin_ReInject", function()
    if #TraitorAdmin.ForcedSteamIDs > 0 then
        timer.Simple(0.2, function()
            for _, mkey in ipairs({"hmcd", "fear"}) do
                local m = zb and zb.modes and zb.modes[mkey]
                if m then
                    m.NextRoundMainTraitors = m.NextRoundMainTraitors or {}
                    for _, sid in ipairs(TraitorAdmin.ForcedSteamIDs) do
                        m.NextRoundMainTraitors[sid] = true
                        print("[TraitorAdmin] Injected forced traitor (" .. mkey .. "): " .. sid)
                    end
                end
            end
        end)
    end
end)

-- Clear our stored values once the round actually starts
hook.Add("ZB_StartRound", "TraitorAdmin_ClearForced", function()
    TraitorAdmin.ForcedSteamIDs = {}
    for _, mkey in ipairs({"hmcd", "fear"}) do
        if zb and zb.modes and zb.modes[mkey] then
            zb.modes[mkey].NextRoundMainTraitors = {}
        end
    end
end)

-- Send full player list + current forced list to requesting admin
local function SendPlayerList(ply)
    if not IsValid(ply) or not IsAdmin(ply) then return end

    local players = {}

    -- Build forced lookup
    local forcedLookup = {}
    for _, sid in ipairs(TraitorAdmin.ForcedSteamIDs) do
        forcedLookup[sid] = true
    end

    for _, p in player.Iterator() do
        local isTraitor = p.isTraitor == true
        local isMainTraitor = p.MainTraitor == true
        local isForced = forcedLookup[p:SteamID()] == true
        local isHomelander = (TraitorAdmin.ForcedHomelander == p:SteamID())

        local charname = p:GetNWString("PlayerName", p:Nick())

        table.insert(players, {
            userid       = p:UserID(),
            steamid      = p:SteamID(),
            name         = p:Nick(),
            charname     = charname,
            alive        = p:Alive(),
            istraitor    = isTraitor,
            ismaintraitor = isMainTraitor,
            isforced     = isForced,
            ishomelander = isHomelander,
            karma        = p.Karma or 100,
        })
    end

    net.Start("traitoradmin_playerlist")
        net.WriteTable(players)
        net.WriteTable(TraitorAdmin.ForcedSteamIDs)
        net.WriteString(TraitorAdmin.ForcedHomelander or "")
    net.Send(ply)
end

-- Admin requests to open the menu
net.Receive("traitoradmin_open", function(len, ply)
    if not IsAdmin(ply) then return end
    SendPlayerList(ply)
end)

-- Admin toggles a player as forced traitor for next round
net.Receive("traitoradmin_settraitor", function(len, ply)
    if not IsAdmin(ply) then return end

    local steamid = net.ReadString()
    local clear   = net.ReadBool()

    if not zb or not zb.modes or not zb.modes["hmcd"] then
        ply:ChatPrint("[TraitorAdmin] ZCity hmcd mode not found!")
        return
    end

    zb.modes["hmcd"].NextRoundMainTraitors = zb.modes["hmcd"].NextRoundMainTraitors or {}

    if clear then
        zb.modes["hmcd"].NextRoundMainTraitors = {}
        TraitorAdmin.ForcedSteamIDs = {}
        print("[TraitorAdmin] " .. ply:Nick() .. " cleared all forced traitors.")
    else
        -- Toggle: if already in list, remove; otherwise add (up to MAX_FORCED)
        local found = false
        for i, sid in ipairs(TraitorAdmin.ForcedSteamIDs) do
            if sid == steamid then
                table.remove(TraitorAdmin.ForcedSteamIDs, i)
                zb.modes["hmcd"].NextRoundMainTraitors[steamid] = nil
                found = true
                print("[TraitorAdmin] " .. ply:Nick() .. " removed " .. steamid .. " from forced traitors.")
                break
            end
        end

        if not found then
            if #TraitorAdmin.ForcedSteamIDs >= MAX_FORCED then
                ply:ChatPrint("[TraitorAdmin] Maximum of " .. MAX_FORCED .. " forced traitors already set. Remove one first.")
                return
            end
            table.insert(TraitorAdmin.ForcedSteamIDs, steamid)
            zb.modes["hmcd"].NextRoundMainTraitors[steamid] = true

            for _, p in player.Iterator() do
                if p:SteamID() == steamid then
                    print("[TraitorAdmin] " .. ply:Nick() .. " added " .. p:Nick() .. " as forced traitor.")
                    break
                end
            end
        end
    end

    -- Refresh all admins
    for _, p in player.Iterator() do
        if IsAdmin(p) then SendPlayerList(p) end
    end
end)

-- Admin forces a player to be traitor mid-round NOW
net.Receive("traitoradmin_forcenow", function(len, ply)
    if not IsAdmin(ply) then return end

    local userid = net.ReadInt(16)
    local target = nil
    for _, p in player.Iterator() do
        if p:UserID() == userid then target = p break end
    end

    if not IsValid(target) or not target:Alive() then return end

    local mode = zb and zb.modes and zb.modes["hmcd"]
    if not mode then return end

    -- Set traitor flags
    target.isTraitor  = true
    target.MainTraitor = true

    -- Give traitor role display
    local roleInfo = mode.Roles and mode.Roles[mode.Type or "standard"] and mode.Roles[mode.Type or "standard"]["traitor"]
    if roleInfo then
        zb.GiveRole(target, roleInfo.name, roleInfo.color)
    else
        zb.GiveRole(target, "Murderer", Color(190, 0, 0))
    end

    -- Give traitor loot
    if mode.Types and mode.Types[mode.Type or "standard"] and mode.Types[mode.Type or "standard"].TraitorLoot then
        mode.Types[mode.Type or "standard"].TraitorLoot(target)
    end

    -- Give subrole equipment (default traitor role)
    local roundType = mode.Type or "standard"
    local subroleConfig = mode.RoleChooseRoundTypes and mode.RoleChooseRoundTypes[roundType]
    if subroleConfig then
        local defaultRole = subroleConfig.TraitorDefaultRole
        if defaultRole and mode.SubRoles and mode.SubRoles[defaultRole] then
            local spawnFunc = mode.SubRoles[defaultRole].SpawnFunction
            if spawnFunc then spawnFunc(target) end
        end
    end

    target:ChatPrint("[Admin] You have been made a traitor by an admin.")
    print("[TraitorAdmin] " .. ply:Nick() .. " forced " .. target:Nick() .. " as traitor mid-round.")

    -- Refresh all admins
    for _, p in player.Iterator() do
        if IsAdmin(p) then SendPlayerList(p) end
    end
end)

-- Admin toggles a player as forced Homelander for next round
net.Receive("traitoradmin_sethomelander", function(len, ply)
    if not IsAdmin(ply) then return end
    local steamid = net.ReadString()

    if TraitorAdmin.ForcedHomelander == steamid then
        TraitorAdmin.ForcedHomelander = nil
        print("[TraitorAdmin] " .. ply:Nick() .. " cleared forced Homelander.")
    else
        TraitorAdmin.ForcedHomelander = steamid
        for _, p in player.Iterator() do
            if p:SteamID() == steamid then
                print("[TraitorAdmin] " .. ply:Nick() .. " set " .. p:Nick() .. " as forced Homelander.")
                break
            end
        end
    end

    for _, p in player.Iterator() do
        if IsAdmin(p) then SendPlayerList(p) end
    end
end)

-- Clear forced Homelander on round start
hook.Add("ZB_StartRound", "TraitorAdmin_ClearHomelander", function()
    TraitorAdmin.ForcedHomelander = nil
end)


-- =====================================================================
-- Server tab actions (admin gated, same as everything else here)
-- =====================================================================

-- Both buttons share player eligibility and the repeat-click gate. The regular
-- action accepts all Homicide variants; force also accepts other active modes.
local reinforcementGate = {}
local function DeployReinforcements(len, ply, force)
    if not IsValid(ply) or not IsAdmin(ply) or len > 0 then return end
    local m = zb and zb.modes and zb.modes.hmcd
    local active = CurrentRound and CurrentRound()
    local homicide = m and active == m
    if not m or not active or zb.ROUND_STATE ~= 1 or (not force and not homicide)
        or (homicide and m.RoleChooseRound and m.StartRoundTime) then
        ply:ChatPrint(force and "[TraitorAdmin] Force reinforcements requires an active round after role selection."
            or "[TraitorAdmin] Reinforcements require an active Homicide round after role selection.")
        return
    end
    local stamp, variant = zb.ROUND_START, active.Type
    if reinforcementGate.mode == active and reinforcementGate.stamp == stamp
        and reinforcementGate.variant == variant and CurTime() < reinforcementGate.untilTime then
        ply:ChatPrint("[TraitorAdmin] Please wait one second between reinforcement deployments.")
        return
    end
    local standard = m.Types and m.Types.standard
    local def = standard
    if homicide then def = m.Types and m.Types[m.Type] end
    local guard = homicide and m.Type == "soe"
    local kind, cap = guard and "nationalguard" or "police", guard and 6 or 4
    local equipment = def and (def.PoliceEquipment or (standard and standard.PoliceEquipment))
    if not def or type(m.SpawnForce) ~= "function" or (guard and type(m.EquipNationalGuard) ~= "function")
        or (not guard and type(equipment) ~= "function") then
        ply:ChatPrint("[TraitorAdmin] Reinforcement equipment is unavailable for this round.")
        return
    end
    local spawnMode = m
    if not homicide then
        -- Borrow the native Standard police kit without switching the active
        -- game mode or changing dormant Homicide state.
        spawnMode = setmetatable({Type = "standard"}, {__index = m})
    elseif not guard and not def.PoliceEquipment then
        -- Per-call fallback: automatic police/SWAT permissions remain intact.
        local spawnDef = setmetatable({PoliceEquipment = equipment}, {__index = def})
        local spawnTypes = setmetatable({[variant] = spawnDef}, {__index = m.Types})
        spawnMode = setmetatable({Types = spawnTypes}, {__index = m})
    end
    local eligible = 0
    for _, p in player.Iterator() do
        if not p:Alive() and not p.isTraitor and p:Team() ~= TEAM_SPECTATOR and (p.afkTime2 or 0) <= 60 then
            eligible = eligible + 1
        end
    end
    if eligible == 0 then
        ply:ChatPrint("[TraitorAdmin] No eligible dead players are available for reinforcements.")
        return
    end
    -- Reserve before native spawn hooks can re-enter either button's receiver.
    reinforcementGate = {mode = active, stamp = stamp, variant = variant, untilTime = CurTime() + 1}
    local ok, spawned = pcall(m.SpawnForce, spawnMode, kind, math.min(eligible, cap))
    if not ok then
        ply:ChatPrint("[TraitorAdmin] Reinforcement spawn failed: " .. tostring(spawned))
        return
    end
    if CurrentRound() ~= active or zb.ROUND_STATE ~= 1 or zb.ROUND_START ~= stamp or active.Type ~= variant then
        ply:ChatPrint("[TraitorAdmin] Round changed during deployment; no arrival announcement sent.")
        return
    end
    if type(spawned) ~= "number" or spawned ~= spawned or spawned <= 0 or spawned > math.min(eligible, cap)
        or spawned ~= math.floor(spawned) then
        ply:ChatPrint("[TraitorAdmin] No valid spawn count returned; existing reinforcement state kept.")
        return
    end
    if homicide then
        if not guard then m.spawnedPoliceCount = (m.spawnedPoliceCount or 0) + spawned end
        m.PoliceSpawned = true
    end
    PrintMessage(HUD_PRINTTALK, guard and (def.PoliceText or "National Guard have arrived.") or "Police have arrived.")
    EmitSound(guard and (def.PoliceSound or "snd_jack_hmcd_heli2.mp3") or "snd_jack_hmcd_policesiren.wav", vector_origin, 0, CHAN_AUTO, 1, 125, 0, 100)
    print("[TraitorAdmin] " .. ply:Nick() .. " deployed " .. spawned .. " " .. kind .. (force and " via admin override." or " via admin panel."))
end
net.Receive("traitoradmin_spawnpolice", function(len, ply) DeployReinforcements(len, ply, false) end)
net.Receive("traitoradmin_forcepolice", function(len, ply) DeployReinforcements(len, ply, true) end)

-- Manual and daily restarts share one cancellable controller.
net.Receive("traitoradmin_restart", function(len, ply)
    if not IsValid(ply) or not IsAdmin(ply) or len>64 then return end
    local controller=ZC_RESTART_WARNING
    if not controller or not controller.RequestManual then
        ply:ChatPrint("[TraitorAdmin] Install restart_warning v2 to enable cancellable restarts.")
        return
    end
    local ok,message=controller.RequestManual(ply)
    ply:ChatPrint("[TraitorAdmin] "..message)
    print("[TraitorAdmin] "..ply:Nick().." manual restart: "..message)
end)

-- =====================================================================
-- ABNORMALTIES TAB (added 8/31)
-- The occult ritual system ships DISABLED: the gamemode hard-sets
-- SetGlobalBool("AbnormaltiesEnabled", false) at load and nothing ever
-- sets it true. This section makes the flag convar-driven, adds the two
-- performance/safety gates that make enabling it sane on 32 slots, and
-- serves the admin panel's Abnormal tab.
--
--  zc_abno        0  master switch (panel toggle writes this; ARCHIVE)
--  zc_abno_swarm  0  allow the resurrection ritual's 70% Swarm
--                    infection (NPC faction = the one real tick risk).
--                    Admin "Infect" button works regardless - the gate
--                    only stops the ritual's automatic roll.
--
-- GATE 1 (blood traces): stock HG_BloodParticleStartedDropping does
-- LookupBone + GetBonePosition + util.TraceLine for EVERY blood drop
-- once enabled, BEFORE checking whether any hot zone exists. We
-- re-register the same hook name with an early-out when there are no
-- hot zones (the normal state), so a 30-player firefight costs one
-- table lookup per drop instead of a trace. Body below is otherwise
-- copied verbatim from abnormalty_detection/sv_plugin.lua:1250-1273.
--
-- GATE 2 (swarm): stock resurrection Think rolls math.random(1,10)<=7
-- -> owner.Swm = true. Re-registered with the roll behind zc_abno_swarm.
-- Body otherwise verbatim from abnormalty_ressurection/sv_ressurection
-- .lua Think hook.
--
-- The gamemode loads AFTER addon autorun and would stomp our hooks, so
-- a 1s sync timer verifies flag + both hooks and reinstalls (same
-- self-healing shape as zc_wwkarma / zc_gfzloot).
-- =====================================================================

local cv_abno  = CreateConVar("zc_abno", "0", FCVAR_ARCHIVE, "Enable the Abnormalties ritual system", 0, 1)
local cv_swarm = CreateConVar("zc_abno_swarm", "0", FCVAR_ARCHIVE, "Allow resurrection's automatic Swarm infection", 0, 1)
local cv_symp  = CreateConVar("zc_abno_symptoms", "1", FCVAR_ARCHIVE, "Balance symptoms (headaches/bleeding/pulse spikes) and the +-300 passive generation", 0, 1)
CreateConVar("zc_abno_rite_blood", "3000", FCVAR_ARCHIVE, "Blood pre-banked by the panel's Blood Rite preset", 0, 50000)

util.AddNetworkString("traitoradmin_abno_open")
util.AddNetworkString("traitoradmin_abno_data")
util.AddNetworkString("traitoradmin_abno_action")

local MEANINGS = { harm = true, ritual = true, shield = true, help = true, sacrifice = true }

-- ---------------------------------------------------------------------
-- GATE 1: trace-gated blood collection (same hook name = replaces stock)
-- ---------------------------------------------------------------------
local bloodHook = function(owner, org, wound, dir, artery)
	local PLUGIN = hg and hg.Abnormalties
	if not PLUGIN then return end
	if not GetGlobalBool("AbnormaltiesEnabled", false) then return end
	if next(PLUGIN.HotZones or {}) == nil then return end -- THE GATE: no hot zones, no trace
	if not IsValid(owner) then return end

	local ent = owner:IsPlayer() and IsValid(owner.FakeRagdoll) and owner.FakeRagdoll or owner
	local pos = ent:GetBonePosition(ent:LookupBone(wound[4]))
	if not pos then return end
	local trace = util.TraceLine({
		start = pos,
		endpos = pos + vector_up * (-1000),
		filter = {ent},
	})

	ent.Abnormalties_LastBloodDropPos = ent.Abnormalties_LastBloodDropPos or trace.HitPos
	local additional_point = ent.Abnormalties_LastBloodDropPos:DistToSqr(trace.HitPos) / 300
	ent.Abnormalties_LastBloodDropPos = trace.HitPos

	if artery then
		PLUGIN.AddBloodToHotZones(trace.HitPos, 1 + additional_point)
	else
		PLUGIN.AddBloodToHotZones(trace.HitPos, 3 + additional_point)
	end
end

-- ---------------------------------------------------------------------
-- GATE 2: swarm-gated resurrection completion (same hook name)
-- ---------------------------------------------------------------------
local resHook = function()
	local PLUGIN = hg and hg.Abnormalties
	if not (PLUGIN and PLUGIN.Ressurection) then return end
	for ply, info in pairs(PLUGIN.Ressurection.ToRessurect) do
		if info.Time <= CurTime() then
			local owner = info.Owner
			local body = info.Body

			if not IsValid(owner) or owner:Alive() or not IsValid(body) then
				PLUGIN.ShowMessageToAll("Ritual was interrupted by divine intervention.\nCorruption spreads")
			else
				hg.RespawnIntoBody(owner, body)
				owner:SetHealth(20)

				owner.organism.pain = 40
				owner.organism.disorientation = 50
				owner.organism.blood = 3500

				if math.random(1, 4) == 4 then
					owner.organism.pulse = 10
				else
					owner.organism.pulse = 15
				end

				if cv_swarm:GetBool() and math.random(1, 10) <= 7 then -- THE GATE
					owner.Swm = true
				end

				PLUGIN.ShowMessageToAll("Something wicked happened")
			end

			PLUGIN.Ressurection.ToRessurect[ply] = nil
		end
	end
end

-- ---------------------------------------------------------------------
-- GATE 3: symptom kill-switch (zc_abno_symptoms 0)
-- Symptoms, the +-300 passive generation AND the punishment decay all
-- live in ONE gamemode hook (PlayerPostThink/"Abnormalties_Consequences",
-- sv_plugin:394). Unlike the other two gates we don't copy that ~150-line
-- body - we CAPTURE the gamemode's function and wrap it: symptoms on ->
-- call it untouched; symptoms off -> skip the effects but keep the
-- punishment decaying and the per-player timestamps fresh, so nothing
-- freezes and re-enabling doesn't hand players a giant delta_time step.
-- The original is stored on the persistent TraitorAdmin table so a
-- hotload never mistakes its own old wrapper for the gamemode's function.
-- ---------------------------------------------------------------------
local sympWrap
sympWrap = function(ply)
	local orig = TraitorAdmin.AbnoSympOrig
	if cv_symp:GetBool() then
		if orig then return orig(ply) end
		return
	end
	-- symptoms off: bookkeeping only
	if ply.AbnormaltiesReady then
		ply.AbnormaltiesConsequencesLastThink = CurTime() -- keep delta_time honest
		if not ply.AbnormaltiesConsequencesNextPunishmentReduceTime then
			ply.AbnormaltiesConsequencesNextPunishmentReduceTime = CurTime() + 1
		end
		if ply.AbnormaltiesConsequencesNextPunishmentReduceTime <= CurTime() then
			ply.AbnormaltiesConsequencesNextPunishmentReduceTime = CurTime() + 1
			local PLUGIN = hg and hg.Abnormalties
			if PLUGIN then
				local punishment = PLUGIN.GetPlayerStat(ply, "punishment") or 0
				if punishment > 0 then
					PLUGIN.SetPlayerStat(ply, "punishment", math.max(math.Truncate(punishment - 1), 0))
				end
			end
		end
	end
end

-- ---------------------------------------------------------------------
-- self-healing sync: flag + all three hook slots
-- ---------------------------------------------------------------------
timer.Create("traitoradmin_abno_sync", 1, 0, function()
	if not (hg and hg.Abnormalties) then return end -- gamemode not up yet

	if GetGlobalBool("AbnormaltiesEnabled", false) ~= cv_abno:GetBool() then
		SetGlobalBool("AbnormaltiesEnabled", cv_abno:GetBool())
		print("[TraitorAdmin] Abnormalties " .. (cv_abno:GetBool() and "ENABLED" or "disabled"))
	end

	local t = hook.GetTable()
	local blood = t["HG_BloodParticleStartedDropping"]
	if not blood or blood["Abnormalties"] ~= bloodHook then
		hook.Add("HG_BloodParticleStartedDropping", "Abnormalties", bloodHook)
		print("[TraitorAdmin] installed trace-gated blood hook")
	end
	local think = t["Think"]
	if not think or think["Abnormalties_Ressurection"] ~= resHook then
		hook.Add("Think", "Abnormalties_Ressurection", resHook)
		print("[TraitorAdmin] installed swarm-gated resurrection hook")
	end

	local ppt = t["PlayerPostThink"]
	local cur = ppt and ppt["Abnormalties_Consequences"]
	if cur ~= sympWrap then
		-- capture the gamemode's real function - but never our own old
		-- wrapper from before a hotload (stored on the persistent table)
		if isfunction(cur) and cur ~= TraitorAdmin.AbnoSympWrap then
			TraitorAdmin.AbnoSympOrig = cur
		end
		if TraitorAdmin.AbnoSympOrig then
			TraitorAdmin.AbnoSympWrap = sympWrap
			hook.Add("PlayerPostThink", "Abnormalties_Consequences", sympWrap)
			print("[TraitorAdmin] installed symptom-gated consequences hook")
		end
	end
end)

-- ---------------------------------------------------------------------
-- panel data
-- ---------------------------------------------------------------------
local MAX_ZONES_SENT = 32

local function SendAbnoData(ply)
	if not IsValid(ply) or not IsAdmin(ply) then return end
	local PLUGIN = hg and hg.Abnormalties

	local data = {
		enabled = cv_abno:GetBool(),
		live    = GetGlobalBool("AbnormaltiesEnabled", false),
		swarm   = cv_swarm:GetBool(),
		symptoms = cv_symp:GetBool(),
		funmode = (PLUGIN and PLUGIN.FunMode) == true,
		zones   = {},
		players = {},
		hotchars = 0,
		swarmstats = nil,
	}

	if PLUGIN then
		for char, until_ in pairs(PLUGIN.HotChars or {}) do
			if until_ > CurTime() then data.hotchars = data.hotchars + 1 end
		end
		for id, zone in ipairs(PLUGIN.Zones or {}) do
			if id > MAX_ZONES_SENT then break end
			data.zones[#data.zones + 1] = {
				id = id,
				x = math.Round(zone.Pos.x), y = math.Round(zone.Pos.y), z = math.Round(zone.Pos.z),
				radius = math.Round(zone.Radius or 0),
				points = math.Round(zone.Points or 0),
				blood = math.Round(zone.Blood or 0),
				hot = PLUGIN.HotZones[id] == true,
			}
		end
	end

	for _, p in player.Iterator() do
		data.players[#data.players + 1] = {
			userid = p:UserID(),
			name = p:Nick(),
			alive = p:Alive(),
			bal = p:GetNWInt("AbnormaltiesConsequences", 0),
			blood = math.Round(p.Abnormalties_Blood or 0),
			eq = math.Round(p.Abnormalties_Equalizers or 0),
			pun = (PLUGIN and PLUGIN.GetPlayerStat(p, "punishment")) or 0,
			swm = p.Swm == true,
		}
	end

	if SWARM and SWARM.GetStats then
		local ok, st = pcall(SWARM.GetStats, SWARM)
		if ok and istable(st) then
			data.swarmstats = { npcs = st.NPCAmt or 0, infected = st.Infected or 0, mothers = st.Mothers or 0 }
		end
	end

	net.Start("traitoradmin_abno_data")
		net.WriteTable(data)
	net.Send(ply)
end

net.Receive("traitoradmin_abno_open", function(len, ply)
	if not IsAdmin(ply) then return end
	SendAbnoData(ply)
end)

-- ---------------------------------------------------------------------
-- panel actions: one message, action string + args. Every action is
-- admin-checked, validated, logged, and answered with fresh data.
-- ---------------------------------------------------------------------
local function findByUserID(userid)
	for _, p in player.Iterator() do
		if p:UserID() == userid then return p end
	end
end

local function rebuildHotZones(PLUGIN)
	PLUGIN.HotZones = {}
	for id, zone in ipairs(PLUGIN.Zones) do
		if (zone.Points or 0) > PLUGIN.HotZonePoints then PLUGIN.HotZones[id] = true end
	end
end

net.Receive("traitoradmin_abno_action", function(len, ply)
	if not IsAdmin(ply) then return end
	local action = net.ReadString()
	local arg1 = net.ReadInt(32)
	local arg2 = net.ReadString()
	local PLUGIN = hg and hg.Abnormalties
	local who = ply:Nick()

	if action == "toggle" then
		cv_abno:SetBool(not cv_abno:GetBool())
		SetGlobalBool("AbnormaltiesEnabled", cv_abno:GetBool())
		print("[TraitorAdmin] " .. who .. " turned Abnormalties " .. (cv_abno:GetBool() and "ON" or "OFF"))

	elseif action == "swarm" then
		cv_swarm:SetBool(not cv_swarm:GetBool())
		print("[TraitorAdmin] " .. who .. " turned Swarm infection " .. (cv_swarm:GetBool() and "ON" or "OFF"))

	elseif action == "symptoms" then
		cv_symp:SetBool(not cv_symp:GetBool())
		print("[TraitorAdmin] " .. who .. " turned Balance symptoms " .. (cv_symp:GetBool() and "ON" or "OFF"))

	elseif action == "funmode" then
		if PLUGIN then
			PLUGIN.FunMode = not PLUGIN.FunMode or nil
			print("[TraitorAdmin] " .. who .. " turned FunMode " .. (PLUGIN.FunMode and "ON" or "OFF"))
		end

	elseif action == "reroll" then
		if PLUGIN then
			PLUGIN.RandomizeCharInfos()
			print("[TraitorAdmin] " .. who .. " re-rolled the letter meanings")
		end

	elseif action == "clearzones" then
		if PLUGIN then
			PLUGIN.Zones = {}
			PLUGIN.HotZones = {}
			PLUGIN.HotWords = {}
			print("[TraitorAdmin] " .. who .. " cleared all zones")
		end

	elseif action == "zonehere" then
		if PLUGIN and ply:Alive() then
			local id = #PLUGIN.Zones + 1
			PLUGIN.Zones[id] = {
				Pos = ply:GetPos(),
				Radius = 200,
				Points = PLUGIN.HotZonePoints + 1,
				Words = {}, Abnormalties = {}, Vars = {}, Chanters = {},
			}
			PLUGIN.HotZones[id] = true
			print("[TraitorAdmin] " .. who .. " created a hot zone at their position")
		end

	elseif action == "zonehot" then
		local zone = PLUGIN and PLUGIN.Zones[arg1]
		if zone then
			zone.Points = math.max(zone.Points or 0, PLUGIN.HotZonePoints + 1)
			PLUGIN.HotZones[arg1] = true
			PLUGIN.ShowMessageInSphere("Zone grew enough to start phrase accumulation and rituals", zone.Pos, zone.Radius)
			print("[TraitorAdmin] " .. who .. " force-heated zone " .. arg1)
		end

	elseif action == "zonegrow" then
		local zone = PLUGIN and PLUGIN.Zones[arg1]
		if zone then
			zone.Radius = math.min((zone.Radius or 70) + 100, PLUGIN.MaxZoneRadius)
			print("[TraitorAdmin] " .. who .. " grew zone " .. arg1 .. " to radius " .. zone.Radius)
		end

	elseif action == "zonetp" then
		local zone = PLUGIN and PLUGIN.Zones[arg1]
		if zone and ply:Alive() then
			ply:SetPos(zone.Pos + Vector(0, 0, 10))
			print("[TraitorAdmin] " .. who .. " teleported to zone " .. arg1)
		end

	elseif action == "zonedel" then
		if PLUGIN and PLUGIN.Zones[arg1] then
			table.remove(PLUGIN.Zones, arg1)
			rebuildHotZones(PLUGIN) -- ids shifted; hot set is keyed by id
			print("[TraitorAdmin] " .. who .. " deleted zone " .. arg1)
		end

	elseif action == "setbal" then
		local target = findByUserID(arg1)
		local v = tonumber(arg2)
		if PLUGIN and IsValid(target) and v then
			-- no_punishment: an admin set should not trigger symptom punishment
			PLUGIN.SetConsequences(target, math.Clamp(v, -500, 500), true)
			print("[TraitorAdmin] " .. who .. " set " .. target:Nick() .. " Balance to " .. math.Clamp(v, -500, 500))
		end

	elseif action == "addbal" then
		local target = findByUserID(arg1)
		local v = tonumber(arg2)
		if PLUGIN and IsValid(target) and v then
			-- AddConsequences = the stock path: punishment fires, symptoms show
			PLUGIN.AddConsequences(target, math.Clamp(v, -500, 500))
			print("[TraitorAdmin] " .. who .. " shifted " .. target:Nick() .. " Balance by " .. v)
		end

	elseif action == "blood" then
		local target = findByUserID(arg1)
		if IsValid(target) then
			target.Abnormalties_Blood = math.max((target.Abnormalties_Blood or 0) + (tonumber(arg2) or 0), 0)
			print("[TraitorAdmin] " .. who .. " gave " .. target:Nick() .. " " .. arg2 .. " abnormal Blood")
		end

	elseif action == "eq" then
		local target = findByUserID(arg1)
		if IsValid(target) then
			target.Abnormalties_Equalizers = math.max((target.Abnormalties_Equalizers or 0) + (tonumber(arg2) or 0), 0)
			print("[TraitorAdmin] " .. who .. " gave " .. target:Nick() .. " " .. arg2 .. " Equalizers")
		end

	elseif action == "clearpunish" then
		local target = findByUserID(arg1)
		if PLUGIN and IsValid(target) then
			PLUGIN.SetPlayerStat(target, "punishment", 0)
			print("[TraitorAdmin] " .. who .. " cleared " .. target:Nick() .. "'s punishment")
		end

	elseif action == "unlock" then
		local target = findByUserID(arg1)
		if PLUGIN and IsValid(target) then
			PLUGIN.SetKnowledge(target, {
				consequences = true, instabillity = true,
				positive_instabillity = true, negative_instabillity = true,
				insanity = true,
			})
			PLUGIN.ShowMessage(target, "You are now able to read every page")
			print("[TraitorAdmin] " .. who .. " unlocked all book pages for " .. target:Nick())
		end

	elseif action == "conjure" then
		local class = ({
			equalizer = "ent_armor_ego_equalizer",
			musket = "weapon_bleeding_musket",
			arm = "weapon_thaumaturgic_arm",
		})[arg2]
		if class and ply:Alive() then
			local tr = ply:GetEyeTrace()
			local ent = ents.Create(class)
			if IsValid(ent) then
				ent:SetPos(tr.HitPos + Vector(0, 0, 20))
				ent:Spawn()
				ent:Activate()
				print("[TraitorAdmin] " .. who .. " conjured " .. class)
			end
		end

	elseif action == "phrase" then
		if PLUGIN and MEANINGS[arg2] then
			local phrase, success = PLUGIN.FindValidPhrase(arg2, 40, "")
			ply:ChatPrint("[Abno] " .. arg2 .. (success and ": " or " (imperfect): ") .. phrase)
			ply:PrintMessage(HUD_PRINTCONSOLE, "[Abno] " .. arg2 .. " phrase: " .. phrase)
			print("[TraitorAdmin] " .. who .. " whispered a '" .. arg2 .. "' phrase")
		end

	elseif action == "whisperto" then
		-- v2: seed a working phrase into a PLAYER's red-text channel -
		-- to them it reads as the game choosing them. Only pure results
		-- are sent; an imperfect brute-force falls back to the admin.
		local target = findByUserID(arg1)
		if PLUGIN and MEANINGS[arg2] and IsValid(target) then
			local phrase, success = PLUGIN.FindValidPhrase(arg2, 40, "")
			if success then
				PLUGIN.ShowMessage(target, "Something whispers:")
				PLUGIN.ShowMessage(target, phrase)
				ply:ChatPrint("[Abno] whispered a '" .. arg2 .. "' phrase to " .. target:Nick() .. ": " .. phrase)
				print("[TraitorAdmin] " .. who .. " whispered a '" .. arg2 .. "' phrase to " .. target:Nick())
			else
				ply:ChatPrint("[Abno] couldn't find a pure '" .. arg2 .. "' phrase this roll - try again or re-roll letters")
			end
		end

	elseif action == "bloodrite" then
		-- v2 event preset: hot zone at the admin's feet, pre-banked
		-- Blood, and an ominous line to the whole server in one click
		if PLUGIN and ply:Alive() then
			local blood = GetConVar("zc_abno_rite_blood") and GetConVar("zc_abno_rite_blood"):GetInt() or 3000
			local id = #PLUGIN.Zones + 1
			PLUGIN.Zones[id] = {
				Pos = ply:GetPos(),
				Radius = 200,
				Points = PLUGIN.HotZonePoints + 1,
				Blood = blood,
				Words = {}, Abnormalties = {}, Vars = {}, Chanters = {},
			}
			PLUGIN.HotZones[id] = true
			PLUGIN.ShowMessageToAll("The air grows thick tonight...")
			print("[TraitorAdmin] " .. who .. " performed a Blood Rite (hot zone + " .. blood .. " blood)")
		end

	elseif action == "cast" then
		-- v2: run a ritual's real EFFECT directly - no zone, pattern or
		-- resources. Implemented by inserting into the gamemode's own
		-- delayed-application tables (Heal.ToHeal / Invisibility.ToInvis /
		-- Ressurection.ToRessurect) so the stock Think hooks deliver the
		-- exact stock effect - including the swarm-gated resurrection.
		-- arg2 = "<ritual>:<costs 0|1>"; costs applies the ritual's stock
		-- caster Balance shift to the RECIPIENT.
		local what, costsFlag = string.match(arg2, "^(%a+):([01])$")
		local costs = costsFlag == "1"
		if PLUGIN and what then
			if what == "heal" then
				local target = findByUserID(arg1)
				if IsValid(target) and target:Alive() and not PLUGIN.Heal.ToHeal[target] then
					PLUGIN.Heal.ToHeal[target] = { Owner = target, Time = CurTime(), Zone = nil }
					if costs then PLUGIN.AddConsequences(target, -20) end
					print("[TraitorAdmin] " .. who .. " cast Heal on " .. target:Nick() .. (costs and " (with Balance cost)" or ""))
				end
			elseif what == "invis" then
				local target = findByUserID(arg1)
				if IsValid(target) and target:Alive() and not PLUGIN.Invisibility.ToInvis[target] then
					PLUGIN.Invisibility.ToInvis[target] = { Owner = target, Time = CurTime() }
					if costs then PLUGIN.AddConsequences(target, 20) end
					print("[TraitorAdmin] " .. who .. " cast Invisibility on " .. target:Nick() .. (costs and " (with Balance cost)" or ""))
				end
			elseif what == "bcast" then
				local target = findByUserID(arg1)
				if IsValid(target) and target:Alive() then
					PLUGIN.Broadcast.Do(target)
					if costs then PLUGIN.AddConsequences(target, 10) end
					print("[TraitorAdmin] " .. who .. " cast Broadcast on " .. target:Nick() .. (costs and " (with Balance cost)" or ""))
				end
			elseif what == "res" then
				-- nearest dead body within 500u of the ADMIN
				local best, bestD = nil, 500 * 500
				for _, ent in ipairs(ents.FindInSphere(ply:GetPos(), 500)) do
					if ent:GetClass() == "prop_ragdoll" then
						local owner = ent.ply
						if IsValid(owner) and not owner:Alive() then
							local body = owner.FakeRagdoll or owner:GetNWEntity("RagdollDeath", owner.FakeRagdoll)
							if IsValid(body) then
								local d = ply:GetPos():DistToSqr(body:GetPos())
								if d < bestD then best, bestD = { owner = owner, body = body }, d end
							end
						end
					end
				end
				if best and not PLUGIN.Ressurection.ToRessurect[best.owner] then
					PLUGIN.Ressurection.ToRessurect[best.owner] = { Owner = best.owner, Body = best.body, Time = CurTime() }
					if costs then PLUGIN.AddConsequences(best.owner, -50) end
					print("[TraitorAdmin] " .. who .. " cast Resurrection on " .. best.owner:Nick() .. (costs and " (with Balance cost)" or ""))
				else
					ply:ChatPrint("[Abno] no dead body within 500 units of you" .. (best and " (already resurrecting)" or ""))
				end
			end
		end

	elseif action == "infect" then
		local target = findByUserID(arg1)
		if IsValid(target) and target:Alive() then
			target.Swm = true
			print("[TraitorAdmin] " .. who .. " infected " .. target:Nick() .. " with Swarm")
		end

	elseif action == "cure" then
		local target = findByUserID(arg1)
		if IsValid(target) and target.ClearSwarm then
			target:ClearSwarm()
			print("[TraitorAdmin] " .. who .. " cured " .. target:Nick() .. " of Swarm")
		end

	elseif action == "killswarm" then
		local n = 0
		for _, ent in ipairs(ents.FindByClass("npc_swarm*")) do
			if IsValid(ent) then ent:Remove() n = n + 1 end
		end
		print("[TraitorAdmin] " .. who .. " removed " .. n .. " swarm NPC(s)")
	end

	SendAbnoData(ply)
end)
