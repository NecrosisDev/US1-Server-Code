local M = SolidMapVote
local cvAudio = CreateConVar("smv_custom_rtv_internal", "0", FCVAR_ARCHIVE)
concommand.Add("smv_custom_rtv_enable", function(ply, _, args)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end
    if args[1] then cvAudio:SetBool(tonumber(args[1]) == 1) end
    local text = "Custom RTV songs: " .. (cvAudio:GetBool() and "ON" or "OFF")
    if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, text) else print(text) end
end, nil, "Superadmin: custom RTV songs: smv_custom_rtv_enable [1|0].")
function M.initialize()
    if M.initialized then return end
    M.votes, M.nominations, M.RTVs = {}, {}, {}
    M.mapPool, M.maps, M.mapPlayCounts, M.poolSet, M.ballotSet = {}, {}, {}, {}, {}
    M.phase, M.isOpen, M.finished, M.pending = "idle", false, false, false
    M.roundBase, M.poolVersion = 0, 0
    M.RTVDelayEnd = RealTime() + M.number("RTV Delay", 60, 0, 3600)
    M.autoStartTime = RealTime() + M.number("Vote Autostart Delay", 3600, 30, 86400)
    M.PleaseRTVs, M.DontRTVs, M.AudioPlayed = {}, {}, false
    M.AudioCooldown = RealTime() + 600
    M.poolMaps(); M.initFairMapRecycling()
    M.initialized = true
end
function M.install()
    if not zb or type(zb.PreRound) ~= "function" then return end
    -- Mirror only the verified small PreRound method; all other round transitions stay in ZCity.
    -- The original map-count gate cannot be called after extension without resetting its counter.
    if zb.PreRound ~= M.preRoundOverride then M.originalPreRound = zb.PreRound end
    M.preRoundOverride = function(self)
        if not M.initialized then return M.originalPreRound(self) end
        if M.isOpen then return end
        local count = self.Roundscount or 0
        if count < M.roundBase then M.roundBase = count end
        local automatic = count - M.roundBase >= math.floor(M.number("Rounds Per Vote", 16, 1, 1000)) and not GetConVar("zb_dev"):GetBool()
        local blockedSeries = self.RoundsLeft and self.CROUND == "cstrike"
        if self.ROUND_STATE == 0 and not blockedSeries and (M.pending or automatic) then
            -- Let your six-second mode ballot finish before opening another fullscreen vote.
            if ZC_MODEVOTE_ACTIVE and ZC_MODEVOTE_ACTIVE() then return end
            M.openBallot()
            if M.isOpen then return end
        end
        if self.ROUND_STATE == 0 and #player.GetAll() > 1 then
            self.END_TIME = nil
            self.START_TIME = self.START_TIME or CurTime() + (CurrentRound().start_time or 5)
            if self.START_TIME < CurTime() then self:RoundStart() end
        end
    end
    zb.PreRound = M.preRoundOverride
    zb.StartRTV = function() M.start() end
    -- Retire the vanilla ballot path while sharing its public votestarted flag.
    -- First installation still requires a clean restart: old anonymous timers cannot be revoked.
    hook.Remove("Think", "RTVThink")
    zb.ThinkRTV, zb.EndRTV = M.checkForVoteEnd, M.checkForVoteEnd
    zb.RTVMenu = function(ply) if M.acceptRequest(ply, "sync", 2) then M.sync(ply) end end
    net.Receive("ZB_RockTheVote_vote", function() end)
    if COMMANDS then COMMANDS.rtv = nil; COMMANDS.forcertv = nil; COMMANDS["кем"] = nil end
