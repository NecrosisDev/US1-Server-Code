if not ZCChatMedia or ZCChatMedia.Version ~= "20260922.2" then
	if file.Exists("zc_chat_media/client.lua", "LUA") then
		local ok, err = pcall(include, "zc_chat_media/client.lua")
		if not ok then ErrorNoHalt("[zc_chat_media] " .. tostring(err) .. "\n") end
	end
end
if not ZCChatMedia or ZCChatMedia.Version ~= "20260922.2" then
	-- This client has not been sent the media module: it joined before the module
	-- was installed, or the module failed to load. Chat keeps working as stock
	-- chat, and picks the module up on the next connect.
	ZCChatMedia = {
		Version = "absent",
		Layout = function() end,
		InstallButton = function() end,
		ClosePicker = function() end,
		Attach = function() end,
		DisplayElements = function(elements) return elements end,
		Format = function(text) return (tostring(text):gsub("<", "&lt;"):gsub(">", "&gt;")) end,
	}
end
--made by mrrp :3

local maxLength = GetConVar("zchat_maxmessagelength")

local NoDrop = CreateClientConVar("zchat_dropcharacters", 1, true, false, "Play the character dropping animation when erasing text", 0, 1)
local ShowTextBoxInactive = CreateClientConVar("zchat_showtextboxinactive", 1, true, false, "Showing your text in textbox while chat is turned off", 0, 1)

-- One palette for the whole chatbox. The old look inherited its colours from
-- three unrelated places: a red gradient wash on the frame, a brown rect behind
-- the entry, and white-on-black hint text. These are deliberate, and they are
-- the only colours drawn here.
local ZC_ACCENT = Color(67, 165, 255)
local ZC_PANEL = Color(16, 18, 23, 214)
local ZC_RULE = Color(255, 255, 255, 18)
local ZC_ENTRY = Color(26, 29, 35)
local ZC_HINT = Color(150, 156, 168)
local ZC_SHADOW = Color(0, 0, 0, 200)

local function ChatKeyLabel()
	local key = input.LookupBinding("messagemode") or input.LookupBinding("messagemode2") or "KEY"
	key = string.upper(key):gsub("MOUSE", "M"):gsub("KP_", "KP")
	return #key > 4 and key:sub(1, 4) or key
end

local function PaintWhisperIcon(x, y, alpha)
	draw.RoundedBox(8, x, y, 16, 16, Color(110, 183, 255, alpha))
	surface.SetDrawColor(18, 34, 58, alpha)
	surface.DrawRect(x + 3, y + 6, 3, 4)
	surface.DrawPoly({
		{x = x + 6, y = y + 6}, {x = x + 10, y = y + 3},
		{x = x + 10, y = y + 13}, {x = x + 6, y = y + 10},
	})
	surface.DrawLine(x + 12, y + 6, x + 13, y + 8)
	surface.DrawLine(x + 13, y + 8, x + 12, y + 10)
end

