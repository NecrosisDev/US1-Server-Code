-- Nativized 2026-09-24 from addons/pats_text_presence/lua/autorun/client/cl_pat_textpresence.lua (verbatim; only this
-- header added). Overhead speech text + typing dots. Loaded by lua/autorun/zc_text_presence.lua after the convars.
PATTextPresence = PATTextPresence or {}
PATTextPresence.Active = PATTextPresence.Active or {}
PATTextPresence.SuppressTypingUntil = PATTextPresence.SuppressTypingUntil or {}

local fallbackSpeechColor = Color(245, 245, 245, 255)
local outlineColor = Color(255, 255, 255, 235)
local typingColor = Color(255, 220, 160, 255)
local dotPulseBase = 145
local pixelvis = util.GetPixelVisibleHandle()
local lineHeightCache = {}

surface.CreateFont("PAT_TextPresence_Main", {
    font = "Bahnschrift",
    size = 28,
    weight = 800,
    antialias = true,
    extended = true
})

surface.CreateFont("PAT_TextPresence_Whisper", {
    font = "Bahnschrift",
    size = 22,
    weight = 650,
    italic = true,
    antialias = true,
    extended = true
})

surface.CreateFont("PAT_TextPresence_Typing", {
    font = "Bahnschrift",
    size = 24,
    weight = 900,
    antialias = true,
    extended = true
})

surface.CreateFont("PAT_TextPresence_Main_Mid", {
    font = "Bahnschrift",
    size = 24,
    weight = 800,
    antialias = true,
    extended = true
})

surface.CreateFont("PAT_TextPresence_Main_Far", {
    font = "Bahnschrift",
    size = 20,
    weight = 800,
    antialias = true,
    extended = true
})

surface.CreateFont("PAT_TextPresence_Whisper_Mid", {
    font = "Bahnschrift",
    size = 19,
    weight = 650,
    italic = true,
    antialias = true,
    extended = true
})

surface.CreateFont("PAT_TextPresence_Whisper_Far", {
    font = "Bahnschrift",
    size = 16,
    weight = 650,
    italic = true,
    antialias = true,
    extended = true
})

surface.CreateFont("PAT_TextPresence_Typing_Mid", {
    font = "Bahnschrift",
    size = 20,
    weight = 900,
    antialias = true,
    extended = true
})

surface.CreateFont("PAT_TextPresence_Typing_Far", {
    font = "Bahnschrift",
    size = 17,
    weight = 900,
    antialias = true,
    extended = true
})

local function utf8SubSafe(text, limit)
    limit = math.max(limit or 0, 0)
    if utf8.len(text) == nil then return string.sub(text, 1, limit) end
    return utf8.sub(text, 1, limit)
end

local function clearSpeakerState(ply)
    PATTextPresence.Active[ply] = nil
    PATTextPresence.SuppressTypingUntil[ply] = nil
end

local function isDeadState(ply)
    if not IsValid(ply) then return true end
    if ply:Alive() == false then return true end
    if ply.Health and ply:Health() <= 0 then return true end

    local ragDeath = ply:GetNWEntity("RagdollDeath")
    if IsValid(ragDeath) then
        return true
    end

    return false
end

local function isUnconsciousState(ply)
    if not IsValid(ply) or not ply.GetNWBool then return false end

    if ply:GetNWBool("Unconscious", false) then return true end
    if ply:GetNWBool("unconscious", false) then return true end
    if ply:GetNWBool("KnockedOut", false) then return true end
    if ply:GetNWBool("knockedout", false) then return true end
    if ply:GetNWBool("Otrub", false) then return true end
    if ply:GetNWBool("otrub", false) then return true end
    if ply:GetNWBool("IsUnconscious", false) then return true end
    if ply:GetNWBool("is_unconscious", false) then return true end

    return false
end

local function shouldSuppressPresence(ply)
    return isDeadState(ply) or isUnconsciousState(ply)