end
hook.Add("PostGamemodeLoaded", "SolidMapVote_OverrideZCity", M.install)
hook.Add("InitPostEntity", "SolidMapVote.Init", function() M.initialize(); M.install() end)
-- These replace the upstream hook IDs even on a same-version Lua refresh.
hook.Remove("InitPostEntity", "SolidMapVote_OverrideZCity")
hook.Remove("ZB_PreRoundStart", "SolidMapVote.ZCityVoteTrigger")
hook.Remove("ZB_EndRound", "SolidMapVote.ZCityEndTrigger")
hook.Add("Think", "SolidMapVote.ServerLoop", function()
    if not M.initialized or RealTime() < (M.nextCheck or 0) then return end
    M.nextCheck = RealTime() + 0.1
    M.checkForRTV(); M.checkForVoteEnd(); M.postMapVoteChange(); M.checkForAutostart()
    if M.mapChangeTriggered and RealTime() - M.changeRequested > 15 then
        M.reset("Map change did not complete; voting reset.")
    end
end)
hook.Add("PlayerDisconnected", "SolidMapVote.PlayerLeave", function(ply)
    if not M.initialized then return end
    local id = ply:SteamID64()
    M.RTVs[id], M.PleaseRTVs[id], M.DontRTVs[id] = nil, nil, nil
    if M.requestTimes then M.requestTimes[ply] = nil end
    if M.phase ~= "results" and M.votes[id] then M.votes[id] = nil; M.sendVotes(true) end
    if M.nominations[id] then M.nominations[id] = nil; M.sendNominations(true) end
end)
local function contains(key, command) return table.HasValue(M.Config[key] or {}, command) end
hook.Add("HG_PlayerSay", "SolidMapVote.PlayerCommands", function(ply, txtTbl, text)
    if not M.initialized or not IsValid(ply) or ply:IsBot() then return end
    local cmd = string.lower(string.Trim(text or ""))
    local force, vote, nomination = contains("Force Vote Commands", cmd), contains("Vote Commands", cmd) or cmd == "кем" or cmd == "!кем", contains("Nomination Commands", cmd)
    local soundVote = cmd == "!pleasertv" or cmd == "!dontrtv"
    local timeLeft = contains("Time Left Commands", cmd)
    if not (force or vote or nomination or soundVote or timeLeft) then return end
    if txtTbl then txtTbl[1] = "" end
    if not M.acceptRequest(ply, "chat", 1) then return end
    local id = ply:SteamID64()
    if force then
        if M.Config["Force Vote Permission"](ply) and M.start() then M.sendMessage({color_white, "An admin queued a map vote for the next intermission."}, true) end
    elseif vote then
        if M.isOpen then M.sync(ply); return end
        if M.pending then M.sendMessage({color_white, "The map vote is already queued."}, false, ply); return end
        if RealTime() < M.RTVDelayEnd then M.sendMessage({color_white, "RTV is available in " .. math.ceil(M.RTVDelayEnd - RealTime()) .. " seconds."}, false, ply); return end
        if M.RTVs[id] then
            if M.Config["Enable UnVote"] then M.RTVs[id] = nil end
        else M.RTVs[id] = true end
        M.sendMessage({color_white, ply:Nick() .. " updated their RTV vote (" .. table.Count(M.RTVs) .. "/" .. M.getRTVAmount() .. ")."}, true)
        M.checkForRTV()
    elseif nomination then
        if not M.isOpen and M.Config["Allow Nominations"] and M.Config["Nomination Permissions"](ply) then ply:ConCommand("solidmapvote_nomination_menu") end
    elseif timeLeft then
        local rounds = math.max(0, math.floor(M.number("Rounds Per Vote", 16, 1, 1000)) - ((zb.Roundscount or 0) - M.roundBase))
        M.sendMessage({color_white, tostring(rounds) .. " completed rounds until the automatic map vote."}, false, ply)
    elseif soundVote and cvAudio:GetBool() and not M.isOpen and not M.pending and not M.AudioPlayed and RealTime() >= M.AudioCooldown then
        local yes = cmd == "!pleasertv"
        local target, other = yes and M.PleaseRTVs or M.DontRTVs, yes and M.DontRTVs or M.PleaseRTVs
        other[id] = nil
        if target[id] then if M.Config["Enable UnVote"] then target[id] = nil end else target[id] = true end
        if table.Count(target) >= math.max(1, math.ceil(M.getRTVAmount() / 2)) then
            M.AudioPlayed = true
            net.Start("SolidMapVote.sound"); net.WriteBool(yes); net.Broadcast()
        end
    end
end)
if M.initialized then M.install() end
