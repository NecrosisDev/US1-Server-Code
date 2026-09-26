local info = ZC_HMCD_MUTATOR_INFO
local state = {active = false, generation = 0}
local hud = CreateClientConVar("zc_mutators_hud", "1", true, false, "Show homicide mutator announcements")
local ANNOUNCE_SOUND = "ambient/levels/citadel/strange_talk8.wav"
local function AnnouncementSound()
    if hud:GetBool() then surface.PlaySound(ANNOUNCE_SOUND) end
end
local bannerUntil = 0
local deathUntil, deathTitle, deathGeneration = 0, nil, -1
local letterPulse, invertedLetters = 0, {}
local layout
local TITLE_FONT, BODY_FONT, CAPTION_FONT = "ZC_Mutator_Title", "ZC_Mutator_Body", "ZC_Mutator_Caption"
local function CreateFonts()
    -- Match Fear_Wrath's face/weight/scale, with an enlarged Mutation: heading.
    surface.CreateFont(TITLE_FONT, {font = "Bahnschrift", size = ScreenScale(19), weight = 900, antialias = true})
    surface.CreateFont(BODY_FONT, {font = "Bahnschrift", size = ScreenScale(27), weight = 900, antialias = true})
    surface.CreateFont(CAPTION_FONT, {font = "Bahnschrift", size = ScreenScale(12), weight = 600, antialias = true})
    layout = nil
