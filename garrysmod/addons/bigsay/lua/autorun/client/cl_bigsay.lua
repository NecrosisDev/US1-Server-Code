-- BigSay client: renders the announcement banner.
if not CLIENT then return end

-- 2026-09-25 HUD pass: the face follows hg_font (GoobOS font rule); sizes unchanged.
local function bigsayFace()
	local cv = GetConVar("hg_font")
	local name = cv and cv:GetString() or ""
	return name ~= "" and name or "Bahnschrift"
end

local function bigsayFonts()
surface.CreateFont("BigSay_Main", {
	font = bigsayFace(),
	size = ScreenScale(26),
	weight = 900,
	antialias = true,
})

surface.CreateFont("BigSay_Small", {
	font = bigsayFace(),
	size = ScreenScale(16),
	weight = 800,
	antialias = true,
})
end
bigsayFonts()
cvars.AddChangeCallback("hg_font", bigsayFonts, "BigSay_Fonts")

local active -- { atoms, gif, start, endtime }
local gifPanel
local EMOJI_GAP = 4
local EMOJI_LIMIT = 12
local MAIN_LINES = 2 -- more than this and the message drops to the small font

-- The chat media module owns the emoji materials, the GIF host allowlist and the
-- embed HTML; this file borrows them rather than keeping a second copy. It is
-- included from the chat panel, so its load order relative to this file is not
-- ours to assume: look it up per announcement, and feature-detect instead of
-- pinning its version. Without it, a banner renders exactly as it always has.
local function media()
	local found = ZCChatMedia
	if istable(found) and istable(found.Emojis) and isfunction(found.GIFURL) then return found end
end

