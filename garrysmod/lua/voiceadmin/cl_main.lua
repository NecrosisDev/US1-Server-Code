VoiceAdmin = VoiceAdmin or {}
local VA = VoiceAdmin
if VA.Client and VA.Shutdown then
    pcall(VA.Shutdown, "client file reload")
end
local CFG = VA.Config

VA.Client = {
    session = nil,
    expectedSeq = 1,
    outSeq = 0,
    locks = {},
    queuedProposals = {},
    hud = nil,
}

local C = VA.Client
local IN_DIR = "voiceadmin/c2g/"
local OUT_DIR = "voiceadmin/g2c/"
local SESSION_FILE = IN_DIR .. "session.json"

file.CreateDir("voiceadmin")
file.CreateDir("voiceadmin/c2g")
file.CreateDir("voiceadmin/g2c")

local function safeSession(value)
    return VA.SafeId(value)
end

local function atomicWrite(path, text)
    local tmp = path .. ".tmp"
    file.Write(tmp, text)
    if file.Exists(path, "DATA") then file.Delete(path) end
    local ok = file.Rename(tmp, path)
    if ok == false then
        file.Write(path, text)
        file.Delete(tmp)
    end
end

local function writeOut(kind, payload)
    if not C.session then return end
    C.outSeq = C.outSeq + 1
    payload = payload or {}
    payload.type = kind
    payload.protocol = VA.PROTOCOL
    payload.session = C.session
    payload.seq = C.outSeq

    local json = util.TableToJSON(payload, false)
    if not json then return end
    local name = string.format("%s%s_%06d.json", OUT_DIR, C.session, C.outSeq)
    atomicWrite(name, json)
end

local function hudTarget(name, sidSuffix)
    C.hud = {
        mode = "TARGET LOCKED",
        line1 = tostring(name),
        line2 = "SteamID64 …" .. tostring(sidSuffix),
        untilTime = CurTime() + CFG.LockTTL,
    }
end

local function hudPreview(action, name, duration, reason, a, b)
    local detail = string.upper(action or "")
    if action == "ban" then detail = detail .. " · " .. tostring(duration) end
    C.hud = {
        mode = "AWAITING CONFIRMATION",
        line1 = detail .. " · " .. tostring(name),
        line2 = reason ~= "" and ("Reason: " .. reason) or "No reason",
        line3 = "Confirm: " .. string.upper(a .. " " .. b),
        untilTime = CurTime() + CFG.RequestTTL,
    }
end

local function hudResult(text)
    C.hud = {
        mode = "VOICEADMIN",
        line1 = tostring(text),
        line2 = "",
        untilTime = CurTime() + 7,
    }
end

local function strictTarget()
    local lp = LocalPlayer()
    if not IsValid(lp) then return end
    local startPos = lp:EyePos()
    local tr = util.TraceLine({
        start = startPos,
        endpos = startPos + lp:GetAimVector() * 32768,
        filter = lp,
        mask = MASK_SHOT,
    })
    if IsValid(tr.Entity) and tr.Entity:IsPlayer() then return tr.Entity end
end

local function requestLock(utterance)
    utterance = VA.SafeId(utterance)
    if not utterance then
        writeOut("error", { message = "Invalid local utterance id." })
        return
    end

    local target = strictTarget()
    if not IsValid(target) then
        writeOut("error", { utterance = utterance, message = "No player is directly under the crosshair." })
        C.queuedProposals[utterance] = nil
        return
    end

    net.Start(VA.Net.LockRequest)
    net.WriteString(utterance)
    net.WriteUInt(target:EntIndex(), 16)
    net.SendToServer()
end

local function durationKind(value)
    value = string.lower(tostring(value or ""))
    if value == "permanent" then return VA.Duration.PERMANENT end
    if value == "temporary" then return VA.Duration.TEMPORARY end
    return VA.Duration.NONE
end

local function actionId(value)
    value = string.lower(tostring(value or ""))
    for id, name in pairs(VA.ActionName) do
        if name == value then return id end
    end
end

local function sendProposal(message, lock)
    local action = actionId(message.action)
    if not action then
        writeOut("error", { message = "Unsupported parsed action." })
        return
    end

    net.Start(VA.Net.Propose)
    net.WriteUInt(lock.id, 32)
    net.WriteUInt(action, 8)
    net.WriteUInt(durationKind(message.duration_kind), 8)
    net.WriteUInt(math.max(0, math.floor(tonumber(message.duration_minutes) or 0)), 32)
    net.WriteString(tostring(message.reason or ""))
    net.SendToServer()
end

local function handleProposal(message)
    local utterance = VA.SafeId(message.utterance)
    if not utterance then
        writeOut("error", { message = "Proposal has no valid utterance id." })
        return
    end
    local lock = C.locks[utterance]
    if not lock then
        C.queuedProposals[utterance] = message
        return
    end
    sendProposal(message, lock)