end

-- ZCity anchor: hg.GetCurrentCharacter is the correct client-side way
-- to get the visible entity (ragdoll while faked, player while standing).
-- Original fallbacks kept underneath.
local function getSpeakEnt(ply)
    if not IsValid(ply) then return nil end

    if hg and hg.GetCurrentCharacter then
        local ok, char = pcall(hg.GetCurrentCharacter, ply)
        if ok and IsValid(char) then return char end
    end

    if IsValid(ply.FakeRagdoll) then return ply.FakeRagdoll end
    local ragDeath = ply:GetNWEntity("RagdollDeath")
    if IsValid(ragDeath) then return ragDeath end
    return ply
end

-- Keep the original head position logic exactly.
local function getHeadPos(ent)
    if not IsValid(ent) then return nil end

    local bone = ent:LookupBone("ValveBiped.Bip01_Head1")
    if bone then
        local matrix = ent:GetBoneMatrix(bone)
        if matrix then
            return matrix:GetTranslation() + Vector(0, 0, 9)
        end
    end

    return ent:WorldSpaceCenter() + Vector(0, 0, 38)
end

-- Keep the original visibility logic exactly.
local function canSeeSpeaker(ply, targetPos)
    local localPly = LocalPlayer()
    if not IsValid(localPly) then return false end
    if not targetPos then return false end

    local listenerEnt = getSpeakEnt(localPly)
    local viewEnt = GetViewEntity()
    local listenerPos = EyePos()

    local speakerEnt = getSpeakEnt(ply)
    local filter = {localPly, listenerEnt, ply, speakerEnt}
    if IsValid(viewEnt) then
        filter[#filter + 1] = viewEnt
    end
    local samples = {
        targetPos,
        targetPos - Vector(0, 0, 8),
        targetPos - Vector(0, 0, 16)
    }

    for _, sample in ipairs(samples) do
        local px = util.PixelVisible(sample, 3, pixelvis)
        if px and px > 0 then
            local tr = util.TraceLine({
                start = listenerPos,
                endpos = sample,
                mask = MASK_SHOT,
                filter = filter
            })

            if not tr.Hit then
                return true
            end
        end
    end

    return false
end

-- Draw colours are written into scratch objects; each is used by one draw call before it is written again.
local speechScratch, outlineScratch, typingScratch, typingOutlineScratch = Color(255, 255, 255), Color(255, 255, 255), Color(255, 255, 255), Color(255, 255, 255)
local function getSpeechColor(ply, alpha)
    local color = fallbackSpeechColor
    if IsValid(ply) and ply.GetPlayerColor then
        local vec = ply:GetPlayerColor()
        color = vec and vec.ToColor and vec:ToColor() or fallbackSpeechColor
    end
    speechScratch.r, speechScratch.g, speechScratch.b, speechScratch.a = color.r, color.g, color.b, alpha
    return speechScratch
end

local function getDistanceData(distance, isWhisper)
    local scale = isWhisper and PATTextPresence.WhisperDistanceScale:GetFloat() or 1
    local maxDist = PATTextPresence.MaxDistance:GetFloat() * scale
    local fadeDist = math.min(PATTextPresence.FadeDistance:GetFloat() * scale, maxDist)
    return fadeDist, maxDist
end

local function distanceAlpha(distance, isWhisper)
    local fadeDist, maxDist = getDistanceData(distance, isWhisper)

    if distance >= maxDist then return 0 end
    if distance <= fadeDist then return 255 end

    return math.Clamp(255 * (1 - (distance - fadeDist) / math.max(maxDist - fadeDist, 1)), 0, 255)
end

local function getDistanceFraction(distance, isWhisper)
    local fadeDist, maxDist = getDistanceData(distance, isWhisper)
    local startDist = fadeDist * 0.35

    if distance <= startDist then return 0 end
    if distance >= maxDist then return 1 end

    return math.Clamp((distance - startDist) / math.max(maxDist - startDist, 1), 0, 1)
end

local function getSpeechFontForDistance(distance, isWhisper)
    local frac = getDistanceFraction(distance, isWhisper)

    if isWhisper then
        if frac >= 0.72 then return "PAT_TextPresence_Whisper_Far" end
        if frac >= 0.36 then return "PAT_TextPresence_Whisper_Mid" end
        return "PAT_TextPresence_Whisper"
    end

    if frac >= 0.72 then return "PAT_TextPresence_Main_Far" end
    if frac >= 0.36 then return "PAT_TextPresence_Main_Mid" end
    return "PAT_TextPresence_Main"
end

local function getTypingFontForDistance(distance, isWhisper)
    local frac = getDistanceFraction(distance, isWhisper)

    if frac >= 0.72 then return "PAT_TextPresence_Typing_Far" end
    if frac >= 0.36 then return "PAT_TextPresence_Typing_Mid" end
    return "PAT_TextPresence_Typing"
end

local function wrapText(text, font, maxWidth)
    surface.SetFont(font)

    local words = string.Explode(" ", text, false)
    local lines = {}
    local current = ""

    if #words == 0 then
        return {text}
    end

    for _, word in ipairs(words) do
        local candidate = current == "" and word or (current .. " " .. word)
        local width = surface.GetTextSize(candidate)

        if width <= maxWidth or current == "" then
            current = candidate
        else
            lines[#lines + 1] = current
            current = word
        end
    end

    if current ~= "" then
        lines[#lines + 1] = current
    end

    if #lines == 0 then
        lines[1] = text
    end

    return lines
end

-- Wrapped lines and obfuscated text are cached by content; a speech line is measured once, not every frame.
local wrapCache, wrapCount = {}, 0
local function wrapTextCached(text, font, maxWidth)
    local key = font .. "\0" .. maxWidth .. "\0" .. text
    local lines = wrapCache[key]
    if lines then return lines end
    if wrapCount >= 256 then wrapCache, wrapCount = {}, 0 end
    lines = wrapText(text, font, maxWidth)
    wrapCache[key] = lines
    wrapCount = wrapCount + 1
    return lines
end

local function getLineHeight(font)
    local cached = lineHeightCache[font]
    if cached then return cached end

    surface.SetFont(font)
    local _, h = surface.GetTextSize("Ag")
    lineHeightCache[font] = h
    return h
end

local function shiftCurrentToPrevious(slot, now)
    if not slot.current or not slot.current.text or slot.current.text == "" then return end

    slot.previous = {
        text = slot.current.text,
        whisper = slot.current.whisper,
        expiresAt = now + PATTextPresence.PreviousLifeTime:GetFloat()
    }
end

local function addSpeech(ply, text, isWhisper)
    if not IsValid(ply) or not isstring(text) or text == "" then return end
    if shouldSuppressPresence(ply) then
        clearSpeakerState(ply)
        return
    end

    local now = CurTime()
    local charCount = math.max(utf8.len(text) or #text, 1)
    local revealDuration = math.Clamp(charCount / PATTextPresence.RevealSpeed:GetFloat(), 0.22, 3.8)
    local slot = PATTextPresence.Active[ply] or {}

    shiftCurrentToPrevious(slot, now)

    slot.current = {
        text = text,
        whisper = isWhisper,
        startedAt = now,
        revealAt = now + revealDuration,
        expiresAt = now + revealDuration + PATTextPresence.LifeTime:GetFloat(),
        chars = charCount
    }

    PATTextPresence.Active[ply] = slot
    PATTextPresence.SuppressTypingUntil[ply] = now + 0.35
end

-- Keep the original permissive capture path that worked.
-- ZCity: ZChat never fires OnPlayerChat, so speech arrives via the
-- server relay (sv_pat_textpresence_bridge.lua) instead.
net.Receive("PAT_TextPresence_Speech", function()
    local ply = net.ReadEntity()
    local text = net.ReadString()
    local bWhisper = net.ReadBool()

    if not IsValid(ply) or not isstring(text) or text == "" then return end
    addSpeech(ply, text, bWhisper)
end)

-- keep the stock hook too, harmless if it never fires; guarded against
-- double-display if some future chat build forwards it
hook.Add("OnPlayerChat", "PAT_TextPresence_Capture", function(ply, text, bTeam, bDead, bWhisper)
    if not IsValid(ply) or bTeam then return end
    local slot = PATTextPresence.Active[ply]
    if slot and slot.current and slot.current.text == text then return end
    addSpeech(ply, text, bWhisper)
end)

local function getRevealText(state, now)
    if now >= state.revealAt then
        return state.text, true
    end

    local frac = math.TimeFraction(state.startedAt, state.revealAt, now)
    local shown = math.max(math.floor(state.chars * frac), 1)
    return utf8SubSafe(state.text, shown), false
end

local function getCurrentLineFade(lineAge, totalLines, fadeProgress)
    if lineAge <= 0 then return 1 end

    local vanishAt = math.Clamp(1 - (lineAge / totalLines), 0.15, 0.9)
    local softness = 0.16
    return math.Clamp((vanishAt - fadeProgress) / softness, 0, 1)
end

local function getTextHash(text)
    local hash = 0
    local sampleLen = math.min(#text, 32)

    for i = 1, sampleLen do
        hash = (hash + (string.byte(text, i) or 0) * i) % 997
    end

    return hash
end

local function getObfuscationStrength(distance, isWhisper)
    local fadeDist, maxDist = getDistanceData(distance, isWhisper)
    local startDist = fadeDist * 0.72

    if distance <= startDist then return 0 end
    if distance >= maxDist then return 1 end

    return math.Clamp((distance - startDist) / math.max(maxDist - startDist, 1), 0, 1)
end

local obfuscateRaw
local obfuscateCache, obfuscateCount = {}, 0
local function obfuscateTextAtDistance(text, distance, isWhisper)
    local strength = getObfuscationStrength(distance, isWhisper)
    if strength <= 0 then return text end
    local threshold = math.floor(strength * 100)
    local key = threshold .. "\0" .. text
    local cached = obfuscateCache[key]
    if cached then return cached end
    if obfuscateCount >= 256 then obfuscateCache, obfuscateCount = {}, 0 end
    cached = obfuscateRaw(text, threshold)
    obfuscateCache[key] = cached
    obfuscateCount = obfuscateCount + 1
    return cached
end

function obfuscateRaw(text, threshold)
    local len = utf8.len(text)
    if not len or len <= 0 then return text end

    local textHash = getTextHash(text)
    local out = {}

    for i = 1, len do
        local ch = utf8.sub(text, i, i)

        if ch == " " or ch == "\t" then
            out[#out + 1] = ch
        else
            local hash = ((i * 17) + textHash) % 100
            if hash < threshold then
                out[#out + 1] = "•"
            else
                out[#out + 1] = ch
            end
        end
    end

    return table.concat(out)
end

local function drawSpeechStack(ply, screenPos, text, alpha, isWhisper, yOffset, historyScale, fadeProgress, progressiveFade, viewDistance)
    local font = getSpeechFontForDistance(viewDistance or 0, isWhisper)
    local maxWidth = PATTextPresence.WrapWidth:GetFloat() * (isWhisper and 0.85 or 1)
    local lines = wrapTextCached(text, font, maxWidth)
    local lineHeight = getLineHeight(font)
    local gap = 2
    local totalHeight = #lines * lineHeight + (#lines - 1) * gap
    local currentY = screenPos.y + yOffset

    for index = #lines, 1, -1 do
        local lineAge = (#lines - index)
        local lineFade = progressiveFade and getCurrentLineFade(lineAge, #lines, fadeProgress or 0) or 1
        local lineScale = lineAge == 0 and 1 or math.max(0.16, 0.58 - lineAge * 0.18)
        local finalAlpha = math.floor(alpha * historyScale * lineScale * lineFade)

        if finalAlpha > 0 then
            local fillAlpha = math.Clamp(math.floor(finalAlpha * 1.55), 0, 255)
            local outlineAlpha = math.Clamp(math.floor(finalAlpha * 0.14), 0, 255)
            local color = getSpeechColor(ply, math.floor(fillAlpha * (isWhisper and 0.9 or 1)))
            local K = ZCGoobApps and ZCGoobApps.Kit
            if K and K.HudText then -- 2026-09-25 HUD pass: shared 1 px shadow
                K.HudText(lines[index], font, screenPos.x, currentY, color, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
            else
                local outline = outlineScratch
                outline.r, outline.g, outline.b, outline.a = outlineColor.r, outlineColor.g, outlineColor.b, outlineAlpha
                draw.SimpleTextOutlined(lines[index], font, screenPos.x, currentY, color, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, outline)
            end
        end

        currentY = currentY - lineHeight - gap
    end

    return totalHeight
end

local function drawTyping(x, y, alpha, viewDistance, isWhisper)
    local phase = CurTime() * 5
    local dots = "."
    if phase % 3 > 1 then dots = ".." end
    if phase % 3 > 2 then dots = "..." end

    local font = getTypingFontForDistance(viewDistance or 0, isWhisper)
    typingScratch.r, typingScratch.g, typingScratch.b = typingColor.r, typingColor.g, typingColor.b
    typingScratch.a = math.floor(alpha * (dotPulseBase + math.abs(math.sin(phase)) * 110) / 255)
    typingOutlineScratch.a = math.floor(alpha * 0.8)

    local K = ZCGoobApps and ZCGoobApps.Kit
    local T = ZCGoobApps and ZCGoobApps.Theme
    if K and K.HudText and T then -- 2026-09-25 HUD pass: muted dots, shared 1 px shadow
        typingScratch.r, typingScratch.g, typingScratch.b = T.muted.r, T.muted.g, T.muted.b
        K.HudText(dots, font, x, y - PATTextPresence.TypingOffset:GetFloat(), typingScratch, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        return
    end
    draw.SimpleTextOutlined(dots, font, x, y - PATTextPresence.TypingOffset:GetFloat(), typingScratch,
        TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, typingOutlineScratch)
end

-- Per-player draw state: eased visibility and typing-dot alpha (0..1, 0.15 s, RealTime), and the next occlusion
-- check. The occlusion test (up to 3 PixelVisible + 3 traces) runs at 10 Hz per player; the easing hides the step,
-- so a speaker walking behind cover fades out instead of popping.
local FADE_TIME = 0.15
local VIS_INTERVAL = 0.1
local fxState = setmetatable({}, {__mode = "k"})
local fxFrame, lastReal = 0, RealTime()

local function ease(t) return t * t * (3 - 2 * t) end

local function speakerFx(ply)
    local fx = fxState[ply]
    if not fx then
        fx = {vis = 0, typing = 0, nextCheck = 0, visible = false, frame = -1}
        fxState[ply] = fx
    end
    return fx
end

local function speakerVisibility(fx, ply, pos, rnow, dt)
    if fx.frame ~= fxFrame then
        fx.frame = fxFrame
        if rnow >= fx.nextCheck then
            fx.visible = canSeeSpeaker(ply, pos)
            fx.nextCheck = rnow + VIS_INTERVAL
        end
        fx.vis = math.Approach(fx.vis, fx.visible and 1 or 0, dt / FADE_TIME)
    end
    return ease(fx.vis)
end

hook.Add("HUDPaint", "PAT_TextPresence_Draw", function()
    local localPly = LocalPlayer()
    if not IsValid(localPly) then return end

    local now = CurTime()
    local rnow = RealTime()
    local dt = math.Clamp(rnow - lastReal, 0, 0.1)
    lastReal = rnow
    fxFrame = fxFrame + 1

    for ply, slot in pairs(PATTextPresence.Active) do
        if not IsValid(ply) or shouldSuppressPresence(ply) then
            clearSpeakerState(ply)
            continue
        end

        local current = slot.current
        local previous = slot.previous

        if current and now >= current.expiresAt then
            slot.current = nil
            current = nil
        end

        if previous and now >= previous.expiresAt then
            slot.previous = nil
            previous = nil
        end

        if not current and not previous then
            clearSpeakerState(ply)
            continue
        end

        local ent = getSpeakEnt(ply)
        local pos = getHeadPos(ent)
        if not pos then continue end
        local vis = speakerVisibility(speakerFx(ply), ply, pos, rnow, dt)
        if vis <= 0 then continue end

        local screenPos = pos:ToScreen()
        if not screenPos.visible then continue end

        local stackedHeight = 0
        local viewDistance = EyePos():Distance(pos)

        if current then
            local currentText = getRevealText(current, now)
            currentText = obfuscateTextAtDistance(currentText, viewDistance, current.whisper)

            local alpha = distanceAlpha(viewDistance, current.whisper)
            local fade = math.Clamp((current.expiresAt - now) / 0.45, 0, 1)
            alpha = math.floor(alpha * math.min(fade, 1) * vis)

            if alpha > 0 then
                local lineFadeProgress = math.TimeFraction(current.revealAt, current.expiresAt, now)
                stackedHeight = drawSpeechStack(ply, screenPos, currentText, alpha, current.whisper, current.whisper and 6 or 0, 1, lineFadeProgress, true, viewDistance)
            end
        end

        if previous then
            local previousText = obfuscateTextAtDistance(previous.text, viewDistance, previous.whisper)

            local alpha = distanceAlpha(viewDistance, previous.whisper)
            local fade = math.Clamp((previous.expiresAt - now) / 0.5, 0, 1)
            alpha = math.floor(alpha * 0.55 * fade * vis)

            if alpha > 0 then
                drawSpeechStack(ply, screenPos, previousText, alpha, previous.whisper, -(stackedHeight + 8), 0.65, 0, false, viewDistance)
            end
        end
    end

    -- Typing dots. Players who are not typing and have no dots fading out are skipped before the state lookups.
    for _, ply in player.Iterator() do
        if not IsValid(ply) then continue end
        local fx = fxState[ply]
        local typing = ply:IsTyping()
        if not typing and not (fx and fx.typing > 0) then continue end
        if shouldSuppressPresence(ply) then
            clearSpeakerState(ply)
            if fx then fx.typing = 0 end
            continue
        end
        fx = fx or speakerFx(ply)
        local slot = PATTextPresence.Active[ply]
        local want = typing and (PATTextPresence.SuppressTypingUntil[ply] or 0) <= now and not (slot and slot.current)
        fx.typing = math.Approach(fx.typing, want and 1 or 0, dt / FADE_TIME)
        if fx.typing <= 0 then continue end

        local ent = getSpeakEnt(ply)
        local pos = getHeadPos(ent)
        if not pos then continue end
        local vis = speakerVisibility(fx, ply, pos, rnow, dt)
        if vis <= 0 then continue end

        local viewDistance = EyePos():Distance(pos)
        local alpha = distanceAlpha(viewDistance, ply.ChatWhisper)
        if alpha <= 0 then continue end

        local screenPos = pos:ToScreen()
        if not screenPos.visible then continue end

        drawTyping(screenPos.x, screenPos.y - 18, math.floor(alpha * 0.9 * vis * ease(fx.typing)), viewDistance, ply.ChatWhisper)
    end
end)