local function tidy(text)
	return (text:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Returns the message with the first supported GIF link removed, plus that link.
local function takeGIF(text, found)
	for candidate in text:gmatch("https://[^%s]+") do
		local url = candidate:gsub("[%)%],!;%.]+$", "")
		if found.GIFURL(url) then
			local at = text:find(url, 1, true)
			return tidy(text:sub(1, at - 1) .. text:sub(at + #url)), url
		end
	end
	return text
end

-- Splits the message into words and emoji. An unknown :name: stays literal text,
-- and `space` records whether whitespace preceded the atom in the message, so
-- wrapping can drop the spaces that land at a line break.
local function buildAtoms(text, emojis)
	local atoms, count, pending = {}, 0, false
	local cursor, scan = 1, 1

	local function addText(chunk)
		local index = 1
		while index <= #chunk do
			local first, last = chunk:find("%s+", index)
			if first == index then
				pending = true
				index = last + 1
			else
				local stop = (first or (#chunk + 1)) - 1
				atoms[#atoms + 1] = {text = chunk:sub(index, stop), space = pending}
				pending = false
				index = stop + 1
			end
		end
	end

	while true do
		local first, last, name = text:find(":([%w_]+):", scan)
		if not first then break end
		local emoji = count < EMOJI_LIMIT and emojis and emojis[name]
		if emoji and emoji.material then
			if first > cursor then addText(text:sub(cursor, first - 1)) end
			atoms[#atoms + 1] = {emoji = emoji, space = pending}
			pending = false
			count = count + 1
			cursor, scan = last + 1, last + 1
		else
			scan = first + 1
		end
	end
	if cursor <= #text then addText(text:sub(cursor)) end
	return atoms
end

-- A single run wider than the banner has to break mid-word. Steps whole UTF-8
-- characters so a multi-byte glyph is never cut in half.
local function splitWide(text, maxWidth)
	local chunks, chunk = {}, ""
	local index = 1
	while index <= #text do
		local stop = index
		repeat stop = stop + 1
		until stop > #text or text:byte(stop) < 128 or text:byte(stop) >= 192
		local char = text:sub(index, stop - 1)
		if chunk ~= "" and surface.GetTextSize(chunk .. char) > maxWidth then
			chunks[#chunks + 1] = chunk
			chunk = char
		else
			chunk = chunk .. char
		end
		index = stop
	end
	if chunk ~= "" then chunks[#chunks + 1] = chunk end
	return chunks
end

-- Packs atoms into lines that fit. Adjacent text merges back into one run, so a
-- message with no emoji still draws as a single string per line.
local function layoutLines(atoms, font, maxWidth)
	surface.SetFont(font)
	local _, tall = surface.GetTextSize("Wg")
	local spaceWidth = surface.GetTextSize(" ")
	local lines = {{items = {}, width = 0}}

	local function place(atom)
		local line = lines[#lines]
		local lead = (#line.items > 0 and atom.space) and spaceWidth or 0
		local base = atom.emoji and (tall + EMOJI_GAP) or surface.GetTextSize(atom.text)
		if #line.items > 0 and line.width + lead + base > maxWidth then
			lines[#lines + 1] = {items = {}, width = 0}
			line = lines[#lines]
			lead = 0
		end
		if atom.emoji then
			line.items[#line.items + 1] = {emoji = atom.emoji, lead = lead}
		else
			local piece = lead > 0 and (" " .. atom.text) or atom.text
			local last = line.items[#line.items]
			if last and last.text then last.text = last.text .. piece
			else line.items[#line.items + 1] = {text = piece} end
		end
		line.width = line.width + lead + base
	end

	for _, atom in ipairs(atoms) do
		if atom.text and surface.GetTextSize(atom.text) > maxWidth then
			local chunks = splitWide(atom.text, maxWidth)
			for index, chunk in ipairs(chunks) do
				place({text = chunk, space = index == 1 and atom.space or false})
				if index < #chunks then lines[#lines + 1] = {items = {}, width = 0} end
			end
		else
			place(atom)
		end
	end

	if #lines > 1 and #lines[#lines].items == 0 then lines[#lines] = nil end
	if #lines == 1 and #lines[1].items == 0 then return {}, tall end
	return lines, tall
end

local function clearGIF()
	if IsValid(gifPanel) then gifPanel:Remove() end
	gifPanel = nil
end

local function showGIF(url, found)
	clearGIF()
	if not isfunction(found.HTML) then return end
	local html = found.HTML(url)
	if not html then return end
	local panel = vgui.Create("DHTML")
	if not IsValid(panel) then return end
	gifPanel = panel
	-- Placed every frame in HUDPaint, since its home is inside the band and the
	-- band's height depends on the laid-out message.
	panel:SetAllowLua(false)
	panel:SetMouseInputEnabled(false)
	panel:SetKeyboardInputEnabled(false)
	panel:SetHTML(html)
end

net.Receive("ULXBigSay_Show", function()
	local dur = net.ReadFloat()
	local text = net.ReadString()
	if text == "" then return end

	local found = media()
	local url
	if found then text, url = takeGIF(text, found) end

	local atoms = buildAtoms(text, found and found.Emojis)
	if #atoms == 0 and not url then return end

	active = {
		atoms = atoms,
		gif = url,
		start = CurTime(),
		endtime = CurTime() + dur,
	}
	clearGIF()
	if url then showGIF(url, found) end
	surface.PlaySound("ambient/alarms/warningbell1.wav")
end)

local textColour, labelColour = Color(255, 255, 255, 255), Color(255, 120, 120, 190)

hook.Add("HUDPaint", "BigSay_Draw", function()
	if not active then return end

	local now = CurTime()
	if now > active.endtime then
		active = nil
		clearGIF()
		return
	end

	-- fade in/out
	local alpha = 1
	local sinceStart = now - active.start
	local untilEnd = active.endtime - now
	if sinceStart < 0.35 then alpha = sinceStart / 0.35 end
	if untilEnd < 0.5 then alpha = math.min(alpha, untilEnd / 0.5) end

	local w, h = ScrW(), ScrH()
	local pad = ScreenScale(12)
	local gap = ScreenScale(8)
	local lineGap = ScreenScale(2)
	local maxWidth = w * 0.94

	-- lay the message out, dropping to the small font rather than overflowing; the layout is kept on the
	-- announcement and redone only when the available width changes
	if active.layoutWidth ~= maxWidth then
		local font = "BigSay_Main"
		local lines, tall = layoutLines(active.atoms, font, maxWidth)
		if #lines > MAIN_LINES then
			font = "BigSay_Small"
			lines, tall = layoutLines(active.atoms, font, maxWidth)
		end
		surface.SetFont(font)
		for _, line in ipairs(lines) do
			for _, item in ipairs(line.items) do
				if item.text then item.width = surface.GetTextSize(item.text) end
			end
		end
		active.layoutWidth, active.font, active.lines, active.tall = maxWidth, font, lines, tall
	end
	local font, lines, tall = active.font, active.lines, active.tall

	local lineStep = tall + lineGap
	local textH = #lines > 0 and (#lines * lineStep - lineGap) or 0
	local gifH = (active.gif and IsValid(gifPanel)) and math.floor(h * 0.18) or 0
	local gifW = math.floor(gifH * 16 / 9)
	local contentH = gifH + textH + ((gifH > 0 and textH > 0) and gap or 0)

	-- The band grows to hold the content and stays centred where it has always
	-- been, so a plain one-line announcement is pixel-identical to before.
	local bandH = math.max(h * 0.16, contentH + pad * 2)
	local y = h * 0.32 - bandH * 0.5
	y = math.max(y, ScreenScale(22)) -- never push the red label off the top

	-- backing band, full width: GoobOS glass with a hairline above and below (2026-09-25 HUD pass)
	local T = ZCGoobApps and ZCGoobApps.Theme
	local glass, hair = T and T.glass, T and T.hair
	y, bandH = math.floor(y), math.floor(bandH)
	if glass then surface.SetDrawColor(glass.r, glass.g, glass.b, glass.a * alpha) else surface.SetDrawColor(0, 0, 0, 215 * alpha) end
	surface.DrawRect(0, y, w, bandH)
	if hair then surface.SetDrawColor(hair.r, hair.g, hair.b, hair.a * alpha) else surface.SetDrawColor(200, 40, 40, 90 * alpha) end
	surface.DrawRect(0, y - 1, w, 1)
	surface.DrawRect(0, y + bandH, w, 1)
	if T then
		textColour.r, textColour.g, textColour.b = T.text.r, T.text.g, T.text.b
		labelColour.r, labelColour.g, labelColour.b = T.muted.r, T.muted.g, T.muted.b
	end

	-- the GIF and the text share one block, centred in the band
	local top = y + (bandH - contentH) * 0.5
	if gifH > 0 then
		gifPanel:SetSize(gifW, gifH)
		gifPanel:SetPos(math.floor(w * 0.5 - gifW * 0.5), math.floor(top))
		gifPanel:SetAlpha(255 * alpha)
	end

	local colour = textColour
	colour.a = 255 * alpha
	local lineTop = top + gifH + (gifH > 0 and textH > 0 and gap or 0)
	for index, line in ipairs(lines) do
		local x = w * 0.5 - line.width * 0.5
		local middle = lineTop + (index - 1) * lineStep + tall * 0.5
		for _, item in ipairs(line.items) do
			if item.text then
				draw.SimpleText(item.text, font, x, middle, colour, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				x = x + item.width
			else
				x = x + item.lead
				surface.SetDrawColor(255, 255, 255, 255 * alpha)
				surface.SetMaterial(item.emoji.material)
				surface.DrawTexturedRect(x, middle - tall * 0.5, tall, tall)
				x = x + tall + EMOJI_GAP
			end
		end
	end

	labelColour.a = 190 * alpha
	draw.SimpleText("ANNOUNCEMENT", "BigSay_Small", w / 2, y - ScreenScale(10),
		labelColour, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end)
