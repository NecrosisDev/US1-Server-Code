-- ============================================================
--  Watchdog: STAFF INTERFACE (client half) -- DUMB RENDERER
-- ------------------------------------------------------------
--  Contains NO thresholds and NO detection logic. It draws whatever
--  the server sends and forwards button clicks back. The server
--  validates IsSuperAdmin() on every request, so this file being
--  readable by anyone (including cheaters) leaks nothing useful.
--
--  Open with the console command:  wd
-- ============================================================
if not CLIENT then return end

local PANEL
local activeTab = "overview"   -- remembered across refreshes while connected
local last = { modules = {}, live = {}, dossiers = {}, mode = "?", version = "?" }

local col = {
	bg     = Color(24, 26, 32),
	bg2    = Color(32, 35, 44),
	line   = Color(52, 57, 70),
	text   = Color(214, 220, 232),
	dim    = Color(150, 158, 175),
	green  = Color(90, 200, 130),
	red    = Color(226, 96, 96),
	amber  = Color(232, 178, 72),
	accent = Color(120, 165, 255),
}

local function req(kind, extra)
	net.Start("WD_UI_Req")
	net.WriteUInt(kind, 8)
	if extra then extra() end
	net.SendToServer()
end

-- ---------------- SETTINGS TAB (dumb renderer) ----------------
-- Renders whatever schema rows the server sent (superadmins only get them).
-- All validation/clamping happens server-side; this just draws and sends.
local function buildSettings(root)
	-- write access is server-decided (settingsWriteGroup). nil => legacy server
	-- that only ever sent config to superadmins, so treat as writable.
	local canWrite = last.configCanWrite ~= false

	local sc = vgui.Create("DScrollPanel", root)
	sc:Dock(FILL)
	sc.Paint = function(_, w, h) draw.RoundedBox(4, 0, 0, w, h, col.bg2) end

	if not canWrite then
		local ro = vgui.Create("DLabel", sc)
		ro:Dock(TOP) ro:DockMargin(10, 10, 10, 2) ro:SetTall(18)
		ro:SetText("READ-ONLY  -  your rank can view these settings but not change them.")
		ro:SetTextColor(col.amber)
	end

	local function section(title)
		local l = vgui.Create("DLabel", sc)
		l:Dock(TOP) l:DockMargin(10, 10, 10, 2) l:SetTall(16)
		l:SetText(title) l:SetFont("DermaDefaultBold") l:SetTextColor(col.accent)
	end

	local function send(key, val)
		req(4, function() net.WriteString(key) net.WriteString(tostring(val)) end)
	end
	local function sendList(listKey, isAdd, value)
		req(6, function() net.WriteString(listKey) net.WriteBool(isAdd) net.WriteString(value) end)
	end

	local group
	for _, s in ipairs(last.config or {}) do
		if s.group ~= group then group = s.group section(group) end

		local row = vgui.Create("DPanel", sc)
		row:Dock(TOP) row:DockMargin(10, 0, 10, 3) row:SetTall(26)
		row.Paint = function(_, w, h)
			draw.RoundedBox(3, 0, 0, w, h, col.bg)
			-- list rows are tall: pin the label to the top line
			draw.SimpleText(s.label, "DermaDefault", 8, s.kind == "list" and 13 or h/2, col.text, 0, 1)
		end
		row:SetTooltip((s.desc or s.key) .. "  [" .. s.key .. "]")

		if s.kind == "list" then
			-- stacked entries, each removable; add box at the bottom (write rank only)
			local entries = istable(s.value) and s.value or {}
			local inner = vgui.Create("DPanel", row)
			inner:Dock(FILL) inner:DockMargin(8, 26, 8, 4)
			inner.Paint = function() end
			for _, item in ipairs(entries) do
				local line = vgui.Create("DPanel", inner)
				line:Dock(TOP) line:SetTall(20) line:DockMargin(0, 0, 0, 2)
				line.Paint = function(_, w, h)
					draw.RoundedBox(3, 0, 0, w, h, col.bg2)
					draw.SimpleText(item, "DermaDefault", 6, h/2, col.text, 0, 1)
				end
				if canWrite then
					local x = vgui.Create("DButton", line)
					x:Dock(RIGHT) x:SetWide(22) x:SetText("")
					x.Paint = function(pnl, w, h)
						draw.SimpleText("x", "DermaDefaultBold", w/2, h/2 - 1,
							pnl:IsHovered() and col.red or col.dim, 1, 1)
					end
					x:SetTooltip("remove")
					x.DoClick = function() sendList(s.key, false, item) end
				end
			end
			if #entries == 0 then
				local e = vgui.Create("DLabel", inner)
				e:Dock(TOP) e:SetTall(18)
				e:SetText("(empty)") e:SetTextColor(col.dim)
			end
			if canWrite then
				local addline = vgui.Create("DPanel", inner)
				addline:Dock(TOP) addline:SetTall(22) addline:DockMargin(0, 2, 0, 0)
				addline.Paint = function() end
				local addb = vgui.Create("DButton", addline)
				addb:Dock(RIGHT) addb:SetWide(44) addb:SetText("")
				addb.Paint = function(_, w, h)
					draw.RoundedBox(3, 0, 0, w, h, col.bg2)
					draw.SimpleText("ADD", "DermaDefaultBold", w/2, h/2, col.green, 1, 1)
				end
				local entry = vgui.Create("DTextEntry", addline)
				entry:Dock(FILL) entry:DockMargin(0, 0, 2, 0)
				if entry.SetPlaceholderText then entry:SetPlaceholderText(s.hint or "add...") end
				local function apply()
					local t = string.Trim(entry:GetText() or "")
					if t ~= "" then sendList(s.key, true, t) end
				end
				addb.DoClick = apply
				entry.OnEnter = apply
			end
			row:SetTall(30 + math.max(#entries, 1) * 22 + (canWrite and 26 or 4))

		elseif not canWrite then
			-- read-only: show the current value, no interactive control
			local v = vgui.Create("DLabel", row)
			v:Dock(RIGHT) v:SetWide(150) v:DockMargin(0, 0, 10, 0)
			v:SetContentAlignment(6)
			if s.kind == "bool" then
				v:SetText(s.value and "ON" or "OFF")
				v:SetTextColor(s.value and col.green or col.red)
			else
				v:SetText(tostring(s.value))
				v:SetTextColor(col.accent)
			end
		elseif s.kind == "bool" then
			local b = vgui.Create("DButton", row)
			b:Dock(RIGHT) b:SetWide(130) b:DockMargin(0, 3, 3, 3) b:SetText("")
			b.Paint = function(_, w, h)
				local armed = b._armT and b._armT > SysTime()
				local on = s.value == true
				draw.RoundedBox(3, 0, 0, w, h, col.bg2)
				draw.SimpleText(armed and "CLICK TO CONFIRM" or (on and "ON" or "OFF"),
					"DermaDefaultBold", w/2, h/2,
					armed and col.amber or (on and col.green or col.red), 1, 1)
			end
			b.DoClick = function()
				-- risky settings need a second click within 3s
				if s.risky and not (b._armT and b._armT > SysTime()) then
					b._armT = SysTime() + 3
					return
				end
				send(s.key, not s.value)
			end

		elseif s.kind == "enum" then
			local b = vgui.Create("DButton", row)
			b:Dock(RIGHT) b:SetWide(130) b:DockMargin(0, 3, 3, 3) b:SetText("")
			b.Paint = function(_, w, h)
				draw.RoundedBox(3, 0, 0, w, h, col.bg2)
				draw.SimpleText(tostring(s.value) .. "  >", "DermaDefaultBold", w/2, h/2, col.accent, 1, 1)
			end
			b.DoClick = function()   -- cycle to the next option
				local opts = s.options or {}
				local idx = 1
				for i, o in ipairs(opts) do if o == s.value then idx = i break end end
				if #opts > 0 then send(s.key, opts[(idx % #opts) + 1]) end
			end

		elseif s.kind == "number" then
			local setb = vgui.Create("DButton", row)
			setb:Dock(RIGHT) setb:SetWide(44) setb:DockMargin(2, 3, 3, 3) setb:SetText("")
			local entry = vgui.Create("DTextEntry", row)
			entry:Dock(RIGHT) entry:SetWide(84) entry:DockMargin(0, 3, 0, 3)
			entry:SetNumeric(true) entry:SetText(tostring(s.value))
			local function apply()
				local n = tonumber(entry:GetText())
				if n then send(s.key, n) end
			end
			setb.Paint = function(_, w, h)
				draw.RoundedBox(3, 0, 0, w, h, col.bg2)
				draw.SimpleText("SET", "DermaDefaultBold", w/2, h/2, col.green, 1, 1)
			end
			setb.DoClick = apply
			entry.OnEnter = apply
			local hint = vgui.Create("DLabel", row)
			hint:Dock(RIGHT) hint:SetWide(76) hint:DockMargin(0, 0, 4, 0)
			hint:SetText((s.min or "") .. " - " .. (s.max or ""))
			hint:SetTextColor(col.dim) hint:SetContentAlignment(6)

		elseif s.kind == "text" then
			local setb = vgui.Create("DButton", row)
			setb:Dock(RIGHT) setb:SetWide(44) setb:DockMargin(2, 3, 3, 3) setb:SetText("")
			local entry = vgui.Create("DTextEntry", row)
			entry:Dock(RIGHT) entry:SetWide(380) entry:DockMargin(0, 3, 0, 3)
			entry:SetText(tostring(s.value or ""))
			entry:SetUpdateOnType(false)
			local function apply()
				local t = string.Trim(entry:GetText() or "")
				if t ~= "" then send(s.key, t) end
			end
			setb.Paint = function(_, w, h)
				draw.RoundedBox(3, 0, 0, w, h, col.bg2)
				draw.SimpleText("SET", "DermaDefaultBold", w/2, h/2, col.green, 1, 1)
			end
			setb.DoClick = apply
			entry.OnEnter = apply
		end
	end

	local note = vgui.Create("DLabel", sc)
	note:Dock(TOP) note:DockMargin(10, 10, 10, 10) note:SetTall(16)
	note:SetText(canWrite
		and "Changes apply live and persist across restarts (data/watchdog/config.json - delete it to reset defaults)."
		or "View-only access. Ask a higher rank to change these.")
	note:SetTextColor(col.dim)
end

local function makeBody(frame)
	-- NEVER Clear() the DFrame itself: Clear() deletes ALL children including
	-- the frame's own built-in title-bar panels (close button, title label),
	-- and DFrame:PerformLayout then errors every frame on the NULL button -
	-- which is also why the panel became unclosable. Rebuild a content panel.
	local root = frame._content
	if not IsValid(root) then
		root = vgui.Create("DPanel", frame)
		root:Dock(FILL)
		root.Paint = function() end
		frame._content = root
	end
	root:Clear()

	-- header
	local head = vgui.Create("DPanel", root)
	head:Dock(TOP) head:SetTall(30) head:DockMargin(0, 0, 0, 6)
	head.Paint = function(_, w, h)
		draw.RoundedBox(4, 0, 0, w, h, col.bg2)
		draw.SimpleText("ZC WATCHDOG", "DermaDefaultBold", 10, h/2, col.accent, 0, 1)
		draw.SimpleText("v" .. last.version .. "  -  " .. last.mode .. "  -  " ..
			(last.enabled and "ENABLED" or "DISABLED"),
			"DermaDefault", 120, h/2, last.enabled and col.green or col.red, 0, 1)
		draw.SimpleText("(watch mode - dossiers only, no auto-bans)", "DermaDefault", w - 10, h/2, col.dim, 2, 1)
	end

	-- tab bar (SETTINGS is offered only when the server sent config = superadmin)
	local canSettings = istable(last.config) and #last.config > 0
	if activeTab == "settings" and not canSettings then activeTab = "overview" end

	local tabs = vgui.Create("DPanel", root)
	tabs:Dock(TOP) tabs:SetTall(24) tabs:DockMargin(0, 0, 0, 6)
	tabs.Paint = function() end
	local function tabBtn(id, label)
		local b = vgui.Create("DButton", tabs)
		b:Dock(LEFT) b:SetWide(110) b:DockMargin(0, 0, 4, 0) b:SetText("")
		b.Paint = function(_, w, h)
			local on = (activeTab == id)
			draw.RoundedBox(4, 0, 0, w, h, on and col.line or col.bg2)
			draw.SimpleText(label, "DermaDefaultBold", w/2, h/2, on and col.text or col.dim, 1, 1)
		end
		b.DoClick = function()
			if activeTab == id then return end
			activeTab = id
			makeBody(frame)
		end
	end
	tabBtn("overview", "OVERVIEW")
	if canSettings then tabBtn("settings", "SETTINGS") end

	if activeTab == "settings" then
		buildSettings(root)
		PANEL._showDossier = nil
		frame._rebuildLive = nil   -- no live host on this tab; poll will no-op
		return
	end

	local body = vgui.Create("DPanel", root)
	body:Dock(FILL)
	body.Paint = function() end

	-- left column: modules + live suspicion
	local left = vgui.Create("DScrollPanel", body)
	left:Dock(LEFT) left:SetWide(340) left:DockMargin(0, 0, 6, 0)
	left.Paint = function(_, w, h) draw.RoundedBox(4, 0, 0, w, h, col.bg2) end

	local function section(parent, title)
		local l = vgui.Create("DLabel", parent)
		l:Dock(TOP) l:DockMargin(8, 8, 8, 2) l:SetTall(18)
		l:SetText(title) l:SetFont("DermaDefaultBold") l:SetTextColor(col.dim)
	end

	section(left, "MODULES  (click to toggle)")
	for _, m in ipairs(last.modules) do
		local row = vgui.Create("DButton", left)
		row:Dock(TOP) row:DockMargin(8, 0, 8, 2) row:SetTall(22) row:SetText("")
		row.Paint = function(_, w, h)
			draw.RoundedBox(3, 0, 0, w, h, col.bg)
			draw.SimpleText(m.enabled and "ON " or "OFF", "DermaDefault", 8, h/2, m.enabled and col.green or col.red, 0, 1)
			draw.SimpleText(m.name, "DermaDefault", 44, h/2, col.text, 0, 1)
		end
		row.DoClick = function()
			req(3, function() net.WriteString(m.name) net.WriteBool(not m.enabled) end)
		end
		row:SetTooltip(m.desc)
	end

	section(left, "LIVE SUSPICION")
	-- live rows live in their own host panel so the auto-poll can refresh JUST
	-- them in place, without rebuilding the whole panel (which would reset your
	-- scroll, the dossier reader, and the module list).
	local liveHost = vgui.Create("DPanel", left)
	liveHost:Dock(TOP) liveHost:DockMargin(8, 0, 8, 4)
	liveHost.Paint = function() end
	local function rebuildLive()
		if not IsValid(liveHost) then return end
		liveHost:Clear()
		local rows = 0
		for _, p in ipairs(last.live or {}) do
			if p.hot then
				local parts = {}
				for mod, sc in pairs(p.scores or {}) do parts[#parts + 1] = mod .. ":" .. sc end
				local nick, txt = p.nick, table.concat(parts, "  ")
				local row = vgui.Create("DPanel", liveHost)
				row:Dock(TOP) row:DockMargin(0, 0, 0, 2) row:SetTall(34)
				row.Paint = function(_, w, h)
					draw.RoundedBox(3, 0, 0, w, h, col.bg)
					draw.SimpleText(nick, "DermaDefaultBold", 8, 7, col.text, 0, 0)
					draw.SimpleText(txt, "DermaDefault", 8, 20, col.amber, 0, 0)
				end
				rows = rows + 1
			end
		end
		if rows == 0 then
			local l = vgui.Create("DLabel", liveHost)
			l:Dock(TOP) l:DockMargin(4, 2, 0, 4) l:SetTall(18)
			l:SetText("(all clean)") l:SetTextColor(col.green)
			liveHost:SetTall(24)
		else
			liveHost:SetTall(rows * 36 + 2)
		end
		if IsValid(left) then left:InvalidateLayout() end
	end
	frame._rebuildLive = rebuildLive
	rebuildLive()

	-- right column: dossiers list + viewer
	local right = vgui.Create("DPanel", body)
	right:Dock(FILL)
	right.Paint = function(_, w, h) draw.RoundedBox(4, 0, 0, w, h, col.bg2) end

	-- dossier reader: RichText inside a painted wrap = proper mouse-wheel
	-- scrolling with a scrollbar (the old DTextEntry couldn't scroll)
	local viewerWrap = vgui.Create("DPanel", right)
	viewerWrap:Dock(BOTTOM) viewerWrap:SetTall(math.floor(frame:GetTall() * 0.38))
	viewerWrap:DockMargin(6, 4, 6, 6)
	viewerWrap.Paint = function(_, w, h) draw.RoundedBox(3, 0, 0, w, h, col.bg) end

	local function showDossier(text)
		if not IsValid(viewerWrap) then return end
		viewerWrap:Clear()   -- plain DPanel: safe to clear (never a DFrame)
		local rt = vgui.Create("RichText", viewerWrap)
		rt:Dock(FILL) rt:DockMargin(6, 6, 6, 6)
		function rt:PerformLayout()
			self:SetFontInternal("DermaDefault")
			self:SetFGColor(col.text)
		end
		rt:AppendText(text or "(empty)")
		rt:GotoTextStart()
	end
	PANEL._showDossier = showDossier
	showDossier("Select a dossier to read it. Scroll with the mouse wheel.")

	local dl = vgui.Create("DLabel", right)
	dl:Dock(TOP) dl:DockMargin(8, 6, 8, 2) dl:SetTall(18)
	dl:SetText("DOSSIERS  (newest first)") dl:SetFont("DermaDefaultBold") dl:SetTextColor(col.dim)

	local list = vgui.Create("DScrollPanel", right)
	list:Dock(FILL) list:DockMargin(6, 0, 6, 0)
	for _, fname in ipairs(last.dossiers) do
		local b = vgui.Create("DButton", list)
		b:Dock(TOP) b:DockMargin(0, 0, 0, 2) b:SetTall(20) b:SetText("")
		b.Paint = function(pnl, w, h)
			draw.RoundedBox(3, 0, 0, w, h, pnl:IsHovered() and col.line or col.bg)
			draw.SimpleText(fname, "DermaDefault", 6, h/2, col.text, 0, 1)
		end
		b.DoClick = function()
			req(2, function() net.WriteString(fname) end)
		end
	end
end

local function openPanel()
	if IsValid(PANEL) then PANEL:Remove() end
	-- soft precheck only (the server's panelMinGroup floor can't go below
	-- operator); the SERVER is authoritative and replies "denied" if short.
	local lp = LocalPlayer()
	local likely = lp:IsAdmin() or (lp.CheckGroup and lp:CheckGroup("operator"))
	if not likely then
		chat.AddText(col.red, "[Watchdog] staff only.")
		return
	end
	local f = vgui.Create("DFrame")
	-- scale to the player's screen so live suspicion fits without scrolling
	local w = math.Clamp(math.floor(ScrW() * 0.70), 760, 1150)
	local h = math.Clamp(math.floor(ScrH() * 0.78), 520, 840)
	f:SetSize(w, h) f:Center() f:SetTitle("") f:MakePopup()
	f.Paint = function(_, w, h)
		draw.RoundedBox(6, 0, 0, w, h, col.bg)
		draw.RoundedBox(6, 0, 0, w, 24, col.bg2)
	end
	PANEL = f
	makeBody(f)
	req(1)

	-- auto-refresh live suspicion while the panel is open (overview tab only).
	-- Uses the cheap live-only request (kind 5) so it never disturbs the dossier
	-- reader, module list, scroll position, or the Settings tab.
	timer.Create("WD_UI_LivePoll", 2, 0, function()
		if not IsValid(PANEL) then timer.Remove("WD_UI_LivePoll") return end
		if activeTab ~= "overview" then return end
		req(5)
	end)
	f.OnRemove = function() timer.Remove("WD_UI_LivePoll") end
end

-- `wd` toggles: open if closed, close if open (so there's always a way out;
-- the title-bar X works too now that Clear() no longer eats it)
concommand.Add("wd", function()
	if IsValid(PANEL) then PANEL:Remove() PANEL = nil return end
	openPanel()
end)

net.Receive("WD_UI_Data", function()
	local kind = net.ReadUInt(8)
	local len = net.ReadUInt(32)

	if kind == 9 then  -- new-dossier nudge
		if IsValid(PANEL) then req(1) end
		return
	end

	local data = len > 0 and net.ReadData(len) or ""
	local tbl = util.JSONToTable(util.Decompress(data) or "") or {}

	if kind == 5 then   -- live-only poll refresh: update just the live rows in place
		if istable(tbl) and tbl.live then last.live = tbl.live end
		if IsValid(PANEL) and activeTab == "overview" and PANEL._rebuildLive then
			PANEL._rebuildLive()
		end
		return
	end

	if kind == 7 then   -- server denied panel access (rank below panelMinGroup)
		chat.AddText(col.red, "[Watchdog] ", col.text, tbl.reason or "you don't have access to this panel.")
		if IsValid(PANEL) then PANEL:Remove() end
		PANEL = nil
		return
	end

	if kind == 1 then
		last = tbl
		if IsValid(PANEL) then makeBody(PANEL) end
	elseif kind == 2 then
		if IsValid(PANEL) and PANEL._showDossier then
			PANEL._showDossier(tbl.body or "(empty)")
		end
	end
end)

-- on-screen alert to staff when a detection lands (toast + sound + chat line)
net.Receive("WD_Alert", function()
	local nick = net.ReadString()
	local module = net.ReadString()
	notification.AddLegacy("WATCHDOG: " .. nick .. "  (" .. module .. ")", NOTIFY_ERROR, 8)
	surface.PlaySound("buttons/button17.wav")
	chat.AddText(col.amber, "[Watchdog] ", col.text, nick, col.dim, "  flagged: ", col.amber, module,
		col.dim, "   (type ", col.text, "wd", col.dim, " to review)")
	if IsValid(PANEL) then req(1) end
end)
