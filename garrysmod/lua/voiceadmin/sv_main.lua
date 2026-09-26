VoiceAdmin = VoiceAdmin or {}
local VA = VoiceAdmin
if VA.Server and VA.Shutdown then
    pcall(VA.Shutdown, "server file reload")
end
VA.Generation = (VA.Generation or 0) + 1
local CFG = VA.Config

local cvEnabled = CreateConVar("voiceadmin_enabled", "1", FCVAR_ARCHIVE, "Enable VoiceAdmin.")
local cvExecute = CreateConVar("voiceadmin_execution_enabled", "0", FCVAR_ARCHIVE, "Allow VoiceAdmin to dispatch ULX moderation commands.")
local cvDebug = CreateConVar("voiceadmin_debug", "0", FCVAR_ARCHIVE, "Verbose VoiceAdmin diagnostics.")

for _, name in pairs(VA.Net) do
    util.AddNetworkString(name)
end

VA.Server = {
    generation = VA.Generation,
    ready = false,
    locks = setmetatable({}, { __mode = "k" }),
    pending = setmetatable({}, { __mode = "k" }),
    requests = {},
    activeDispatch = setmetatable({}, { __mode = "k" }),
    rate = setmetatable({}, { __mode = "k" }),
    nextLock = 0,
    nextRequest = 0,
}

local S = VA.Server
local CHALLENGE_WORDS = {
    "amber", "cedar", "delta", "falcon", "harbor", "mango",
    "orbit", "raven", "tiger", "velvet", "willow", "zenith"
}

local TERMINAL = {
    VERIFIED = true,
    REJECTED = true,
    PRECALL_REJECTED = true,
    CANCELLED = true,
    EXPIRED = true,
    UNKNOWN = true,
    STATE_CHANGED = true,
}

local function dbg(...)
    if not cvDebug:GetBool() then return end
    MsgC(Color(120, 200, 255), "[VoiceAdmin] ")
    print(...)
end

local function qstr(value)
    return sql.SQLStr(tostring(value or ""))
end

local function sqlExec(query)
    local result = sql.Query(query)
    if result == false then
        return false, sql.LastError() or "unknown sqlite error"
    end
    return true, result
end

local function journalSchema()
    local ok, err = sqlExec([[
        CREATE TABLE IF NOT EXISTS voiceadmin_requests (
            request_id TEXT PRIMARY KEY,
            generation INTEGER,
            revision INTEGER,
            actor_sid TEXT,
            actor_sid64 TEXT,
            target_sid TEXT,
            target_sid64 TEXT,
            target_userid INTEGER,
            action INTEGER,
            duration_kind INTEGER,
            duration_minutes INTEGER,
            reason TEXT,
            state TEXT,
            created_at INTEGER,
            confirmed_at INTEGER,
            dispatch_intent_at INTEGER,
            callback_at INTEGER,
            verified_at INTEGER,
            result_code TEXT,
            result_detail TEXT
        )
    ]])
    if not ok then ErrorNoHalt("[VoiceAdmin] journal schema failed: " .. tostring(err) .. "\n") end
    return ok
end

local function journalInsert(req)
    local query = string.format(
        "INSERT INTO voiceadmin_requests " ..
        "(request_id,generation,revision,actor_sid,actor_sid64,target_sid,target_sid64,target_userid,action,duration_kind,duration_minutes,reason,state,created_at,confirmed_at,dispatch_intent_at,callback_at,verified_at,result_code,result_detail) " ..
        "VALUES (%s,%d,%d,%s,%s,%s,%s,%d,%d,%d,%d,%s,%s,%d,0,0,0,0,'','')",
        qstr(req.id), req.generation, req.revision,
        qstr(req.actorSid), qstr(req.actorSid64),
        qstr(req.targetSid), qstr(req.targetSid64), req.targetUserId,
        req.action, req.durationKind, req.durationMinutes or 0,
        qstr(req.reason or ""), qstr(req.state), req.createdAt
    )
    return sqlExec(query)
end

local function journalUpdate(req)
    local query = string.format(
        "UPDATE voiceadmin_requests SET revision=%d,duration_kind=%d,duration_minutes=%d,reason=%s,state=%s," ..
        "confirmed_at=%d,dispatch_intent_at=%d,callback_at=%d,verified_at=%d,result_code=%s,result_detail=%s WHERE request_id=%s",
        req.revision, req.durationKind, req.durationMinutes or 0, qstr(req.reason or ""), qstr(req.state),
        req.confirmedAt or 0, req.dispatchIntentAt or 0, req.callbackAt or 0, req.verifiedAt or 0,
        qstr(req.resultCode or ""), qstr(req.resultDetail or ""), qstr(req.id)
    )
    return sqlExec(query)