end

local function handleConfirm(message)
    net.Start(VA.Net.Confirm)
    net.WriteString(tostring(message.request_id or ""))
    net.WriteUInt(math.max(0, math.floor(tonumber(message.revision) or 0)), 16)
    net.WriteString(string.lower(tostring(message.challenge_a or "")))
    net.WriteString(string.lower(tostring(message.challenge_b or "")))
    net.SendToServer()
end

local function handleAmend(message)
    net.Start(VA.Net.Amend)
    net.WriteBool(message.change_duration == true)
    net.WriteUInt(durationKind(message.duration_kind), 8)
    net.WriteUInt(math.max(0, math.floor(tonumber(message.duration_minutes) or 0)), 32)
    net.WriteBool(message.change_reason == true)
    net.WriteString(tostring(message.reason or ""))
    net.SendToServer()
end

local function processMessage(message)
    if not istable(message) or tonumber(message.protocol) ~= VA.PROTOCOL then
        writeOut("error", { message = "Local IPC protocol mismatch." })
        return
    end
    if tostring(message.session or "") ~= C.session then return end

    local kind = tostring(message.type or "")
    if kind == "wake" then
        requestLock(message.utterance)
    elseif kind == "proposal" then
        handleProposal(message)
    elseif kind == "confirm" then
        handleConfirm(message)
    elseif kind == "cancel" then
        net.Start(VA.Net.Cancel)
        net.SendToServer()
    elseif kind == "amend" then
        handleAmend(message)
    end
end

local function activateSession(session)
    C.session = session
    C.outSeq = 0
    C.locks = {}
    C.queuedProposals = {}

    local ackPath = IN_DIR .. "ack_" .. session .. ".txt"
    local last = tonumber(file.Read(ackPath, "DATA") or "0") or 0
    C.expectedSeq = last + 1

    writeOut("hello", {
        version = VA.VERSION,
        protocol_version = VA.PROTOCOL,
    })
end

local function pollIpc()
    local sessionRaw = file.Read(SESSION_FILE, "DATA")
    if not sessionRaw then return end
    local sessionInfo = util.JSONToTable(sessionRaw)
    if not istable(sessionInfo) or tonumber(sessionInfo.protocol) ~= VA.PROTOCOL then return end

    local session = safeSession(sessionInfo.session)
    if not session then return end
    if C.session ~= session then activateSession(session) end

    for _ = 1, CFG.IpcBurst do
        local path = string.format("%s%s_%06d.json", IN_DIR, C.session, C.expectedSeq)
        if not file.Exists(path, "DATA") then break end

        local raw = file.Read(path, "DATA")
        local message = raw and util.JSONToTable(raw) or nil
        if istable(message) then
            local ok, err = pcall(processMessage, message)
            if not ok then writeOut("error", { message = "Client IPC error: " .. tostring(err) }) end
        else
            writeOut("error", { message = "Malformed local IPC message." })
        end

        file.Delete(path)
        file.Write(IN_DIR .. "ack_" .. C.session .. ".txt", tostring(C.expectedSeq))
        C.expectedSeq = C.expectedSeq + 1
    end
end

net.Receive(VA.Net.LockResult, function()
    local ok = net.ReadBool()
    local utterance = net.ReadString()
    if not ok then
        local err = net.ReadString()
        C.queuedProposals[utterance] = nil
        writeOut("error", { utterance = utterance, message = err })
        hudResult(err)
        return
    end

    local lock = {
        id = net.ReadUInt(32),
        name = net.ReadString(),
        suffix = net.ReadString(),
        expiresAt = CurTime() + CFG.LockTTL,
    }
    C.locks[utterance] = lock
    hudTarget(lock.name, lock.suffix)
    writeOut("target_locked", {
        utterance = utterance,
        lock_id = lock.id,
        target_name = lock.name,
        target_suffix = lock.suffix,
    })

    local queued = C.queuedProposals[utterance]
    if queued then
        C.queuedProposals[utterance] = nil
        sendProposal(queued, lock)
    end
end)

net.Receive(VA.Net.Preview, function()
    local data = {
        request_id = net.ReadString(),
        revision = net.ReadUInt(16),
        action = net.ReadString(),
        target_name = net.ReadString(),
        target_suffix = net.ReadString(),
        duration = net.ReadString(),
        reason = net.ReadString(),
        challenge_a = net.ReadString(),
        challenge_b = net.ReadString(),
        prompt = net.ReadString(),
    }
    hudPreview(data.action, data.target_name, data.duration, data.reason, data.challenge_a, data.challenge_b)
    writeOut("preview", data)
end)

net.Receive(VA.Net.Result, function()
    local data = {
        request_id = net.ReadString(),
        code = net.ReadString(),
        message = net.ReadString(),
    }
    hudResult(data.message)
    writeOut("result", data)
end)

timer.Create("VoiceAdmin.IPCPoll", CFG.IpcPollSeconds, 0, pollIpc)