local function WrapSystemBannerText(message, maxWidth, maxLines)
	maxLines = maxLines or 4
	surface.SetFont("DermaDefaultBold")
	local lines, current = {}, ""
	for word in tostring(message):gsub("[\r\n]", " "):gmatch("%S+") do
		local candidate = current == "" and word or (current .. " " .. word)
		local width = surface.GetTextSize(candidate)
		if current ~= "" and width > maxWidth then
			lines[#lines + 1] = current
			current = word
		else
			current = candidate
		end
	end
	if current ~= "" then lines[#lines + 1] = current end
	if #lines == 0 then lines[1] = "" end
	if #lines > maxLines then
		while #lines > maxLines do table.remove(lines) end
		local ellipsis = lines[maxLines] .. "…"
		if surface.GetTextSize(ellipsis) <= maxWidth then lines[maxLines] = ellipsis end
	end
	return lines
end

local function CallbackBind(self, callback)
	return function(_, ...)
		return callback(self, ...)
	end
end

local function PaintMarkupOverride(text, font, x, y, color, alignX, alignY, alpha)
	alpha = alpha or 255

	-- background for easier reading
	surface.SetTextPos(x + 1, y + 1)
	surface.SetTextColor(0, 0, 0, alpha)
	surface.SetFont(font)
	surface.DrawText(text)

	surface.SetTextPos(x, y)
	surface.SetTextColor(color.r, color.g, color.b, alpha)
	surface.SetFont(font)
	surface.DrawText(text)
end

local PANEL = {}

function PANEL:Init()
	self.text = ""
	self.alpha = 0
	self.fadeDelay = 4
	self.fadeDuration = 0.6
	self.yAnimDuration = 1

	self.yAnim = 5
end

function PANEL:SetMarkup(text)
	self.text = text
	self.ZCTypewriterStart = CurTime()
	self:BuildMarkup(self:GetWide())

	self:SetTall(self.ZCBaseHeight)
	ZCChatMedia.Layout(self)

	timer.Simple(self.fadeDelay, function()
		if (!IsValid(self)) then return end
		self:CreateAnimation(self.fadeDuration, {
			index = 3,
			target = {alpha = 0}
		})
	end)

	self:CreateAnimation(self.yAnimDuration, {
		index = 4,
		target = {yAnim = 0},
		easing = "outQuint"
	})

	self:CreateAnimation(0.5, {
		index = 3,
		target = {alpha = 255},
	})
end

function PANEL:BuildMarkup(width)
	local bubbleMax = self.ZCBubble and math.min(width * 0.72, 560) or width
	local textWidth = math.max(1, bubbleMax - (self.ZCLeftInset or 0) - (self.ZCBubble and 12 or 0))
	self.markup = hg.markup.Parse(self.text, textWidth)
	if self.ZCBubble then
		self.ZCBubbleWidth = math.min(bubbleMax, self.markup:GetWidth() + (self.ZCLeftInset or 0) + 12)
		self.ZCBubbleX = self.ZCOwn and math.max(0, width - self.ZCBubbleWidth - 4) or 0
		self.ZCTextX = self.ZCBubbleX + (self.ZCLeftInset or 0) + 4
		self.ZCBubbleBodyHeight = math.max(42, self.markup:GetHeight() + 8)
		self.ZCBaseHeight = self.ZCBubbleBodyHeight + (self.ZCReactionsVisible and 20 or 0)
		if IsValid(self.ZCAvatar) then
			self.ZCAvatar:SetPos(self.ZCBubbleX + 4, 4)
		end
	else
		self.ZCTextX = self.ZCLeftInset or 0
		self.ZCBaseHeight = self.markup:GetHeight()
	end
	local count = 0
	for _, block in ipairs(self.markup.blocks) do
		if block.text then
			block.ZCRevealBefore = count
			count = count + string.utf8len(block.text)
		end
	end
	self.ZCTypewriterRate = math.max(45, count / 1.5)
	self.markup.onDrawText = function(text, font, x, y, color, alignX, alignY, alpha, block)
		local shown = math.floor((CurTime() - self.ZCTypewriterStart) * self.ZCTypewriterRate)
		local available = shown - block.ZCRevealBefore
		if available <= 0 then return end
		if available < string.utf8len(text) then text = string.utf8sub(text, 1, available) end
		PaintMarkupOverride(text, font, x, y, color, alignX, alignY, alpha)
	end
end

function PANEL:PerformLayout(width, height)
	self:BuildMarkup(width)

	self:SetTall(self.ZCBaseHeight)
	ZCChatMedia.Layout(self)
end

function PANEL:Paint(width, height)
	local newAlpha

	if (hg.chat:GetActive()) then
		if self.ZCOpenedAt and self.ZCOpenedAt == hg.chat.openTime then
			local elapsed = CurTime() - self.ZCOpenedAt
			newAlpha = 255 * math.Clamp((elapsed - self.ZCOpenOrder * 0.20) / 0.05, 0, 1)
		else
			newAlpha = math.max(hg.chat.alpha, self.alpha)
		end
	elseif self.ZCClosedAt and self.ZCClosedAt == hg.chat.closeTime then
		-- Closing the editor is immediate; its existing lines leave in order.
		local elapsed = CurTime() - self.ZCClosedAt
		local start = self.ZCCloseOrder * 0.20
		newAlpha = 255 * (1 - math.Clamp((elapsed - start) / 0.05, 0, 1))
	else
		newAlpha = self.alpha - (255 - hg.chat.realAlpha)
	end

	DisableClipping(true)
		local clipX, clipY = hg.chat.history:LocalToScreen(0, 0)
		local clipW, clipH = hg.chat.history:GetSize()

		render.SetScissorRect(clipX, clipY, clipX + clipW, clipY + clipH, true)
			if self.ZCBubble then
				local bubbleAlpha = math.Clamp(newAlpha * 0.58, 0, 255)
				local shade = self.ZCOwn and Color(44, 116, 220, bubbleAlpha)
					or (self.ZCBot and Color(95, 80, 132, bubbleAlpha)
					or Color(73, 92, 119, bubbleAlpha))
				draw.RoundedBox(10, self.ZCBubbleX, 0, self.ZCBubbleWidth, self.ZCBubbleBodyHeight, shade)
			end
			self.markup:draw(self.ZCTextX, self.yAnim + (self.ZCBubble and 4 or 0), nil, nil, newAlpha)
		render.SetScissorRect(0, 0, 0, 0, false)
	DisableClipping(false)
	if IsValid(self.ZCAvatar) then self.ZCAvatar:SetAlpha(math.Clamp(newAlpha, 0, 255)) end
end

vgui.Register("zChatMessage", PANEL, "Panel")

PANEL = {}

DEFINE_BASECLASS("DTextEntry")

function PANEL:Init()
	self:SetFont("zChatFont")
	self:SetUpdateOnType(true)
	self:SetHistoryEnabled(true)

	self.History = hg.chat.messageHistory
	self.droppedCharacters = {}

	self.prevText = ""

	self:SetTextColor(color_white)

	self:SetPaintBackground(false)

	self.m_bLoseFocusOnClickAway = false
end

function PANEL:AllowInput(newCharacter)
	local text = self:GetText()
	local maxLen = maxLength:GetInt()

	-- we can't check for the proper length using utf-8 since AllowInput is called for single bytes instead of full characters
	if (string.len(text .. newCharacter) > maxLen) then
		surface.PlaySound("common/talk.wav")
		return true
	end
end

function PANEL:Think()
	local text = self:GetText()
	local maxLen = maxLength:GetInt()

	if (text:utf8len() > maxLen) then
		local newText = text:utf8sub(0, maxLen)

		self:SetText(newText)
		self:SetCaretPos(newText:utf8len())
	end
end

function PANEL:Paint(w, h)
	for k, v in ipairs(self.droppedCharacters) do
		local text = v.text

		v.velocityY = v.velocityY + (5 * FrameTime())
		v.y = v.y + v.velocityY

		v.x = v.x + v.velocityX

		v.alpha = v.alpha - FrameTime() * 750

		DisableClipping(true)
			surface.SetTextColor(ZC_HINT.r, ZC_HINT.g, ZC_HINT.b, v.alpha)
			surface.SetTextPos(v.x, v.y)
			surface.SetFont("zChatFont")
			surface.DrawText(text)
		DisableClipping(false)

		if v.alpha <= 0 then
			table.remove(self.droppedCharacters, k)
		end
	end

	if ShowTextBoxInactive:GetBool() and !hg.chat:GetActive() and self.prevText != "" then
		DisableClipping(true)
		surface.SetAlphaMultiplier(1)
			surface.SetTextColor(ZC_HINT.r, ZC_HINT.g, ZC_HINT.b, 70)
			surface.SetTextPos(0, 0)
			surface.SetFont("zChatFont")
			surface.DrawText(self.prevText)
		surface.SetAlphaMultiplier(0)
		DisableClipping(false)
	end

	BaseClass.Paint(self, w, h)
end

function PANEL:OnValueChange(text)
	local prevText = self.prevText

	if NoDrop:GetBool() then
		local len1, len2 = string.utf8len(prevText), string.utf8len(text)

		if len1 > len2 then
			local droppedText = string.utf8sub(prevText, self:GetCaretPos() + 1, self:GetCaretPos() + (len1 - len2))

			local droppedChars = string.Explode(utf8.charpattern, droppedText)
			for k, v in ipairs(droppedChars) do
				local data = {}
				data.text = v

				surface.SetFont("zChatFont")
				-- local tw1 = surface.GetTextSize(text)
				local tw2 = surface.GetTextSize(v)

				data.x = tw2 * (self:GetCaretPos())

				-- local panelWide = self:GetWide()

				-- if data.x > panelWide then
				-- 	data.x = data.x - (data.x - panelWide)
				-- end

				data.y = 8

				data.velocityX = math.Rand(-0.1, 0.1)
				data.velocityY = -1

				data.alpha = 255

				table.insert(self.droppedCharacters, data)
			end
		end
	end

	self.prevText = text
end

vgui.Register("zChatboxEntry", PANEL, "DTextEntry")

PANEL = {}

AccessorFunc(PANEL, "bActive", "Active", FORCE_BOOL)
AccessorFunc(PANEL, "realAlpha", "RealAlpha", FORCE_BOOL)

function PANEL:Init()
	hg.chat = self

	self.entries = {}
	self.messageHistory = {}

	self.alpha = 255
	self.realAlpha = 255
	self.frameAlpha = 0
	self.fadeStart = CurTime()
	self.fadeFrom = 0
	self.fadeTo = 0

	local x = 48
	local width = math.Clamp(cookie.GetNumber("zchat_width", ScrW() * 0.42), 320, ScrW() - x - 16)
	local height = math.Clamp(cookie.GetNumber("zchat_height", ScrH() * 0.4), 180, ScrH() * 0.65)
	self:SetSize(width, height)
	self:SetPos(x, ScrH() - 48 - height)

	self.resizeHandle = self:Add("DPanel")
	self.resizeHandle:SetSize(28, 28)
	self.resizeHandle:SetPos(self:GetWide() - 28, 0)
	self.resizeHandle:SetMouseInputEnabled(true)
	self.resizeHandle:SetCursor("sizenesw")
	self.resizeHandle.Paint = function(_, w, h)
		surface.SetDrawColor(ZC_ENTRY.r, ZC_ENTRY.g, ZC_ENTRY.b, 245)
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(ZC_ACCENT.r, ZC_ACCENT.g, ZC_ACCENT.b, 255)
		surface.DrawLine(6, 21, 21, 6)
		surface.DrawLine(12, 21, 21, 12)
		surface.DrawLine(16, 6, 21, 6)
		surface.DrawLine(21, 6, 21, 11)
	end
	self.resizeHandle.OnMousePressed = function(handle, button)
		if button != MOUSE_LEFT or not self:GetActive() then return end
		local px, py = self:GetPos()
		self.resizeBottom = py + self:GetTall()
		self.resizing = true
		handle:MouseCapture(true)
	end
	self.resizeHandle.OnMouseReleased = function(handle, button)
		if button != MOUSE_LEFT then return end
		handle:MouseCapture(false)
		if not self.resizing then return end
		self.resizing = false
		cookie.Set("zchat_width", math.floor(self:GetWide()))
		cookie.Set("zchat_height", math.floor(self:GetTall()))
	end
	self.resizeHandle.Think = function(handle)
		if not self.resizing then return end
		if not input.IsMouseDown(MOUSE_LEFT) then handle:OnMouseReleased(MOUSE_LEFT) return end
		local mx, my = gui.MousePos()
		local x = self:GetX()
		local width = math.Clamp(mx - x + 14, 320, ScrW() - x - 16)
		local height = math.Clamp(self.resizeBottom - my + 14, 180, ScrH() * 0.65)
		self:SetSize(width, height)
		self:SetY(self.resizeBottom - height)
		handle:SetPos(width - 28, 0)
	end

	self.bannerMuted = cookie.GetNumber("zchat_mute_banners", 0) == 1
	self.bannerNotices = {}
	self.bannerMuteButton = self:Add("DButton")
	self.bannerMuteButton:SetPos(4, 4)
	self.bannerMuteButton:SetSize(24, 24)
	self.bannerMuteButton:SetText("")
	self.bannerMuteButton:SetTooltip("Mute system banners")
	self.bannerMuteButton.Paint = function(button, w, h)
		local alpha = self:GetActive() and 220 or 80
		draw.RoundedBox(6, 0, 0, w, h, Color(38, 45, 56, alpha))
		draw.SimpleText("!", "DermaDefaultBold", w / 2, h / 2,
			Color(220, 229, 240, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		if self.bannerMuted then
			surface.SetDrawColor(255, 105, 105, alpha)
			surface.DrawLine(5, 19, 19, 5)
		end
	end
	self.bannerMuteButton.DoClick = function()
		self.bannerMuted = not self.bannerMuted
		cookie.Set("zchat_mute_banners", self.bannerMuted and "1" or "0")
		self.bannerMuteButton:SetTooltip(self.bannerMuted and "Unmute system banners" or "Mute system banners")
		if self.bannerMuted then
			for _, notice in ipairs(self.bannerNotices) do if IsValid(notice) then notice:Remove() end end
			self.bannerNotices = {}
		end
	end

	self.entrySlot = self:Add("Panel")
	self.entrySlot:SetZPos(1)
	self.entrySlot:Dock(BOTTOM)
	self.entrySlot:SetTall(40)
	self.entrySlot:DockMargin(0, 0, 6, 5)
	self.keyOrb = vgui.Create("DPanel")
	self.keyOrb:SetSize(40, 40)
	self.keyOrb:SetPos(48, ScrH() - 88)
	self.keyOrb:SetMouseInputEnabled(false)
	self.keyOrb.Paint = function(_, w, h)
		draw.RoundedBox(20, 0, 0, w, h, Color(44, 116, 220, 230))
		draw.SimpleText(ChatKeyLabel(), "DermaDefaultBold", w / 2, h / 2,
			color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	self.entryPanel = self.entrySlot:Add("Panel")
	self.entryPanel:SetSize(math.max(1, self:GetWide() - 96), 40)
	self.entryPanel.Paint = function(panel, w, h)
		local focused = IsValid(self.entry) and self.entry:HasFocus()
		draw.RoundedBox(18, 0, 0, w, h, focused and ZC_ACCENT or Color(67, 74, 86, 230))
		draw.RoundedBox(17, 1, 1, w - 2, h - 2, Color(ZC_ENTRY.r, ZC_ENTRY.g, ZC_ENTRY.b, 245))
	end

	self.entry = self.entryPanel:Add("zChatboxEntry")
	self.entry:Dock(FILL)
	self.entry:DockMargin(12, 5, 4, 5)
	self.entry:SetPlaceholderText("Message")
	-- self.entry.OnValueChange = ix.util.Bind(self, self.OnTextChanged)
	-- self.entry.OnKeyCodeTyped = ix.util.Bind(self, self.OnKeyCodeTyped)
	self.entry.OnEnter = CallbackBind(self, self.OnMessageSent)
	ZCChatMedia.InstallButton(self)

	self.history = self:Add("DScrollPanel")
	self.history:Dock(FILL)
	self.history:DockMargin(4, 2, 4, 12)
	self.historySpacer = self.history:GetCanvas():Add("Panel")
	self.historySpacer:Dock(TOP)
	self.historySpacer:SetTall(0)
	self.resizeHandle:MoveToFront()

	self:SetActive(false)
end

function PANEL:PerformLayout(w, h)
	if IsValid(self.resizeHandle) then
		self.resizeHandle:SetPos(w - 28, 0)
		self.resizeHandle:MoveToFront()
	end
	if IsValid(self.bannerMuteButton) then self.bannerMuteButton:MoveToFront() end
end

function PANEL:LayoutSystemBanners()
	if not IsValid(self.bannerMuteButton) or not IsValid(self.entrySlot) or not IsValid(self.keyOrb) then return end
	local orbX, orbY = self.keyOrb:LocalToScreen(0, 0)
	local panelX, panelY = self:LocalToScreen(0, 0)
	if self:GetActive() then
		self.bannerMuteButton:SetVisible(true)
		self.bannerMuteButton:SetPos(4, 4)
	else
		self.bannerMuteButton:SetVisible(false)
	end
	local openY = panelY + 4
	local closedX = orbX + self.keyOrb:GetWide() + 6
	local closedHeight = 0
	local lastHeight = 0
	for i, notice in ipairs(self.bannerNotices or {}) do
		if IsValid(notice) then
			local width = math.max(120, self:GetWide() - (self:GetActive() and 64 or closedX - panelX + 6))
			local maxLines = self:GetActive() and 4 or 2
			if notice.ZCWrapWidth ~= width or notice.ZCWrapLines ~= maxLines then
				notice.ZCWrapWidth = width
				notice.ZCWrapLines = maxLines
				notice.ZCLines = WrapSystemBannerText(notice.ZCMessage, width - 24, maxLines)
				notice:SetSize(width, math.max(32, #notice.ZCLines * 16 + 14))
			end
			if self:GetActive() then
				notice:SetPos(panelX + 32, openY)
				openY = openY + notice:GetTall() + 4
			else
				closedHeight = closedHeight + notice:GetTall() + 4
				lastHeight = notice:GetTall()
			end
		end
	end
	if not self:GetActive() then
		local closedY = orbY - math.max(0, closedHeight - 4 - lastHeight)
		self.ZCClosedNoticeTop = closedY
		for _, notice in ipairs(self.bannerNotices or {}) do
			if IsValid(notice) then
				notice:SetPos(closedX, closedY)
				closedY = closedY + notice:GetTall() + 4
			end
		end
	end
end

function PANEL:Think()
	local t = math.Clamp((CurTime() - self.fadeStart) / 0.25, 0, 1)
	self.frameAlpha = Lerp(t * t * (3 - 2 * t), self.fadeFrom, self.fadeTo)
	self.composeBlend = self.frameAlpha / 255
	if IsValid(self.entryPanel) and IsValid(self.entrySlot) then
		local slotWidth = self.entrySlot:GetWide()
		local width = math.max(1, slotWidth * self.composeBlend)
		self.entryPanel:SetSize(width, 40)
		self.entryPanel:SetPos(0, 0)
		self.entryPanel:SetAlpha(self.composeBlend * 255)
		self.entryPanel:SetVisible(self.composeBlend > 0.01)
		if IsValid(self.keyOrb) then
			local endX, endY = self.entrySlot:LocalToScreen(slotWidth - 40, 0)
			self.keyOrb:SetPos(Lerp(self.composeBlend, 48, endX),
				Lerp(self.composeBlend, ScrH() - 88, endY))
			self.keyOrb:SetAlpha(255 * math.Clamp((1 - self.composeBlend) / 0.25, 0, 1))
			self.keyOrb:MoveToFront()
		end
		if IsValid(self.ZCEmoteButton) then
			self.ZCEmoteButton:SetAlpha(255 * math.Clamp((self.composeBlend - 0.75) / 0.25, 0, 1))
		end
	end
	if IsValid(self.historySpacer) then
		local rowsHeight = 0
		for _, row in ipairs(self.entries) do
			if IsValid(row) then rowsHeight = rowsHeight + row:GetTall() + (row.ZCTopGap or 0) end
		end
		local targetHeight = math.max(0, self.history:GetTall() - rowsHeight)
		local currentHeight = self.historySpacer:GetTall()
		local nextHeight = Lerp(math.Clamp(FrameTime() * 16, 0, 1), currentHeight, targetHeight)
		if #self.entries == 0 then nextHeight = targetHeight end
		if math.abs(nextHeight - targetHeight) < 0.5 then nextHeight = targetHeight end
		if math.abs(nextHeight - currentHeight) >= 0.5 then self.historySpacer:SetTall(nextHeight) end
	end
	if self.scrollStart and IsValid(self.history) then
		local bar = self.history:GetVBar()
		local fraction = math.Clamp((CurTime() - self.scrollStart) / 0.25, 0, 1)
		bar:SetScroll(Lerp(fraction * fraction * (3 - 2 * fraction), self.scrollFrom or 0, bar.CanvasSize or 0))
		if fraction >= 1 then self.scrollStart = nil end
	end
	if IsValid(self.resizeHandle) then self.resizeHandle:SetVisible(self:GetActive()) end
	self:LayoutSystemBanners()
end

function PANEL:Paint(w, h)
	local fade = self.frameAlpha / 255
	surface.SetDrawColor(ZC_PANEL.r, ZC_PANEL.g, ZC_PANEL.b, ZC_PANEL.a * fade)
	surface.DrawRect(0, 0, w, h)

	-- One accent, on the bottom edge, breathing slowly enough to read as light
	-- rather than as a warning. The previous wash pulsed a red gradient across
	-- the whole panel once a second, which is a thing chat does not need to say.
	surface.SetDrawColor(ZC_ACCENT.r, ZC_ACCENT.g, ZC_ACCENT.b, (150 + math.sin(CurTime() * 0.35) * 30) * fade)
	surface.DrawRect(0, h - 2, w, 2)

	-- A hairline on the two edges that meet the screen, so the panel has a shape
	-- when it sits over something bright.
	surface.SetDrawColor(ZC_RULE.r, ZC_RULE.g, ZC_RULE.b, ZC_RULE.a * fade)
	surface.DrawRect(0, 0, w, 1)
	surface.DrawRect(0, 0, 1, h - 2)

	surface.SetAlphaMultiplier(1)
		self.history:PaintManual()
		local bar = self.history:GetVBar()
		bar:SetAlpha(self:GetActive() and 255 or 0)
	surface.SetAlphaMultiplier(1)

	DisableClipping(true)
		if LocalPlayer().organism and LocalPlayer().organism.otrub  then
			local noticeY = h + 6
			local noticeAlpha = self:GetActive() and 255 or 80
			draw.SimpleText("Your messages are currently not visible to anyone.", "zChatFontSmall", w - 4 + 1, noticeY + 1,
				Color(ZC_SHADOW.r, ZC_SHADOW.g, ZC_SHADOW.b, noticeAlpha), TEXT_ALIGN_RIGHT)
			draw.SimpleText("Your messages are currently not visible to anyone.", "zChatFontSmall", w - 4, noticeY,
				Color(ZC_ACCENT.r, ZC_ACCENT.g, ZC_ACCENT.b, noticeAlpha), TEXT_ALIGN_RIGHT)
		end
	DisableClipping(false)

end

function PANEL:SetActive(bActive, bRemovePrev)
	self.fadeFrom = self.frameAlpha
	self.fadeTo = bActive and 255 or 0
	self.fadeStart = CurTime()
	if (bActive) then
		self.closeTime = nil
		self.openTime = CurTime()
		local _, top = self.history:LocalToScreen(0, 0)
		local bottom = top + self.history:GetTall()
		local visible = {}
		for _, row in ipairs(self.entries) do
			if IsValid(row) then
				row.ZCOpenedAt = self.openTime
				row.ZCOpenOrder = 0
				local _, y = row:LocalToScreen(0, 0)
				if y < bottom and y + row:GetTall() > top then visible[#visible + 1] = row end
			end
		end
		for i, row in ipairs(visible) do
			row.ZCOpenOrder = #visible > 1 and (#visible - i) / (#visible - 1) or 0
		end
		self:MakePopup()
		if IsValid(self.entryPanel) then self.entryPanel:SetVisible(true) end
		self.entry:RequestFocus()

		input.SetCursorPos(self:LocalToScreen(10, self:GetTall() + 10))

		hook.Run("StartChat")
	else
		self.closeTime = CurTime()
		local _, top = self.history:LocalToScreen(0, 0)
		local bottom = top + self.history:GetTall()
		local visible = {}
		for i, row in ipairs(self.entries) do
			if IsValid(row) then
				row.ZCClosedAt = self.closeTime
				row.ZCCloseOrder = 0
				local _, y = row:LocalToScreen(0, 0)
				if y < bottom and y + row:GetTall() > top then visible[#visible + 1] = row end
			end
		end
		for i, row in ipairs(visible) do
			row.ZCCloseOrder = #visible > 1 and (i - 1) / (#visible - 1) or 0
		end
		ZCChatMedia.ClosePicker()
		self.resizing = false
		if IsValid(self.resizeHandle) then self.resizeHandle:MouseCapture(false) end
		self:SetMouseInputEnabled(false)
		self:SetKeyboardInputEnabled(false)

		if bRemovePrev then
			self.entry:SetText("")
			self.entry.prevText = ""
		end

		gui.EnableScreenClicker(false)

		hook.Run("FinishChat")
	end

	self.bActive = bActive

	local bar = self.history:GetVBar()
	bar:SetScroll(bar.CanvasSize)
end

function PANEL:AnimateAlpha(newAlpha)
	self:CreateAnimation(1, {
		index = 1,
		target = {alpha = newAlpha},
	})
end

function PANEL:AnimateRealAlpha(newAlpha)
	self:CreateAnimation(1, {
		index = 2,
		target = {realAlpha = newAlpha},
	})
end

function PANEL:SetRealAlpha(alpha)
	self.realAlpha = alpha
end

function PANEL:OnMessageSent()
	local text = self.entry:GetText()

	if (text:find("%S")) then
		local lastEntry = hg.chat.messageHistory[#hg.chat.messageHistory]

		-- only add line to textentry history if it isn't the same message
		if (lastEntry != text) then
			if (#hg.chat.messageHistory >= 20) then
				table.remove(hg.chat.messageHistory, 1)
			end

			hg.chat.messageHistory[#hg.chat.messageHistory + 1] = text
		end

		net.Start("zChatMessage")
			net.WriteString(text)
		net.SendToServer()
	end

	self:SetActive(false, true)
end

function PANEL:ShowSystemBanner(elements)
	if self.bannerMuted then return end
	local parts = {}
	for _, value in ipairs(elements) do
		if isstring(value) or isnumber(value) then parts[#parts + 1] = tostring(value) end
		if type(value) == "Player" and IsValid(value) then parts[#parts + 1] = value:Nick() end
	end
	local message = string.Trim(table.concat(parts))
	if message == "" then return end
	while #self.bannerNotices >= 3 do
		local oldest = table.remove(self.bannerNotices, 1)
		if IsValid(oldest) then oldest:Remove() end
	end
	local banner = vgui.Create("DPanel")
	self.bannerNotices[#self.bannerNotices + 1] = banner
	banner.ZCMessage = message
	banner:SetMouseInputEnabled(false)
	banner:SetKeyboardInputEnabled(false)
	banner:SetSize(math.max(120, self:GetWide() - 64), 32)
	self:LayoutSystemBanners()
	banner:SetTooltip(message)
	banner:MoveToFront()
	if IsValid(self.bannerMuteButton) then self.bannerMuteButton:MoveToFront() end
	local started = CurTime()
	banner.Paint = function(panel, w, h)
		local elapsed = CurTime() - started
		local alpha = 255 * math.min(math.Clamp(elapsed / 0.18, 0, 1), math.Clamp((3.5 - elapsed) / 0.25, 0, 1))
		draw.RoundedBox(8, 0, 0, w, h, Color(35, 43, 54, alpha * 0.96))
		for i, line in ipairs(panel.ZCLines or {}) do
			draw.SimpleText(line, "DermaDefaultBold", 12, 7 + (i - 1) * 16,
				Color(235, 241, 250, alpha), TEXT_ALIGN_LEFT)
		end
	end
	banner.Think = function(panel)
		if CurTime() - started < 3.5 then return end
		panel:Remove()
		for i, notice in ipairs(self.bannerNotices) do
			if notice == panel then table.remove(self.bannerNotices, i) break end
		end
		self:LayoutSystemBanners()
	end
end

function PANEL:AddLine(elements)
	local speaker = IsValid(CHAT_SPEAKER) and CHAT_SPEAKER or nil
	if not speaker and not CHAT_IS_BOT then
		self:ShowSystemBanner(elements)
		return
	end
	local buffer = {
		"<font=zChatFont>"
	}

	buffer = hook.Run("ModifyMessageBuffer", buffer, CHAT_SPEAKER) or buffer

	local display, gifURL = ZCChatMedia.DisplayElements(elements)
	local function format(items, parts)
	for _, v in ipairs(items) do
		if (type(v) == "IMaterial") then
			local texture = v:GetName()

			if (texture) then
				parts[#parts + 1] = string.format("<img=%s,%dx%d> ", texture, v:Width(), v:Height())
			end
		elseif (istable(v) and v.r and v.g and v.b) then
			parts[#parts + 1] = string.format("<color=%d,%d,%d>", v.r, v.g, v.b)
		elseif (type(v) == "Player") then
			local color = team.GetColor(v:Team())

			parts[#parts + 1] = string.format("<color=%d,%d,%d>%s", color.r, color.g, color.b,
				v:GetName():gsub("<", "&lt;"):gsub(">", "&gt;"))
		else
			parts[#parts + 1] = ZCChatMedia.Format(tostring(v), 18)
		end
	end

		return table.concat(parts)
	end
	local originalText
	if gifURL then
		local originalBuffer = {}
		for i, value in ipairs(buffer) do originalBuffer[i] = value end
		originalText = format(elements, originalBuffer)
	end
	local displayText = format(display, buffer)

	local panel = self.history:Add("zChatMessage")
	panel.ZCMessageID = tonumber(CHAT_MESSAGE_ID)
	panel.ZCSpeaker = speaker
	local previous = self.entries[#self.entries]
	if IsValid(previous) and previous.ZCSpeaker ~= speaker then
		panel.ZCTopGap = 6
		panel:DockMargin(0, panel.ZCTopGap, 0, 0)
	end
	if speaker or CHAT_IS_BOT then
		panel.ZCBubble = true
		panel.ZCBot = (speaker and speaker:IsBot()) or CHAT_IS_BOT or false
	end
	if speaker then
		panel.ZCOwn = speaker == LocalPlayer()
		panel.ZCLeftInset = 42
		panel.ZCAvatar = panel:Add("AvatarImage")
		panel.ZCAvatar:SetPos(0, 0)
		panel.ZCAvatar:SetSize(34, 34)
		panel.ZCAvatar:SetPlayer(speaker, 34)
		panel.ZCAvatar:SetMouseInputEnabled(false)
	end
	panel:Dock(TOP)
	panel:InvalidateParent(true)
	panel:SetMarkup(displayText)
	panel.ZCGifOriginalText = originalText
	ZCChatMedia.Attach(panel, elements)

	if (#self.entries >= 100) then
		local oldPanel = table.remove(self.entries, 1)

		if (IsValid(oldPanel)) then
			oldPanel:Remove()
		end
	end

	local bar = self.history:GetVBar()
	local bScroll = !self:GetActive() or bar:GetScroll() >= (bar.CanvasSize or 0) - 8
	if bScroll then
		self.scrollFrom = bar:GetScroll()
		self.scrollStart = CurTime()
	end

	self.entries[#self.entries + 1] = panel
	return panel
end

function PANEL:AddMessage(...)
	self:AddLine({...})

	chat.PlaySound()
end

function PANEL:OnRemove()
	if IsValid(self.keyOrb) then self.keyOrb:Remove() end
	for _, notice in ipairs(self.bannerNotices or {}) do
		if IsValid(notice) then notice:Remove() end
	end
end

vgui.Register("zChatbox", PANEL, "EditablePanel")

hook.Add("HUDPaint", "ZCChat_WhisperIndicator", function()
	if ZChatWhisper then PaintWhisperIcon(96, ScrH() - 76, 235) end
end)

hook.Add("ZC_ULXVoteStarted", "ZCChat_ULXVotePush", function(title, timeout, options)
	if IsValid(hg.ZCChatVotePush) then hg.ZCChatVotePush:Remove() end
	local card = vgui.Create("DPanel")
	hg.ZCChatVotePush = card
	card:SetSize(math.min(360, IsValid(hg.chat) and hg.chat:GetWide() - 24 or ScrW() - 24), 92)
	card:SetMouseInputEnabled(false)
	card:SetKeyboardInputEnabled(false)
	card:SetAlpha(0)
	card.Think = function(self)
		local chatbox = hg and hg.chat
		if not IsValid(chatbox) then return end
		local x, y = chatbox:LocalToScreen(0, 0)
		self.ZCSlim = not chatbox:GetActive()
		self:SetSize(math.min(360, chatbox:GetWide() - 24), self.ZCSlim and 52 or 92)
		local cardY = self.ZCSlim and
			((chatbox.ZCClosedNoticeTop or (y + chatbox:GetTall() - 48)) - self:GetTall() - 8) or
			(y + (chatbox:GetTall() - self:GetTall()) / 2)
		self:SetPos(math.Clamp(x + (chatbox:GetWide() - self:GetWide()) / 2, 0, ScrW() - self:GetWide()),
			math.Clamp(cardY, 0, ScrH() - self:GetTall()))
	end
	card:Think()
	local voteTitle = tostring(title or "Vote")
	local choices = {}
	for i = 1, math.min(#(options or {}), 3) do choices[#choices + 1] = tostring(options[i]) end
	local summary = table.concat(choices, "  •  ")
	card.Paint = function(self, w, h)
		draw.RoundedBox(16, 0, 0, w, h, Color(37, 43, 54, 244))
		draw.SimpleText("ULX VOTE", "DermaDefaultBold", w / 2, self.ZCSlim and 5 or 11, Color(145, 205, 255), TEXT_ALIGN_CENTER)
		draw.SimpleText(string.sub(voteTitle, 1, 55), "DermaDefaultBold", w / 2, self.ZCSlim and 23 or 32, color_white, TEXT_ALIGN_CENTER)
		if self.ZCSlim then return end
		surface.SetDrawColor(255, 255, 255, 28)
		surface.DrawRect(16, 60, w - 32, 1)
		draw.SimpleText(string.sub(summary, 1, 80), "DermaDefault", w / 2, 69, Color(205, 213, 226), TEXT_ALIGN_CENTER)
	end
	card:AlphaTo(255, 0.2, 0)
	timer.Simple(math.min(math.max(tonumber(timeout) or 7, 2), 7), function()
		if not IsValid(card) then return end
		card:AlphaTo(0, 0.25, 0, function()
			if IsValid(card) then card:Remove() end
			if hg.ZCChatVotePush == card then hg.ZCChatVotePush = nil end
		end)
	end)
end)