end
CreateFonts()
hook.Add("OnScreenSizeChanged", "zc_hmcd_mutators_fonts", CreateFonts)
local function Wrap(text, font, width)
    surface.SetFont(font)
    local lines, line = {}, ""
    for word in string.gmatch(text, "%S+") do
        local candidate = line == "" and word or line .. " " .. word
        if line ~= "" and surface.GetTextSize(candidate) > width then
            lines[#lines + 1] = line
            line = word
        else
            line = candidate
        end
    end
    if line ~= "" then lines[#lines + 1] = line end
    return lines
end
net.Receive(info.Net, function()
    local generation = net.ReadUInt(32)
    local active = net.ReadBool()
    local id, title, description = net.ReadString(), net.ReadString(), net.ReadString()
    local midRound = net.ReadString() == "mid_round" -- Existing wire field; never printed to chat.
    if generation < state.generation then return end
    local fresh = active and (not state.active or generation ~= state.generation)
    if generation > state.generation then deathUntil, deathTitle = 0, nil end
    state = {generation = generation, active = active, id = id, title = title, description = description, midRound = midRound}
    layout = nil
    if fresh then
        AnnouncementSound()
        bannerUntil = CurTime() + 7
        letterPulse, invertedLetters = 0, {}
    elseif not active then
        bannerUntil = 0
    end
end)
net.Receive("zc_informant_death", function()
    local generation, choice = net.ReadUInt(32), net.ReadUInt(2)
    local messages = {"The informant has passed", "The informant has died", "The informant has left this plane"}
    if generation < state.generation or generation <= deathGeneration or not messages[choice] then return end
    AnnouncementSound()
    deathGeneration, deathTitle, deathUntil = generation, messages[choice], CurTime() + 7
    layout, letterPulse, invertedLetters = nil, 0, {}
end)
local function Request()
    if not IsValid(LocalPlayer()) then return end
    net.Start(info.Net)
    net.SendToServer()
end
hook.Add("InitPostEntity", "zc_hmcd_mutators_sync", Request)
timer.Simple(1, Request)
local function DrawLine(text, font, x, y, fill, outline)
    -- Fear's eight yellow outline passes; no ghost copies.
    for ox = -2, 2, 2 do
        for oy = -2, 2, 2 do
            if ox ~= 0 or oy ~= 0 then
                draw.SimpleText(text, font, x + ox, y + oy, outline, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        end
    end
    draw.SimpleText(text, font, x, y, fill, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end
local function HeadingLayout(text)
    local chars = {}
    surface.SetFont(BODY_FONT)
    local width = surface.GetTextSize(text)
    for i = 1, #text do
        local prefix = surface.GetTextSize(text:sub(1, i - 1))
        local char = text:sub(i, i)
        chars[i] = {text = char, offset = prefix + surface.GetTextSize(char) / 2 - width / 2}
    end
    return chars
end
local function DrawHeading(x, y, elapsed, fill, outline, stronger)
    local interval, duration = stronger and 0.5 or 0.75, stronger and 0.2 or 0.18
    local pulse = math.floor(elapsed / interval)
    -- Mutation headings glitch for 200ms every half second. Death notices retain
    -- their original timing. Letter choices/offsets stay stable within each burst.
    if pulse < 1 or elapsed % interval >= duration then
        DrawLine(layout.headingText, BODY_FONT, x, y, fill, outline)
        return
    end
    if letterPulse ~= pulse then
        letterPulse, invertedLetters = pulse, {}
        local pool = {}
        for i = 1, #layout.headingText do
            if layout.headingText:sub(i, i):match("%a") then pool[#pool + 1] = i end
        end
        local count = math.random(stronger and math.min(2, #pool) or 1, #pool)
        -- Partial shuffle: unique random letters, sampled once per pulse (not per frame).
        for i = 1, count do
            local pick = math.random(i, #pool)
            pool[i], pool[pick] = pool[pick], pool[i]
            invertedLetters[pool[i]] = true
        end
    end
    for i, char in ipairs(layout.heading) do
        local invert = invertedLetters[i]
        local dx, dy = 0, 0
        if stronger and invert then
            dx = ScreenScale(((i + pulse) % 3 - 1) * 1.8)
            dy = ScreenScale(((i + pulse * 2) % 3 - 1) * 0.75)
        end
        DrawLine(char.text, BODY_FONT, x + char.offset + dx, y + dy,
            invert and outline or fill, invert and fill or outline)
    end
end
hook.Add("HUDPaint", "zc_hmcd_mutators_hud", function()
    local showingDeath = deathUntil > CurTime()
    local left = (showingDeath and deathUntil or bannerUntil) - CurTime()
    if (not state.active and not showingDeath) or not hud:GetBool() or left <= 0 then return end
    local title = showingDeath and deathTitle or state.title
    local heading = not showingDeath and state.midRound and "Mid Round Mutation:" or "Mutation:"
    local caption = not showingDeath and (info.AnnouncementDescriptions or {})[state.id] or ""
    caption = caption or ""
    if not layout or layout.source ~= title or layout.headingText ~= heading or layout.captionText ~= caption then
        layout = {
            source = title,
            captionText = caption,
            caption = Wrap(caption, CAPTION_FONT, ScrW() * 0.88),
            title = Wrap(string.upper(title), TITLE_FONT, ScrW() * 0.88),
            headingText = heading,
            heading = HeadingLayout(heading)
        }
    end
    local alpha = math.min(left / 1.2, 1) * 255
    local fill, outline = Color(190, 0, 0, alpha), Color(255, 230, 0, alpha)
    -- Original Fear timing. Quarter-strength name movement, doubled for the heading.
    local t = CurTime()
    local driftX = math.sin(t * 1.9) * 1.5 + math.sin(t * 3.7) * 0.75
    local driftY = math.cos(t * 1.4) + math.sin(t * 4.3) * 0.5
    local glitching = math.sin(t * 13) > 0.86
    local gx = glitching and math.random(-14, 14) * 0.25 or 0
    local gy = glitching and math.random(-4, 4) * 0.25 or 0
    local x, y = ScrW() / 2 + driftX + gx, ScrH() * 0.34 + driftY + gy
    local hx = ScrW() / 2 + (driftX + gx) * 2 + math.sin(t * 6.1 + 2.4)
    local hy = ScrH() * 0.34 + (driftY + gy) * 2 - ScreenScale(34)
    DrawHeading(hx, hy, 7 - left, fill, outline, not showingDeath)
    for i, text in ipairs(layout.title) do
        DrawLine(text, TITLE_FONT, x + math.sin(t * 6.1 + (i + 1) * 2.4) * 0.5, y, fill, outline)
        y = y + ScreenScale(22)
    end
    -- Keep the short subtitle steady and readable; only heading/name use Fear motion.
    local captionY = ScrH() * 0.34 + ScreenScale(22) * #layout.title + ScreenScale(2)
    for _, text in ipairs(layout.caption) do
        DrawLine(text, CAPTION_FONT, ScrW() / 2, captionY, Color(255, 230, 0, alpha), Color(0, 0, 0, alpha))
        captionY = captionY + ScreenScale(15)
    end
end)
concommand.Add("zc_mutator_info", function()
    if not state.active then print("[zc_mutators] No active mutator.") return end
    print("[zc_mutators] " .. state.title .. ": " .. state.description)
end, nil, "Print the active round mutator and what it does.")