-- The card eases in and out over 0.2 s (RealTime) with an 8 px drop; the last card stays up while it fades out.
local hudBg, hudMode, hudLine2, hudLine3 = Color(10, 13, 18, 225), Color(120, 205, 255), Color(210, 210, 210), Color(255, 205, 100)
local hudShown, hudVis, hudLast = nil, 0, RealTime()
-- Pre-restyle drawing, verbatim from the live A+B file; used when the GoobOS kit is not loaded.
local legacyDraw = function()
    local h = C.hud
    if h and h.untilTime and h.untilTime < CurTime() then C.hud = nil h = nil end
    local rnow = RealTime()
    local dt = math.Clamp(rnow - hudLast, 0, 0.1)
    hudLast = rnow
    if h then hudShown = h end
    hudVis = math.Approach(hudVis, h and 1 or 0, dt / 0.2)
    if hudVis <= 0 or not hudShown then hudShown = nil return end
    h = hudShown
    local ease = hudVis * hudVis * (3 - 2 * hudVis)

    local w, hgt = 430, h.line3 and 112 or 88
    local x, y = math.floor(ScrW() * 0.5 - w * 0.5), math.floor(ScrH() * 0.16 - (1 - ease) * 8)
    surface.SetAlphaMultiplier(ease)
    draw.RoundedBox(8, x, y, w, hgt, hudBg)
    draw.SimpleText(h.mode or "VOICEADMIN", "DermaDefaultBold", x + 16, y + 12, hudMode, TEXT_ALIGN_LEFT)
    draw.SimpleText(h.line1 or "", "DermaDefaultBold", x + 16, y + 36, color_white, TEXT_ALIGN_LEFT)
    draw.SimpleText(h.line2 or "", "DermaDefault", x + 16, y + 58, hudLine2, TEXT_ALIGN_LEFT)
    if h.line3 then
        draw.SimpleText(h.line3, "DermaDefaultBold", x + 16, y + 82, hudLine3, TEXT_ALIGN_LEFT)
    end
    surface.SetAlphaMultiplier(1)
end

hook.Add("HUDPaint", "VoiceAdmin.HUD", function()
    local K = ZCGoobApps and ZCGoobApps.Kit
    local T = ZCGoobApps and ZCGoobApps.Theme
    if not (K and K.HudPlate and T) then return legacyDraw() end
    local h = C.hud
    if h and h.untilTime and h.untilTime < CurTime() then C.hud = nil h = nil end
    local rnow = RealTime()
    local dt = math.Clamp(rnow - hudLast, 0, 0.1)
    hudLast = rnow
    if h then hudShown = h end
    hudVis = math.Approach(hudVis, h and 1 or 0, dt / 0.2)
    if hudVis <= 0 or not hudShown then hudShown = nil return end
    h = hudShown
    local ease = hudVis * hudVis * (3 - 2 * hudVis)

    -- 2026-09-25 HUD pass: GoobOS plate, fonts and tokens; right column, clear of the notification lane and the
    -- announcement band.
    local s = K.HudScale()
    local w, hgt = math.floor(430 * s), math.floor((h.line3 and 112 or 88) * s)
    local x = ScrW() - w - math.floor(24 * s)
    local y = math.floor(ScrH() * 322 / 1080 - (1 - ease) * 8 * s)
    local pad = math.floor(16 * s)
    surface.SetAlphaMultiplier(ease)
    K.HudPlate(x, y, w, hgt)
    draw.SimpleText(string.upper(h.mode or "Voice admin"), K.HudFont(11, 700), x + pad, y + math.floor(12 * s), T.muted, TEXT_ALIGN_LEFT)
    draw.SimpleText(K.Fit(h.line1 or "", K.HudFont(17, 600), w - pad * 2), K.HudFont(17, 600), x + pad, y + math.floor(32 * s), T.text, TEXT_ALIGN_LEFT)
    draw.SimpleText(K.Fit(h.line2 or "", K.HudFont(15, 500), w - pad * 2), K.HudFont(15, 500), x + pad, y + math.floor(56 * s), T.muted, TEXT_ALIGN_LEFT)
    if h.line3 then
        draw.SimpleText(K.Fit(h.line3, K.HudFont(15, 600), w - pad * 2), K.HudFont(15, 600), x + pad, y + math.floor(80 * s), T.gold, TEXT_ALIGN_LEFT)
    end
    surface.SetAlphaMultiplier(1)
end)

concommand.Add("voiceadmin_ipc_status", function()
    print(string.format(
        "[VoiceAdmin] version=%s session=%s expected=%d out=%d",
        VA.VERSION, tostring(C.session), C.expectedSeq, C.outSeq
    ))
end)

function VA.Shutdown(reason)
    timer.Remove("VoiceAdmin.IPCPoll")
    hook.Remove("HUDPaint", "VoiceAdmin.HUD")
end