end

local function hasBridgeAccess(ply)
    if not cvEnabled:GetBool() or not IsValid(ply) or not ply:IsPlayer() then return false end
    if not ULib or not ULib.ucl or not ULib.ucl.query then return false end
    local allowed = ULib.ucl.query(ply, CFG.Permission)
    return allowed == true
end

local function rateAllowed(ply, bucket, limit, window)
    local now = CurTime()
    local byPlayer = S.rate[ply]
    if not byPlayer then
        byPlayer = {}
        S.rate[ply] = byPlayer
    end
    local items = byPlayer[bucket] or {}
    local kept = {}
    for i = 1, #items do
        if now - items[i] <= window then kept[#kept + 1] = items[i] end
    end
    byPlayer[bucket] = kept
    if #kept >= limit then return false end
    kept[#kept + 1] = now
    return true
end

local function netGuard(ply, bits, bucket, limit, window)
    if bits > CFG.MaxNetBits then return false end
    if not S.ready or not hasBridgeAccess(ply) then return false end
    return rateAllowed(ply, bucket, limit, window)
end

local function suffix(sid64)
    sid64 = tostring(sid64 or "")
    return sid64:sub(math.max(1, #sid64 - 3))
end

local function currentTarget(reqOrLock)
    for _, ply in ipairs(player.GetAll()) do
        if ply:SteamID() == reqOrLock.targetSid
            and ply:SteamID64() == reqOrLock.targetSid64
            and ply:UserID() == reqOrLock.targetUserId then
            return ply
        end
    end
end

local function fullyAuthenticated(ply)
    if not IsValid(ply) then return false end
    if not ply.IsFullyAuthenticated then return true end
    return ply:IsFullyAuthenticated()
end

local function sendResult(ply, reqId, code, text)
    if not IsValid(ply) then return end
    net.Start(VA.Net.Result)
    net.WriteString(tostring(reqId or ""))
    net.WriteString(tostring(code or ""))
    net.WriteString(tostring(text or ""))
    net.Send(ply)
end

local function finish(req, state, code, detail)
    if TERMINAL[req.state] then return end
    req.state = state
    req.resultCode = code or state
    req.resultDetail = detail or ""
    req.verifiedAt = os.time()
    journalUpdate(req)

    if IsValid(req.actor) then
        sendResult(req.actor, req.id, req.resultCode, req.resultDetail)
        if S.pending[req.actor] == req then S.pending[req.actor] = nil end
        if S.activeDispatch[req.actor] == req then S.activeDispatch[req.actor] = nil end
    end

    timer.Create("VoiceAdmin.Forget." .. req.id, 60, 1, function()
        if S.requests[req.id] == req then S.requests[req.id] = nil end
    end)
end

local function reject(ply, text)
    sendResult(ply, "", "REJECTED", text)
end

local function challenge()
    local a = CHALLENGE_WORDS[math.random(1, #CHALLENGE_WORDS)]
    local b = CHALLENGE_WORDS[math.random(1, #CHALLENGE_WORDS)]
    while b == a do b = CHALLENGE_WORDS[math.random(1, #CHALLENGE_WORDS)] end
    return a, b
end

local function commandAccessExists(commandName)
    if not ULib or not ULib.ucl or not ULib.ucl.query then return false end
    return isstring(commandName) and commandName:sub(1, 4) == "ulx "
end

local function validateLock(lock)
    if not lock or lock.expiresAt < CurTime() then return nil, "target lock expired" end
    local target = currentTarget(lock)
    if not IsValid(target) then return nil, "target disconnected or reconnected" end
    return target
end

local function validateProposal(action, durationKind, minutes, reason)
    if not VA.ActionName[action] then return nil, "unsupported action" end
    local normalized, err = VA.NormalizeReason(reason or "")
    if not normalized then return nil, err end

    if action == VA.Action.BAN then
        if durationKind == VA.Duration.PERMANENT then
            minutes = 0
        elseif durationKind == VA.Duration.TEMPORARY then
            minutes = math.floor(tonumber(minutes) or 0)
            if minutes < 1 or minutes > 5256000 then
                return nil, "temporary ban duration is outside the allowed range"
            end
        else
            return nil, "ban duration is missing"
        end
    else
        durationKind = VA.Duration.NONE
        minutes = 0
        if action == VA.Action.FREEZE or action == VA.Action.UNFREEZE then normalized = "" end
    end

    return {
        action = action,
        durationKind = durationKind,
        durationMinutes = minutes,
        reason = normalized,
    }
end

local function promptFor(req)
    local target = req.targetName
    local reason = req.reason ~= "" and (" for " .. req.reason) or ""
    local actionText
    if req.action == VA.Action.BAN then
        if req.durationKind == VA.Duration.PERMANENT then
            actionText = "Permanent ban " .. target .. reason .. "."
        else
            actionText = "Ban " .. target .. " for " .. VA.DurationText(req.durationKind, req.durationMinutes) .. reason .. "."
        end
    elseif req.action == VA.Action.KICK then
        actionText = "Kick " .. target .. reason .. "."
    elseif req.action == VA.Action.FREEZE then
        actionText = "Freeze " .. target .. "."
    else
        actionText = "Unfreeze " .. target .. "."
    end
    return actionText .. " Confirmation words: " .. req.challengeA .. " " .. req.challengeB .. "."
end

local function sendPreview(req)
    if not IsValid(req.actor) then return end
    net.Start(VA.Net.Preview)
    net.WriteString(req.id)
    net.WriteUInt(req.revision, 16)
    net.WriteString(VA.ActionName[req.action])
    net.WriteString(req.targetName)
    net.WriteString(suffix(req.targetSid64))
    net.WriteString(VA.DurationText(req.durationKind, req.durationMinutes))
    net.WriteString(req.reason or "")
    net.WriteString(req.challengeA)
    net.WriteString(req.challengeB)
    net.WriteString(promptFor(req))
    net.Send(req.actor)
end

local function verifyBanPersisted(req)
    local query = "SELECT steamid,time,unban,reason,name,admin,modified_admin,modified_time FROM ulib_bans WHERE steamid=" .. qstr(req.targetSid64)
    local rows = sql.Query(query)
    if rows == false then return false, "ban database query failed: " .. tostring(sql.LastError()) end
    if not istable(rows) or not rows[1] then return false, "ban row is not present" end

    local row = rows[1]
    local storedReason = tostring(row.reason or "")
    if storedReason ~= tostring(req.reason or "") then
        return false, "persisted ban reason differs from this request"
    end

    local unban = tonumber(row.unban) or -1
    if req.durationKind == VA.Duration.PERMANENT then
        if unban ~= 0 then return false, "persisted ban is not permanent" end
    else
        local expected = (req.dispatchIntentAt or os.time()) + req.durationMinutes * 60
        if unban <= 0 or math.abs(unban - expected) > 15 then
            return false, "persisted ban duration differs from this request"
        end
    end

    local adminText = tostring(row.modified_admin or "") .. " " .. tostring(row.admin or "")
    if req.actorSid ~= "" and not adminText:find(req.actorSid, 1, true) then
        return false, "persisted ban administrator differs from this request"
    end

    if ULib and ULib.bans then
        local memory = ULib.bans[req.targetSid]
        if not memory then return false, "ULib in-memory ban record is missing" end
        if tostring(memory.reason or "") ~= tostring(req.reason or "") then
            return false, "ULib in-memory ban reason differs from this request"
        end
    end

    return true
end

local function verifyBan(req, attempt)
    if TERMINAL[req.state] then return end
    local ok, detail = verifyBanPersisted(req)
    if ok then
        finish(req, "VERIFIED", "VERIFIED", "Ban recorded for " .. req.targetName .. ".")
        return
    end
    attempt = (attempt or 0) + 1
    if attempt * 0.10 < CFG.BanVerifySeconds then
        timer.Create("VoiceAdmin.BanVerify." .. req.id, 0.10, 1, function() verifyBan(req, attempt) end)
        return
    end
    finish(req, "UNKNOWN", "UNKNOWN", "ULX attempted the ban, but persistence could not be verified: " .. tostring(detail))
end

local function verifyFreeze(req)
    if TERMINAL[req.state] then return end
    local target = currentTarget(req)
    if not IsValid(target) then
        finish(req, "UNKNOWN", "UNKNOWN", "ULX callback ran, but the target is no longer the same connection.")
        return
    end
    local expected = req.action == VA.Action.FREEZE
    if (target.frozen == true) == expected then
        finish(req, "VERIFIED", "VERIFIED", (expected and "Freeze applied to " or "Unfreeze applied to ") .. req.targetName .. ".")
    else
        finish(req, "STATE_CHANGED", "STATE_CHANGED", "ULX callback ran, but the resulting freeze state did not match the request.")
    end
end

local function buildUlxArgs(req)
    local selector = "$" .. req.targetSid
    if req.action == VA.Action.FREEZE then return { "freeze", selector }, "ulx freeze" end
    if req.action == VA.Action.UNFREEZE then return { "unfreeze", selector }, "ulx unfreeze" end
    if req.action == VA.Action.KICK then
        local args = { "kick", selector }
        if req.reason ~= "" then args[#args + 1] = req.reason end
        return args, "ulx kick"
    end
    if req.action == VA.Action.BAN then
        local minutes = req.durationKind == VA.Duration.PERMANENT and 0 or req.durationMinutes
        local args = { "ban", selector, tostring(minutes) }
        if req.reason ~= "" then args[#args + 1] = req.reason end
        return args, "ulx ban"
    end
end

local function dispatch(req)
    if not cvExecute:GetBool() then
        finish(req, "REJECTED", "EXECUTION_DISABLED", "VoiceAdmin execution is disabled on the server.")
        return
    end

    local target = currentTarget(req)
    if not IsValid(target) then
        finish(req, "REJECTED", "TARGET_CHANGED", "Target disconnected or reconnected before execution.")
        return
    end
    if req.action == VA.Action.KICK and target:IsListenServerHost() then
        finish(req, "REJECTED", "TARGET_INVALID", "The listen-server host is immune to kicking.")
        return
    end
    if req.action == VA.Action.BAN then
        if target:IsBot() or target:IsListenServerHost() or not fullyAuthenticated(target) then
            finish(req, "REJECTED", "TARGET_INVALID", "Target is not eligible for an online ban.")
            return
        end
    end

    req.state = "DISPATCH_INTENT"
    req.dispatchIntentAt = os.time()
    local ok, err = journalUpdate(req)
    if not ok then
        req.state = "REJECTED"
        req.resultCode = "JOURNAL_FAILED"
        req.resultDetail = "Dispatch journal write failed: " .. tostring(err)
        sendResult(req.actor, req.id, req.resultCode, req.resultDetail)
        if S.pending[req.actor] == req then S.pending[req.actor] = nil end
        return
    end

    local rawArgs, expectedCommand = buildUlxArgs(req)
    if not rawArgs then
        finish(req, "REJECTED", "ADAPTER_ERROR", "No ULX adapter exists for this action.")
        return
    end

    local cmdTable, commandName, argv = ULib.cmds.getCommandTableAndArgv("ulx", rawArgs, false)
    if not cmdTable or not cmdTable.__fn then
        finish(req, "REJECTED", "ADAPTER_ERROR", "Installed ULib could not resolve " .. tostring(expectedCommand) .. ".")
        return
    end

    req.expectedCommand = expectedCommand
    req.state = "DISPATCHING"
    journalUpdate(req)
    S.activeDispatch[req.actor] = req

    local success, callErr = xpcall(function()
        ULib.cmds.execute(cmdTable, req.actor, commandName, argv)
    end, debug.traceback)

    if not success then
        S.activeDispatch[req.actor] = nil
        finish(req, "UNKNOWN", "DISPATCH_ERROR", "ULib raised an error during dispatch; outcome is uncertain. " .. tostring(callErr))
        return
    end

    if not req.callbackReached then
        S.activeDispatch[req.actor] = nil
        finish(req, "PRECALL_REJECTED", "ULX_REJECTED", "ULib rejected the request before the ULX callback was reached.")
        return
    end

    if req.action == VA.Action.FREEZE or req.action == VA.Action.UNFREEZE then
        timer.Create("VoiceAdmin.FreezeVerify." .. req.id, 0, 1, function() verifyFreeze(req) end)
    elseif req.action == VA.Action.KICK then
        timer.Create("VoiceAdmin.KickWatch." .. req.id, CFG.KickVerifySeconds, 1, function()
            if not TERMINAL[req.state] then
                local stillThere = currentTarget(req)
                if req.kickIssued and not IsValid(stillThere) then
                    finish(req, "VERIFIED", "VERIFIED", "Kick completed for " .. req.targetName .. ".")
                else
                    finish(req, "UNKNOWN", "UNKNOWN", "ULX attempted the kick, but disconnect could not be confirmed.")
                end
            end
        end)
    elseif req.action == VA.Action.BAN then
        timer.Create("VoiceAdmin.BanWatch." .. req.id, CFG.BanVerifySeconds + 0.25, 1, function()
            if not TERMINAL[req.state] then verifyBan(req, 999) end
        end)
    end
end

local function newRequest(ply, lock, proposal)
    S.nextRequest = S.nextRequest + 1
    local id = string.format("%d-%d-%d", os.time(), S.generation, S.nextRequest)
    local a, b = challenge()
    local req = {
        id = id,
        generation = S.generation,
        revision = 1,
        actor = ply,
        actorSid = ply:SteamID(),
        actorSid64 = ply:SteamID64(),
        targetSid = lock.targetSid,
        targetSid64 = lock.targetSid64,
        targetUserId = lock.targetUserId,
        targetName = lock.targetName,
        action = proposal.action,
        durationKind = proposal.durationKind,
        durationMinutes = proposal.durationMinutes,
        reason = proposal.reason,
        challengeA = a,
        challengeB = b,
        state = "AWAITING_CONFIRMATION",
        createdAt = os.time(),
        expiresAt = CurTime() + CFG.RequestTTL,
    }

    local ok, err = journalInsert(req)
    if not ok then return nil, "request journal unavailable: " .. tostring(err) end
    S.requests[id] = req
    S.pending[ply] = req

    timer.Create("VoiceAdmin.Expire." .. id, CFG.RequestTTL, 1, function()
        if req.state == "AWAITING_CONFIRMATION" then
            finish(req, "EXPIRED", "EXPIRED", "VoiceAdmin request expired.")
        end
    end)

    return req
end

local function previewAmended(req)
    req.revision = req.revision + 1
    req.challengeA, req.challengeB = challenge()
    req.expiresAt = CurTime() + CFG.RequestTTL
    local ok, err = journalUpdate(req)
    if not ok then
        finish(req, "REJECTED", "JOURNAL_FAILED", "Could not journal the amended request: " .. tostring(err))
        return
    end
    timer.Adjust("VoiceAdmin.Expire." .. req.id, CFG.RequestTTL, 1, function()
        if req.state == "AWAITING_CONFIRMATION" then
            finish(req, "EXPIRED", "EXPIRED", "VoiceAdmin request expired.")
        end
    end)
    sendPreview(req)
end

hook.Add(ULib and ULib.HOOK_POST_TRANSLATED_COMMAND or "ULibPostTranslatedCommand", "VoiceAdmin.PostTranslated", function(ply, commandName)
    local req = S.activeDispatch[ply]
    if not req or TERMINAL[req.state] then return end
    if commandName ~= req.expectedCommand then return end
    req.callbackReached = true
    req.callbackAt = os.time()
    req.state = "CALLBACK_REACHED"
    journalUpdate(req)
    if req.action == VA.Action.BAN or req.action == VA.Action.KICK then
        req.state = "VERIFYING"
        journalUpdate(req)
    end
end)

hook.Add(ULib and ULib.HOOK_USER_BANNED or "ULibPlayerBanned", "VoiceAdmin.Banned", function(steamid)
    for _, req in pairs(S.requests) do
        if req.action == VA.Action.BAN and not TERMINAL[req.state]
            and req.callbackReached and req.targetSid == steamid then
            timer.Create("VoiceAdmin.BanVerify." .. req.id, 0, 1, function() verifyBan(req, 0) end)
        end
    end
end)

hook.Add(ULib and ULib.HOOK_USER_KICKED or "ULibPlayerKicked", "VoiceAdmin.Kicked", function(steamid, reason, callingPly)
    for _, req in pairs(S.requests) do
        if req.action == VA.Action.KICK and not TERMINAL[req.state]
            and req.callbackReached and req.targetSid == steamid and req.actor == callingPly then
            req.kickIssued = true
            req.state = "VERIFYING"
            journalUpdate(req)
        end
    end
end)

gameevent.Listen("player_disconnect")
hook.Add("player_disconnect", "VoiceAdmin.PlayerDisconnect", function(data)
    local sid = tostring(data.networkid or "")
    local uid = tonumber(data.userid or -1)
    for _, req in pairs(S.requests) do
        if req.action == VA.Action.KICK and req.kickIssued and not TERMINAL[req.state]
            and req.targetSid == sid and req.targetUserId == uid then
            finish(req, "VERIFIED", "VERIFIED", "Kick completed for " .. req.targetName .. ".")
        end
    end
end)

net.Receive(VA.Net.LockRequest, function(bits, ply)
    if not netGuard(ply, bits, "lock", 8, 4) then return end
    local utterance = VA.SafeId(net.ReadString())
    local entIndex = net.ReadUInt(16)

    net.Start(VA.Net.LockResult)
    if not utterance then
        net.WriteBool(false)
        net.WriteString("")
        net.WriteString("invalid utterance id")
        net.Send(ply)
        return
    end

    local target = Entity(entIndex)
    if not IsValid(target) or not target:IsPlayer() then
        net.WriteBool(false)
        net.WriteString(utterance)
        net.WriteString("No player is directly selected.")
        net.Send(ply)
        return
    end

    S.nextLock = S.nextLock + 1
    local lock = {
        id = S.nextLock,
        utterance = utterance,
        targetSid = target:SteamID(),
        targetSid64 = target:SteamID64(),
        targetUserId = target:UserID(),
        targetName = target:Nick(),
        createdAt = CurTime(),
        expiresAt = CurTime() + CFG.LockTTL,
    }
    S.locks[ply] = lock

    net.WriteBool(true)
    net.WriteString(utterance)
    net.WriteUInt(lock.id, 32)
    net.WriteString(lock.targetName)
    net.WriteString(suffix(lock.targetSid64))
    net.Send(ply)
end)

net.Receive(VA.Net.Propose, function(bits, ply)
    if not netGuard(ply, bits, "propose", 5, 5) then return end
    local lockId = net.ReadUInt(32)
    local action = net.ReadUInt(8)
    local durationKind = net.ReadUInt(8)
    local minutes = net.ReadUInt(32)
    local reason = net.ReadString()

    if S.pending[ply] and not TERMINAL[S.pending[ply].state] then
        reject(ply, "A VoiceAdmin request is already pending. Confirm it or cancel it first.")
        return
    end

    local lock = S.locks[ply]
    if not lock or lock.id ~= lockId then reject(ply, "Target lock does not match this request.") return end
    local target, lockErr = validateLock(lock)
    if not target then reject(ply, lockErr) return end

    local proposal, propErr = validateProposal(action, durationKind, minutes, reason)
    if not proposal then reject(ply, propErr) return end

    if action == VA.Action.BAN then
        if target:IsBot() or target:IsListenServerHost() or not fullyAuthenticated(target) then
            reject(ply, "That player is not eligible for an online ban.")
            return
        end
    end

    local req, reqErr = newRequest(ply, lock, proposal)
    if not req then reject(ply, reqErr) return end
    sendPreview(req)
end)
net.Receive(VA.Net.Confirm, function(bits, ply)
    if not netGuard(ply, bits, "confirm", 6, 5) then return end
    local id = net.ReadString()
    local revision = net.ReadUInt(16)
    local wordA = string.lower(net.ReadString())
    local wordB = string.lower(net.ReadString())

    local req = S.pending[ply]
    if not req or req.id ~= id then reject(ply, "No matching VoiceAdmin request is pending.") return end
    if req.state ~= "AWAITING_CONFIRMATION" then reject(ply, "That request can no longer be confirmed.") return end
    if req.revision ~= revision then reject(ply, "That confirmation belongs to an older request revision.") return end
    if req.expiresAt < CurTime() then finish(req, "EXPIRED", "EXPIRED", "VoiceAdmin request expired.") return end
    if wordA ~= req.challengeA or wordB ~= req.challengeB then reject(ply, "Confirmation challenge did not match.") return end

    local target = currentTarget(req)
    if not IsValid(target) then finish(req, "REJECTED", "TARGET_CHANGED", "Target disconnected or reconnected before confirmation.") return end
    if not hasBridgeAccess(ply) then finish(req, "REJECTED", "PERMISSION_REVOKED", "VoiceAdmin permission is no longer available.") return end

    req.confirmedAt = os.time()
    req.state = "CONFIRMED"
    local ok, err = journalUpdate(req)
    if not ok then
        finish(req, "REJECTED", "JOURNAL_FAILED", "Could not journal confirmation: " .. tostring(err))
        return
    end
    dispatch(req)
end)

net.Receive(VA.Net.Cancel, function(bits, ply)
    if not netGuard(ply, bits, "cancel", 8, 5) then return end
    local req = S.pending[ply]
    if not req then reject(ply, "No VoiceAdmin request is pending.") return end
    if req.state ~= "AWAITING_CONFIRMATION" and req.state ~= "CONFIRMED" then
        reject(ply, "Too late. The command is already being dispatched or verified.")
        return
    end
    finish(req, "CANCELLED", "CANCELLED", "VoiceAdmin request cancelled.")
end)

net.Receive(VA.Net.Amend, function(bits, ply)
    if not netGuard(ply, bits, "amend", 5, 5) then return end
    local req = S.pending[ply]
    if not req or req.state ~= "AWAITING_CONFIRMATION" then reject(ply, "No amendable VoiceAdmin request is pending.") return end

    local changeDuration = net.ReadBool()
    local durationKind = net.ReadUInt(8)
    local minutes = net.ReadUInt(32)
    local changeReason = net.ReadBool()
    local reason = net.ReadString()

    if changeDuration then
        if req.action ~= VA.Action.BAN then reject(ply, "Only ban requests have a duration.") return end
        if durationKind == VA.Duration.PERMANENT then
            req.durationKind = durationKind
            req.durationMinutes = 0
        elseif durationKind == VA.Duration.TEMPORARY and minutes >= 1 and minutes <= 5256000 then
            req.durationKind = durationKind
            req.durationMinutes = math.floor(minutes)
        else
            reject(ply, "Invalid amended ban duration.")
            return
        end
    end

    if changeReason then
        local normalized, err = VA.NormalizeReason(reason)
        if not normalized then reject(ply, err) return end
        req.reason = normalized
    end

    if not changeDuration and not changeReason then reject(ply, "Nothing was changed.") return end
    previewAmended(req)
end)

local function compatibilityProbe()
    local issues = {}
    if not ULib then issues[#issues + 1] = "ULib global missing" end
    if not ulx then issues[#issues + 1] = "ULX global missing" end
    if not ULib or not ULib.cmds or not isfunction(ULib.cmds.getCommandTableAndArgv) then
        issues[#issues + 1] = "ULib.cmds.getCommandTableAndArgv missing"
    end
    if not ULib or not ULib.cmds or not isfunction(ULib.cmds.execute) then
        issues[#issues + 1] = "ULib.cmds.execute missing"
    end
    if not sql.TableExists("ulib_bans") then issues[#issues + 1] = "ulib_bans table missing" end

    if #issues == 0 then
        local tests = { "freeze", "unfreeze", "kick", "ban" }
        for _, sub in ipairs(tests) do
            local t = ULib.cmds.getCommandTableAndArgv("ulx", { sub, "$STEAM_0:0:0" }, false)
            if not t then issues[#issues + 1] = "unable to resolve ulx " .. sub end
        end
    end

    S.compatIssues = issues
    return #issues == 0
end

local function recoverBanRow(row, attempt)
    local req = {
        targetSid = tostring(row.target_sid or ""),
        targetSid64 = tostring(row.target_sid64 or ""),
        actorSid = tostring(row.actor_sid or ""),
        durationKind = tonumber(row.duration_kind) or VA.Duration.NONE,
        durationMinutes = tonumber(row.duration_minutes) or 0,
        reason = tostring(row.reason or ""),
        dispatchIntentAt = tonumber(row.dispatch_intent_at) or 0,
    }
    local ok, detail = verifyBanPersisted(req)
    if ok then
        sqlExec("UPDATE voiceadmin_requests SET state='VERIFIED',result_code='RECOVERED_VERIFIED',result_detail='Recovered persisted ban' WHERE request_id=" .. qstr(row.request_id))
        return
    end

    attempt = (attempt or 0) + 1
    if attempt * 0.10 < CFG.BanVerifySeconds then
        timer.Create("VoiceAdmin.RecoverBan." .. tostring(row.request_id), 0.10, 1, function()
            recoverBanRow(row, attempt)
        end)
        return
    end

    sqlExec("UPDATE voiceadmin_requests SET state='UNKNOWN',result_code='RECOVERY_UNKNOWN',result_detail=" .. qstr(tostring(detail)) .. " WHERE request_id=" .. qstr(row.request_id))
end

local function recoverySweep()
    local rows = sql.Query("SELECT * FROM voiceadmin_requests WHERE state NOT IN ('VERIFIED','REJECTED','PRECALL_REJECTED','CANCELLED','EXPIRED','UNKNOWN','STATE_CHANGED')")
    if rows == false or not istable(rows) then return end

    for _, row in ipairs(rows) do
        local state = tostring(row.state or "")
        if state == "AWAITING_CONFIRMATION" or state == "CONFIRMED" then
            sqlExec("UPDATE voiceadmin_requests SET state='EXPIRED',result_code='RELOAD_EXPIRED',result_detail='Expired during addon/server reload' WHERE request_id=" .. qstr(row.request_id))
        elseif tonumber(row.action) == VA.Action.BAN then
            local recoveryRow = table.Copy(row)
            recoverBanRow(recoveryRow, 0)
        else
            sqlExec("UPDATE voiceadmin_requests SET state='UNKNOWN',result_code='RECOVERY_UNKNOWN',result_detail='Dispatch state could not be safely replayed after reload' WHERE request_id=" .. qstr(row.request_id))
        end
    end
end

local initAttempts = 0
local function initialize()
    initAttempts = initAttempts + 1
    if not ULib or not ulx or not ULib.ucl then
        if initAttempts < 100 then timer.Create("VoiceAdmin.InitRetry", 0.1, 1, initialize) end
        return
    end

    ULib.ucl.registerAccess(CFG.Permission, ULib.ACCESS_SUPERADMIN, "Allows use of the VoiceAdmin bridge. ULX command permissions still apply.", "Other")
    if not journalSchema() then return end

    S.ready = compatibilityProbe()
    if S.ready then recoverySweep() end

    if S.ready then
        MsgC(Color(100, 255, 130), "[VoiceAdmin] ready v" .. VA.VERSION .. "; execution=" .. tostring(cvExecute:GetBool()) .. "\n")
    else
        ErrorNoHalt("[VoiceAdmin] compatibility probe failed: " .. table.concat(S.compatIssues or {}, "; ") .. "\n")
    end
end

concommand.Add("voiceadmin_status", function(ply)
    if IsValid(ply) and not hasBridgeAccess(ply) then return end
    local lines = {
        "VoiceAdmin " .. VA.VERSION,
        "generation=" .. tostring(S.generation),
        "ready=" .. tostring(S.ready),
        "enabled=" .. tostring(cvEnabled:GetBool()),
        "execution=" .. tostring(cvExecute:GetBool()),
        "pending=" .. tostring(table.Count(S.requests)),
    }
    if S.compatIssues and #S.compatIssues > 0 then
        lines[#lines + 1] = "issues=" .. table.concat(S.compatIssues, "; ")
    end
    local msg = table.concat(lines, " | ")
    if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, msg .. "\n") else print(msg) end
end)

concommand.Add("voiceadmin_selftest", function(ply)
    if IsValid(ply) and not hasBridgeAccess(ply) then return end
    local ok = S.ready and journalSchema() and compatibilityProbe()
    local msg = ok and "VoiceAdmin self-test PASS (no moderation action executed)." or "VoiceAdmin self-test FAIL."
    if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, msg .. "\n") else print(msg) end
end)

function VA.Shutdown(reason)
    if not VA.Server then return end
    for _, req in pairs(S.requests or {}) do
        if req.state == "AWAITING_CONFIRMATION" or req.state == "CONFIRMED" then
            req.state = "EXPIRED"
            req.resultCode = "RELOAD_EXPIRED"
            req.resultDetail = "Expired during VoiceAdmin reload."
            journalUpdate(req)
        end
    end

    hook.Remove("ULibPostTranslatedCommand", "VoiceAdmin.PostTranslated")
    hook.Remove("ULibPlayerBanned", "VoiceAdmin.Banned")
    hook.Remove("ULibPlayerKicked", "VoiceAdmin.Kicked")
    hook.Remove("player_disconnect", "VoiceAdmin.PlayerDisconnect")
    for timerName in pairs(timer.GetTable()) do
        if isstring(timerName) and string.StartWith(timerName, "VoiceAdmin.") then
            timer.Remove(timerName)
        end
    end
    dbg("shutdown", reason or "")
end

timer.Simple(0, initialize)
