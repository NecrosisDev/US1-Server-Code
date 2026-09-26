return string.sub([========[x    local bottom = vgui.Create("DPanel", frame) bottom:Dock(BOTTOM) bottom:SetTall(84) bottom:DockMargin(0, 6, 0, 0) bottom.Paint = nil
    local scene = vgui.Create("DPanel", frame) scene:Dock(FILL) scene:DockMargin(0, 6, 0, 0)
    scene.Paint = paintScene
    scene.OnMouseWheeled = function(_, delta) if state then state.zoom = math.Clamp(state.zoom * (delta > 0 and 1.15 or 0.87), 0.08, 3) end end
    scene.OnMousePressed = function(s) if state then s.drag = {gui.MouseX(), gui.MouseY(), state.camX, state.camY} state.follow = nil s:MouseCapture(true) end end
    scene.OnMouseReleased = function(s) s.drag = nil s:MouseCapture(false) end
    scene.Think = function(s)
        if state and s.drag then
            state.camX = s.drag[3] - (gui.MouseX() - s.drag[1]) / state.zoom
            state.camY = s.drag[4] + (gui.MouseY() - s.drag[2]) / state.zoom
        end
        if state and state.playing then
            state.cs = state.cs + RealFrameTime() * 100 * state.speed
            if state.cs >= state.clip.last then state.cs = state.clip.last state.playing = false end
        end
    end

    local timeline = vgui.Create("DPanel", bottom) timeline:Dock(TOP) timeline:SetTall(44)
    timeline.Paint = paintTimeline
    timeline.OnMousePressed = function(s) s.dragging = true if state then state.playing = false end end
    local bar = vgui.Create("DPanel", bottom) bar:Dock(FILL) bar:DockMargin(0, 4, 0, 0) bar.Paint = nil
    local function add(text, wide, fn) local b = button(bar, text, function() if state then fn() end end) b:Dock(LEFT) b:SetWide(wide) b:DockMargin(0, 0, 4, 0) return b end
    add("|< event", 80, function() jumpEvent(-1) end)
    add("-1s", 50, function() seek(state.cs - 100) end)
    add("-0.1", 50, function() state.playing = false seek(state.cs - 10) end)
    add(function() return state and state.playing and "Pause" or "Play" end, 80, function()
        if state.cs >= state.clip.last then seek(state.clip.first) end
        state.playing = not state.playing
    end)
    add("+0.1", 50, function() state.playing = false seek(state.cs + 10) end)
    add("+1s", 50, function() seek(state.cs + 100) end)
    add("event >|", 80, function() jumpEvent(1) end)
    add(function() return "Speed " .. (state and state.speed or 1) .. "x" end, 100, function() state.speed = state.speed == 1 and 2 or (state.speed == 2 and 0.25 or 1) end)
    add(function() return "Follow: " .. (state and state.follow and state.clip.actors[state.follow].label or "free") end, 190, function()
        local n = #state.clip.actors
        local i = state.follow or 0
        for _ = 1, n do i = i % n + 1 if state.clip.actors[i].named then state.follow = i return end end
    end)
    add(function() return state and state.showMap and "Map: on" or "Map: off" end, 80, function() state.showMap = not state.showMap end)

    function frame:Rebuild()
        right:Clear()
        if not state then return end
        local filed = notes[state.id]
        if filed and #filed > 0 then
            local box = vgui.Create("DPanel", right) box:Dock(TOP) box:SetTall(26 + #filed * 38) box:DockMargin(0, 0, 0, 6)
            box.Paint = function(_, w, h)
                surface.SetDrawColor(COL.panel) surface.DrawRect(0, 0, w, h)
                draw.SimpleText("Reported by " .. filed.reporter, "ZCKC.Head", 8, 4, COL.bad)
                for i, item in ipairs(filed) do
                    local y = 26 + (i - 1) * 38
                    draw.SimpleText(string.format("Hit %d, %s%s", item.instance, item.attacker, item.attackerId ~= "" and ("  " .. item.attackerId) or ""), "ZCKC.Small", 8, y, COL.dim)
                    draw.SimpleText(item.text ~= "" and item.text or "(no comment)", "ZCKC.Body", 8, y + 14, COL.text)
                end
            end
        end
        if state.seq then -- life sequence: every hit taken that life, one button each, and a report control
            local strip = vgui.Create("DPanel", right) strip:Dock(TOP) strip:SetTall(30 + #state.seq.instances * 26 + 34) strip:DockMargin(0, 0, 0, 6)
            strip.Paint = function(_, w, h) surface.SetDrawColor(COL.panel) surface.DrawRect(0, 0, w, h) draw.SimpleText("Every hit you took that life", "ZCKC.Head", 8, 4, COL.text) end
            strip:DockPadding(6, 28, 6, 6)
            for i, inst in ipairs(state.seq.instances) do
                local b = button(strip, function()
                    return string.format("%d  %s  %s dmg  %s%s", i, tostring(inst.attacker), tostring(inst.dmg or 0), V.Tags and V.Tags[inst.tag] or inst.tag or "", state.reported[i] and "  (reported)" or "")
                end, function() loadInstance(state.id, state.seq, i) end)
                b:Dock(TOP) b:SetTall(24) b:DockMargin(0, 0, 0, 2)
                local paint = b.Paint
                b.Paint = function(s, w, h) paint(s, w, h) if state and state.index == i then surface.SetDrawColor(COL.text) surface.DrawRect(0, 0, 3, h) end end
            end
            local current = state.seq.instances[state.index]
            local report = button(strip, function()
                if state.reported[state.index] then return "Reported" end
                return current.reportable and "Report this hit to staff" or "This hit can't be reported"
            end, function()
                if current.reportable and not state.reported[state.index] and V.ReportDialog then V.ReportDialog(state.id, state.index, current) end
            end)
            report:Dock(TOP) report:SetTall(28) report:DockMargin(0, 4, 0, 0)
        end
        local head = vgui.Create("DPanel", right) head:Dock(TOP) head:SetTall(26 + #state.findings * 34)
        head.Paint = function(_, w, h)
            surface.SetDrawColor(COL.panel) surface.DrawRect(0, 0, w, h)
            draw.SimpleText("Findings", "ZCKC.Head", 8, 4, COL.text)
            for i, f in ipairs(state.findings) do
                local y = 26 + (i - 1) * 34
                draw.SimpleText(f.name, "ZCKC.Small", 8, y, COL.dim)
                draw.SimpleText(f.value, "ZCKC.Body", 8, y + 13, COL[f.tone or ""] or COL.text)
            end
        end
        local list = vgui.Create("DScrollPanel", right) list:Dock(FILL) list:DockMargin(0, 6, 0, 0)
        for _, e in ipairs(state.log) do
            local row = vgui.Create("DButton", list) row:Dock(TOP) row:SetTall(22) row:SetText("")
            row.Paint = function(s, w, h)
                local current = state and math.abs(state.cs - e.cs) < 25
                if current or s:IsHovered() then surface.SetDrawColor(COL.line) surface.DrawRect(0, 0, w, h) end
                surface.SetDrawColor(COL[e.kind] or COL.text) surface.DrawRect(0, 3, 3, h - 6)
                draw.SimpleText(string.format("%+.1f", e.cs / 100), "ZCKC.Small", 8, h / 2, COL.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                draw.SimpleText(e.text, "ZCKC.Small", 48, h / 2, COL.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
            row.DoClick = function() if state then seek(e.cs - 50) state.playing = true if e.a and state.clip.actors[e.a] then state.follow = e.a end end end
        end
    end

    frame.OnKeyCodePressed = function(_, key)
        if not state then return end
        if key == KEY_SPACE then state.playing = not state.playing
        elseif key == KEY_LEFT then seek(state.cs - 100)
        elseif key == KEY_RIGHT then seek(state.cs + 100)
        elseif key == KEY_COMMA then state.playing = false seek(state.cs - 10)
        elseif key == KEY_PERIOD then state.playing = false seek(state.cs + 10) end
    end

    frame.records = left
    ask("zckc_index", target)
end

net.Receive("zckc_index", function()
    local sid, locked, n = net.ReadString(), net.ReadBool(), net.ReadUInt(5)
    local rows = {}
    for i = 1, n do
        rows[i] = {clip = net.ReadString(), t = net.ReadUInt(32), map = net.ReadString(), tag = net.ReadString(), role = net.ReadString(), other = net.ReadString(), reported = net.ReadBool()}
    end
    if not IsValid(frame) then return end
    frame.records:Clear()
    frame.note = locked and STATUS_TEXT[3] or (n == 0 and ("Nothing under \"" .. sid .. "\"" .. (sid == "mine" and IsValid(frame) and (frame.scope or "") ~= "" and " (that tab is not open to your rank)" or "") .. ".") or nil)
    for _, r in ipairs(rows) do
        local what = r.tag == "life" and (r.role == "" and r.other or "Your death, last hit by " .. r.other) or r.role == "" and r.other or r.tag == "ivi" and (r.role == "killer" and "You killed " or "Killed by ") .. r.other or "Traitor, killed by " .. r.other
        local b = button(frame.records, "", function() ask("zckc_clip", r.clip) end)
        b:Dock(TOP) b:SetTall(46) b:DockMargin(0, 0, 0, 4)
        b.Paint = function(s, w, h)
            local active = state and state.id == r.clip
            surface.SetDrawColor((active or s:IsHovered()) and COL.line or COL.panel) surface.DrawRect(0, 0, w, h)
            surface.SetDrawColor(r.tag == "ivi" and COL.bad or COL.attacker) surface.DrawRect(0, 0, 3, h)
            draw.SimpleText(what, "ZCKC.Body", 10, 6, COL.text)
            draw.SimpleText(os.date("%d %b %H:%M", r.t) .. "  " .. r.map .. (r.reported and "  reported" or ""), "ZCKC.Small", 10, 26, COL.dim)
        end
    end
end)

-- Reports filed on the open clip (sent to operators and up only).
notes = {}
net.Receive("zckc_notes", function()
    local id, reporter, n = net.ReadString(), net.ReadString(), net.ReadUInt(5)
    local list = {reporter = reporter}
    for i = 1, n do list[i] = {instance = net.ReadUInt(5), text = net.ReadString(), attacker = net.ReadString(), attackerId = net.ReadString()} end
    notes[id] = list
    if IsValid(frame) and state and state.id == id then frame:Rebuild() end
end)

-- Hooks for the death sequence (cl_life.lua): open a sequence it already holds, surface replies, mark reports.
function V.OpenSequence(id, seq)
    open()
    openClip(id, seq)
end
function V.Note(text) if IsValid(frame) then frame.note = text end end
function V.MarkReported(id, index) if state and state.id == id and index then state.reported[index] = true end end

concommand.Add("zc_killcam", function(_, _, args) open(args[1]) end)
-- Shown in the console rather than a panel, deliberately: this is a staff tool that wants copying into a ban note,
-- and it is reachable the moment the round is closed with no UI to build or maintain.
function V.ShowTape(id, raw)
    local round = string.match(id, "^tape:(.-):") or id
    -- V.Tape is created by cl_tape.lua, which the bundle appends AFTER this file, so it is looked up at CALL
    -- time and never hoisted into a local here - a `local T = V.Tape` up top would capture nil.
    local T = V.Tape
    if not T or not T.Summary or not T.Hurt then return MsgN("[Killcam] the tape decoder is not loaded") end
    local lines, marks, deaths = T.Summary(raw)
    local chunks, from, till = T.Span(raw)
    MsgN("[Killcam] round " .. round .. ": " .. marks .. " marks, " .. deaths .. " death(s)"
        .. (chunks > 0 and (", " .. chunks .. " chunk(s) covering " .. T.Clock(from) .. "-" .. T.Clock(till)) or ""))
    if deaths == 0 then
        MsgN(marks == 0 and "  nothing readable in this round's index" or "  no deaths in this round")
    end
    for _, line in ipairs(lines) do MsgN(line) end
    local hurt = T.Hurt(raw)
    if #hurt > 0 then
        MsgN("  -- damage taken --")
        for _, line in ipairs(hurt) do MsgN(line) end
    end
    -- The next thing a staff member wants after reading a death line is to look at that moment, so hand them the
    -- command for it rather than making them remember the syntax and retype the round id. Console output is
    -- deliberate here: it is copy-pasteable into a ban note, which a panel would not be.
    if deaths > 0 then MsgN("  seek a moment:  zc_killcam_round " .. round .. " <m:ss>") end
end

-- Staff only in the place that matters - the SERVER refuses a tape to anyone who may not see it
-- (sv_tapeserve K.TapeMayView), so this does not have to be trusted and deliberately does not try.
concommand.Add("zc_killcam_round", function(_, _, args)
    local id = string.Trim(args and args[1] or "")
    if id == "" then return MsgN("[Killcam] zc_killcam_round <round id>   (zc_killcam_tape on the server lists them)") end
    local when = V.Tape and V.Tape.ParseTime and V.Tape.ParseTime(args and args[2] or "")
    if args and args[2] and args[2] ~= "" and not when then
        return MsgN("[Killcam] could not read the time '" .. tostring(args[2]) .. "'. Use m:ss, or seconds.")
    end
    if when then
        V.AskMoment(id, when)
        return MsgN("[Killcam] asked for " .. id .. " at " .. V.Tape.Clock(when))
    end
    if string.sub(id, 1, 5) ~= "tape:" then id = "tape:" .. id .. ":index" end
    net.Start("zckc_clip")
    net.WriteString(id)
    net.SendToServer()
    MsgN("[Killcam] asked for " .. id)
end)


-- cl_life.lua reaches clients at the first boot after it was added; until then it is simply absent.
-- cl_life.lua and cl_tape.lua are bundled below (work/killcam/build_bundle.py).

----------------------------------------------------------------- one moment out of a round
-- `zc_killcam_round <id> <time>` answers "who was where at 2:14", which is the question a staff member reading an
-- RDM report actually has. Three hops, because that is what the format costs: the INDEX says which chunk holds the
-- moment (T.PickChunk), the CHUNK is fetched on its own, and the decode is spread across frames - cl_tape's header
-- is explicit that nothing there runs in one frame, so it is pumped from Think on a 2 ms budget and never looped
-- to completion. One lookup in flight at a time; a second command replaces the first rather than racing it.
local moment
local function say(text) MsgN("[Killcam] " .. text) end
local function askTape(id)
    net.Start("zckc_clip")
    net.WriteString(id)
    net.SendToServer()
end

local function momentIndex(raw)
    local T = V.Tape
    moment.names = {}
    for _, t in ipairs(T.Lines(raw)) do
        if t.k == "who" and t.uid then moment.names[t.uid] = t.name or ("#" .. tostring(t.uid)) end
    end
    local seq, t0 = T.PickChunk(raw, moment.cs)
    if not seq then
        moment = nil
        return say("that round's index lists no chunks, so there is nothing to seek in")
    end
    moment.seq, moment.chunkT0 = seq, t0
    askTape("tape:" .. moment.id .. ":" .. seq)
end

-- One decode slice a frame. A 2 ms budget and never a loop that must finish: cl_tape's own rule, because one
-- chunk is tens of thousands of numbers. No `goto` - the bundle has to compile under plain 5.1 as well as LuaJIT.
local function pump(m)
    local T = V.Tape
    local started, done = SysTime(), false
    while not done and SysTime() - started < 0.002 do done = not m.job:Step() end
    if not done then return end
    moment = nil
    if m.job.bad and m.job.bad[1] then return say("that chunk did not decode: " .. tostring(m.job.bad[1])) end
    say("round " .. m.id .. " at " .. T.Clock(m.cs) .. " (chunk " .. tostring(m.seq) .. ")")
    for _, line in ipairs(T.MomentLines(m.job.out, m.cs, m.chunkT0, m.names)) do MsgN(line) end
end

local pumpErr
hook.Add("Think", "ZCKillcam.TapeMoment", function()
    local m = moment
    if not m or not m.job then return end
    -- A fault in here would repeat every frame forever, so the lookup is dropped on the way out: one complaint,
    -- then silence, and the next command starts clean.
    local ok, err = pcall(pump, m)
    if ok then return end
    moment = nil
    if not pumpErr then pumpErr = true print("[Killcam] round seek: " .. tostring(err)) end
end)

-- Everything arriving under a "tape:" id lands here. An id ending in digits is a chunk; anything else is the index.
function V.TapeBlob(id, raw)
    local T = V.Tape
    if not T or not T.PickChunk then return say("the tape decoder is not loaded") end
    local n = string.match(id, ":(%d+)$")
    if n and moment and moment.seq and tostring(moment.seq) == n then
        moment.job = T.Chunk(raw)
        return
    end
    if not n and moment and moment.cs and not moment.seq then return momentIndex(raw) end
    return V.ShowTape(id, raw)
end

function V.AskMoment(id, cs)
    moment = {id = id, cs = cs}
    askTape("tape:" .. id .. ":index")
end

do -- ===== zc_killcam/cl_life.lua =====
-- Z-City killcam: the death sequence. When you die the server sends every instance you took
-- damage that life; each one replays through the attacker's eyes, slowing to quarter speed
-- around the hit. It ends by itself the moment you are alive again.
--
-- Fitted to the gamemode's death flow (read from its source, 2026-09-21):
--  * dying puts you straight into spectate; LMB/RMB change target and R cycles the view mode,
--    so the replay uses none of those and swallows them while it plays - your spectate state is
--    exactly where you left it when the replay ends;
--  * F opens the forgiveness menu for the first 5 s after death and its prompt sits at the bottom
--    of the screen, so the replay waits those 5 s (a slim banner offers it meanwhile) and never binds F.
-- Keys: G report this hit, V save, Space start / next hit, B top-down viewer, Q close.
-- PROVISIONAL(2026-09-21, the 3D replay is unseen in-engine by its author: needs the owner's eyes, ratify-by: 2026-10-05)
if not CLIENT then return end
local V = ZCKillcamView
-- replay_v1 P3: what the round viewer (cl_part_09, AFTER this block) may call. Fields, not locals: this block is at
-- Lua's 200-locals line. Rebuilt on every load, so a hot reload hands part 09 this copy's functions.
V.Life = {}
-- Where a scan of clip.events may start. A death clip is short and is still scanned from its first event (1, exactly
-- as before); a round clip (clip.round) holds thousands, so the first event at or after `cs` is found by bisection.
function V.EvFrom(clip, cs)
    if not clip.round then return 1 end
    local ev = clip.events
    local lo, hi = 1, #ev + 1
    while lo < hi do
        local mid = math.floor((lo + hi) / 2)
        if ev[mid][1] < cs then lo = mid + 1 else hi = mid end
    end
    return lo
end

local TAGS = {ivi = "Innocent hit innocent", tvt = "Traitor hit traitor", ivt = "Innocent hit traitor", tvi = "Traitor hit innocent", other = "Not a traitor round"}
local REPLY = {[0] = "Reported to staff.", [1] = "That sequence is not yours.", [2] = "That sequence is gone.", [3] = "That hit cannot be reported.", [4] = "You already reported that hit.", [5] = "Report limit reached, try again later."}
local SLOW_FROM, SLOW_TO, SLOW, GHOST_MODEL = -100, 60, 0.25, "models/player/group01/male_07.mdl"
-- Slack on top of a replay's own expected length before the wall-clock failsafe takes the screen back regardless of
-- what the state machine thinks. Wide enough that nothing normal ever reaches it.
local WALL = 30
-- Which way the legs sit against the aim. See the note at the SetAngles call in pose(): the sign of aim_yaw is the
-- one thing about the new body-state replay that cannot be checked from outside the game, so it is switchable in
-- console instead of being a constant that needs a redeploy to correct.
-- Kept on the module table, NOT in a local: this file sits inside one chunk in the shipped bundle and is at Lua's
-- ceiling of 200 locals per function. One more file-scope local and the whole client payload fails to load - which
-- test_bundleload.py catches, but only because it EXECUTES the bundle rather than just compiling it.
CreateClientConVar("zc_killcam_feet", "1", true, false,
    "Replay body yaw: 1 feet behind the aim (default), -1 the other way if the legs look backwards, 0 body drawn straight at the aim (pre-2026-09-22)")
V.FeetCV = GetConVar("zc_killcam_feet")
V.Tags = TAGS

local povGun = CreateClientConVar("zc_killcam_povgun", "1", true, false, "Show the attacker's own body, arms and weapon in the first-person replay")
-- weapons.Get merges the base classes in (RHPos, WorldPos ... mostly live on homigrad_base);
-- weapons.GetStored would only show what the weapon file itself declares. It copies, so cache.
local weaponTables = {}
local function weaponTable(class)
    if not class or class == "" then return nil end
    local t = weaponTables[class]
    if t == nil then
        t = weapons.Get(class)
        if t then weaponTables[class] = t end -- a class missing during loading must remain retryable
    end
    return t or nil
end
-- How a weapon is held depends on the base it comes from (owner, 2026-09-21: "weapon orientation is sometimes wrong" -
-- everything was being held with homigrad_base's firearm maths). Read from the US1 source:
--   "gun"    homigrad_base                  eye -> hand -> gun, see heldTransform
--   "melee"  weapon_melee (31 weapons)      WorldModelReal at LocalToWorld(HoldPos, HoldAng, eye, aim)   (SWEP:ModelAnim)
--   "tpik"   weapon_tpik_base (grenades...) WorldModelReal at eye + F*(HoldPos.x-4) + R*HoldPos.y + U*HoldPos.z, aim turned by HoldAng
--   "item"   the rest (bandages, medkits, food: weapon_base) WorldModel on the right hand bone + offsetVec / offsetAng
-- Melee swings and grenade throws use recorded action events; generic items retain their idle hold.
local families = {}
local function heldFamily(class)
    local known = families[class]
    if known then return known end
    local family, at = "item", class
    for _ = 1, 8 do
        if at == "homigrad_base" then family = "gun" break end
        if at == "weapon_melee" then family = "melee" break end
        if at == "weapon_tpik_base" then family = "tpik" break end
        local stored = at and weapons.GetStored(at)
        if not stored then return family end -- do not cache an incomplete inheritance chain
        at = stored.Base ~= at and stored.Base or nil
        if not at then break end
    end
    families[class] = family
    return family
end
-- The gamemode never shows SWEP.WorldModel when a weapon has WorldModelFake: that is the model it actually draws.
local function heldModel(class, ragged)
    local w = weaponTable(class)
    if not w then return end
    local family = heldFamily(class)
    -- G1 (killcam_polish, 2026-09-25): util.IsValidModel answers false on the CLIENT for a model the SERVER has not
    -- precached (wiki: "Returns false clientside if the model is not precached by the server"), and this server carries
    -- 520 weapons; the file is on disk all the same and ClientsideModel loads it. A model on disk counts. When the fake
    -- (high-poly) model is still skipped, the console says so once per class (zc_killcam_impact_print).
    local function valid(model) return isstring(model) and model ~= "" and (util.IsValidModel(model) or file.Exists(model, "GAME")) end
    -- The resting ragdoll carries the ordinary model, not the separate animated
    -- hands rig used by melee/TPIK weapons while standing.
    local real = not ragged and (family == "melee" or family == "tpik") and w.WorldModelReal
    local model = valid(real) and real or valid(w.WorldModelFake) and w.WorldModelFake or valid(w.WorldModel) and w.WorldModel
    if w.WorldModelFake and model ~= w.WorldModelFake and V.ImpactPrint and V.ImpactPrint:GetBool() then -- G1
        V.SaidModel = V.SaidModel or {}
        if not V.SaidModel[class] then
            V.SaidModel[class] = true
            MsgN(string.format("[Killcam] %s: fake world model %s skipped (valid=%s onDisk=%s), drawing %s", class, tostring(w.WorldModelFake),
                tostring(util.IsValidModel(w.WorldModelFake)), tostring(file.Exists(tostring(w.WorldModelFake), "GAME")), tostring(model)))
        end
    end
    if not model then return nil, w end
    if w.WorldModelFake and model ~= w.WorldModelFake then
        -- A valid ordinary fallback must not inherit the missing fake model's
        -- scale, bodygroups or FakePos/FakeAng transform. Never edit the SWEP cache.
        w = table.Copy(w)
        w.WorldModelFake = nil
    end
    return model, w
end

-- Where the gamemode holds a weapon, replicated from homigrad_base (SWEP:PosAngChanges then
-- SWEP:WorldModel_Transform, read from the US1 source 2026-09-21): the right hand sits at a per-weapon
-- offset FROM THE EYE along the aim, and the gun hangs off the hand. Nothing here follows the
-- player animation - the arms are then bent to reach (see solveArm).
-- `motion` (optional) carries what changes from moment to moment - see gunMotion: walk bob, idle sway, the sprint's
-- relaxed pitch. Left out on purpose: bipod rest, recoil's per-weapon shake. Aiming down sights moves the CAMERA, not
-- the gun (see eyeOf).
local RH_POS, WORLD_POS, WORLD_ANG = Vector(7, -7, 5), Vector(13, -0.3, 3.4), Angle(5, 0, 180)
local function heldTransform(w, eyePos, pitch, yaw, motion, rest)
    local aim = Angle(pitch, yaw, 0)
    local addPos, addAng = w.AdditionalPos or vector_origin, w.AdditionalAng or angle_zero
    local gunPitch = pitch
    if motion then
        addPos, addAng = addPos + motion.pos, addAng + motion.ang
        gunPitch = pitch * (1 - motion.relax) -- sh_worldmodel.lua:180: wepang.p approaches 0 by wepang.p * self.pitch
    end
    local handPos, handAng = LocalToWorld((w.RHPos or RH_POS) + addPos, addAng, eyePos - aim:Up(), Angle(gunPitch, yaw, 90))
    handAng.r = handAng.r + 90
    if rest then handPos = LocalToWorld(rest.back * rest.lerp, angle_zero, LerpVector(rest.lerp, handPos, rest.pos), handAng) end -- on its bipod: see restPoint
    handPos = handPos + handAng:Up()
    local pos, ang = LocalToWorld(w.WorldPos or WORLD_POS, (w.WorldAng or WORLD_ANG) + (w.WorldAng2 or angle_zero), handPos, handAng)
    ang:RotateAroundAxis(ang:Forward(), 180)
    local basePos = pos -- before the FakePos shift: SWEP.ZoomPos is measured from here (SWEP:GetZoomPos undoes FakePos first)
    if w.WorldModelFake then pos, ang = LocalToWorld(w.FakePos or vector_origin, w.FakeAng or angle_zero, pos, ang) end
    return pos, ang, handPos, handAng, basePos
end

-- The player's own switch. Userinfo: the server reads it before it sends a death replay or the round's highlight.
CreateClientConVar("zc_killcam_show", "1", true, true, "Show killcams: your death replay and the round's best moment (0 = never)", 0, 1)
local function listSetting() -- Z-City's settings menu (Esc > Settings) builds itself from hg.settings.tbl each time it opens
    if hg and hg.settings and hg.settings.AddOpt then hg.settings:AddOpt("Gameplay", "zc_killcam_show", "Killcams (death replay & round highlight)") end
end
listSetting()
hook.Add("InitPostEntity", "ZCKillcam.Setting", listSetting)
CreateClientConVar("zc_killcam_autoplay", "1", true, false, "Legacy setting; death replays now take control and start automatically", 0, 1)
local wasAlive, deathClockReady = true, false
local deathPending, deathPendingUntil = false, 0
local L -- the running sequence; declared here so the death-claim hook can share its lifetime
hook.Add("Think", "ZCKillcam.LifeDeathClock", function()
    local me = LocalPlayer()
    if not IsValid(me) then return end
    local alive = me:Alive()
    if not deathClockReady then
        deathClockReady, wasAlive = true, alive
        return
    end
    if wasAlive and not alive then
        local now = RealTime()
        local show = GetConVar("zc_killcam_show")
        deathPending = show ~= nil and show:GetBool()
        deathPendingUntil = deathPending and (now + 5) or 0
        if deathPending then
            local menu = rawget(_G, "hmcdEndMenu")
            if IsValid(menu) then menu:SetVisible(false) end
        end
    end
    if alive then
        V.ObserverLife = nil
        deathPending, deathPendingUntil = false, 0
    elseif deathPending then
        local show = GetConVar("zc_killcam_show")
        if show == nil or not show:GetBool() or RealTime() >= deathPendingUntil or (L and not L.highlight) then
            deathPending, deathPendingUntil = false, 0
        end
    end
    wasAlive = alive
end)

----------------------------------------------------------------- shared: report box and replies
local REASONS = {"No reason given", "They shot first", "Mistaken identity", "Revenge for an earlier round"}
function V.ReportDialog(id, index, inst, onClose)
    local style = V.LifeStyle
    local box = vgui.Create("DFrame")
    box:SetSize(math.max(ScreenScale(230), 560), 250) box:Center() box:SetTitle("") box:ShowCloseButton(false) box:SetDraggable(false) box:MakePopup()
    box.Paint = function(_, w, h)
        surface.SetDrawColor(0, 0, 0, 120) surface.DrawRect(-ScrW(), -ScrH(), ScrW() * 2, ScrH() * 2)
        surface.SetDrawColor(28, 28, 28, 245) surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(style.edge) surface.DrawOutlinedRect(0, 0, w, h, 2)
        draw.SimpleText("Report this hit to staff", "ZCKC.LifeHead", 16, 10, style.text)
        draw.SimpleText(string.format("%s   ·   %s   ·   %d hit%s, %s dmg   ·   %.0fs before your death", tostring(inst.attacker), (string.gsub(inst.wep or "unknown weapon", "^weapon_", "")), inst.hits or 0, inst.hits == 1 and "" or "s", tostring(inst.dmg or 0), inst.ago or 0), "ZCKC.LifeSmall", 16, 48, style.dim)
        draw.SimpleText("Staff get this replay from the attacker's view, with your note.", "ZCKC.LifeSmall", 16, 68, style.dim)
    end
    local function flat(button, colour, filled)
        button:SetFont("ZCKC.LifeSmall") button:SetTextColor(filled and style.text or colour)
        button.Paint = function(self, w, h)
            if filled then surface.SetDrawColor(155, 0, 0, self:IsHovered() and 255 or 220) surface.DrawRect(0, 0, w, h)
            else
                surface.SetDrawColor(60, 60, 60, self:IsHovered() and 200 or 90) surface.DrawRect(0, 0, w, h)
                surface.SetDrawColor(colour) surface.DrawOutlinedRect(0, 0, w, h, 1)
            end
        end
    end
    local entry = vgui.Create("DTextEntry", box)
    entry:SetPos(16, 134) entry:SetSize(box:GetWide() - 32, 56) entry:SetMultiline(true) entry:SetFont("ZCKC.LifeSmall")
    entry:SetPlaceholderText("I was holding a medkit and never aimed at them")
    entry:SetPaintBackground(false) entry:SetTextColor(style.text) entry:SetCursorColor(style.text)
    entry.AllowInput = function(self) return #self:GetValue() >= 240 end
    local paintEntry = entry.Paint
    entry.Paint = function(self, w, h)
        surface.SetDrawColor(18, 18, 18, 255) surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(60, 60, 60, 255) surface.DrawOutlinedRect(0, 0, w, h, 1)
        paintEntry(self, w, h)
    end
    local x = 16
    for _, reason in ipairs(REASONS) do
        local chip = vgui.Create("DButton", box)
        chip:SetText(reason) flat(chip, style.dim)
        surface.SetFont("ZCKC.LifeSmall")
        chip:SetPos(x, 98) chip:SetSize(surface.GetTextSize(reason) + 18, 24)
        chip.DoClick = function() entry:SetText(reason .. ". ") entry:RequestFocus() entry:SetCaretPos(#entry:GetValue()) end
        x = x + chip:GetWide() + 6
    end
    local count = vgui.Create("DLabel", box)
    count:SetPos(16, 206) count:SetSize(200, 20) count:SetFont("ZCKC.LifeSmall") count:SetTextColor(style.dim)
    count.Think = function(self) self:SetText(#entry:GetValue() .. " / 240") end
    local send = vgui.Create("DButton", box)
    send:SetText("Send report") flat(send, style.text, true) send:SetSize(120, 28) send:SetPos(box:GetWide() - 136, 204)
    local cancel = vgui.Create("DButton", box)
    cancel:SetText("Cancel") flat(cancel, style.dim) cancel:SetSize(90, 28) cancel:SetPos(box:GetWide() - 232, 204)
    cancel.DoClick = function() box:Close() end
    send.DoClick = function()
        V.lastReport = {id = id, index = index}
        net.Start("zckc_report") net.WriteString(id) net.WriteUInt(index, 5) net.WriteString(string.sub(entry:GetValue(), 1, 240)) net.SendToServer()
        box:Close()
    end
    box.OnClose = function() if onClose then onClose() end end
    box.OnRemove = box.OnClose
    entry:RequestFocus()
    return box
end

local function say(text)
    if L then L.note, L.noteUntil = text, RealTime() + 4 end
    if V.Note then V.Note(text) end
end
net.Receive("zckc_report", function()
    local id, code = net.ReadString(), net.ReadUInt(3)
    say(REPLY[code] or "The report was not accepted.")
    local last = V.lastReport
    if code == 0 and last and last.id == id then
        if L and L.id == id then L.reported[last.index] = true end
        if V.MarkReported then V.MarkReported(id, last.index) end
    end
end)
net.Receive("zckc_save", function()
    local _, code = net.ReadString(), net.ReadUInt(3)
    if L and code == 0 then L.saved = true end
    say(code == 0 and "Saved to your records (zc_killcam)." or "Nothing to save.")
end)

----------------------------------------------------------------- ghosts
local scoping = false -- true while the scope's own picture is rendered: ghosts must not run their arm IK for that pass
local strip -- removes what is fitted to a ghost's gun; defined with the attachments below
local punchOver -- defined further down, used by the bone callback
local function clearGhosts()
    V.Gore.Clear()
    if L then L.goreErr = nil end
    if V.StopReplaySounds then V.StopReplaySounds() end
    if not L or not L.ghosts then return end
    for _, g in pairs(L.ghosts) do
        if IsValid(g) then
            strip(g)
            if IsValid(g.zcGun) then g.zcGun:Remove() end
            if IsValid(g.zcExchange) then g.zcExchange:Remove() end
            g.zcExchange, g.zcExchangeRetry = nil, nil
            if IsValid(g.zcRag) then g.zcRag:Remove() end
            if IsValid(g.zcDouble) then g.zcDouble:Remove() end
            for _, a in ipairs(g.zcAccess or {}) do if IsValid(a) then a:Remove() end end
            g:Remove()
        end
    end
    L.ghosts = nil
end

-- The model they actually wore; never the engine's bare figure, and never a stand-in borrowed from whoever happens to
-- be online now (owner, 2026-09-21). A clip recorded before the appearance was captured gets the mannequin and is
-- MARKED as unknown, because a moderation tool that quietly dresses the accused in somebody else's clothes is worse
-- than one that admits it does not know.
local function modelFor(actor)
    if actor.m and actor.m ~= "" and actor.m ~= "models/player.mdl" and util.IsValidModel(actor.m) then return actor.m end
    return GHOST_MODEL, true
end

-- Model alone is not appearance: the clothing on Z-City's player packs is a bodygroup, and every player carries their
-- own colour. The engine reads that colour through the PlayerColor material proxy, which calls GetPlayerColor() on
-- whatever entity is being drawn - so a clientside body is tinted by giving it that method.
local function wear(ent, skin, groups, colour, subs) -- `dress` further down is the gun's attachments, not the body's clothes
    if not IsValid(ent) then return end
    ent:SetSkin(skin or 0)
    if ent.GetNumBodyGroups then
        for i = 0, ent:GetNumBodyGroups() - 1 do ent:SetBodygroup(i, 0) end
    end
    ent:SetSubMaterial()
    if groups then
        for i = 1, #groups do ent:SetBodygroup(i - 1, groups[i]) end -- recorded 0-based, stored 1-based
    end
    if subs then -- their clothes and their face: {slot, material path} pairs, the slot already 0-based
        for i = 1, #subs do
            local s = subs[i]
            if istable(s) and isnumber(s[1]) and isstring(s[2]) then ent:SetSubMaterial(s[1], s[2]) end
        end
    end
    if colour then
        local v = Vector(colour[1] / 255, colour[2] / 255, colour[3] / 255)
        ent.GetPlayerColor = function() return v end
    end
end

-- Hats and packs. The gamemode spawns these client side out of `hg.Accessories` keyed by name, so the names are the
-- whole record and the same table puts them back. Its own RenderAccessories is NOT called: that function is full of
-- first-person, spectate and transmit logic that means nothing for a replay ghost, and the killcam reads the
-- gamemode's data without ever running its behaviour. Parented, so they follow the body; drawDress hides them with it.
local function accessorise(g, names)
    if not names or not (hg and istable(hg.Accessories)) then return end
    for i = 1, #names do
        local d = hg.Accessories[names[i]]
        local model = istable(d) and d.model
        if isstring(model) and util.IsValidModel(model) then
            local a = V.OwnReplayEntity(ClientsideModel(model, RENDERGROUP_BOTH))
            if IsValid(a) then
                a:SetNoDraw(true)
                a:SetMoveType(MOVETYPE_NONE) -- a parented child needs this before its bone id counts
                a.zcBone, a.zcHost = d.bone, g -- kept so drawDress can re-seat it on the ragdoll when the player goes down
                a:SetParent(g, d.bone and g:LookupBone(d.bone) or -1) -- LookupBone gives NO value on a miss: hang it off the body
                if d.bonemerge then a:AddEffects(EF_BONEMERGE) end
                if isnumber(d.skin) then a:SetSkin(d.skin) end -- their `skin` may be a function of the wearer; only a plain one is ours to use
                if isstring(d.bodygroups) then a:SetBodyGroups(d.bodygroups) end
                if isstring(d.SubMat) then a:SetSubMaterial(0, d.SubMat) end
                if d.bSetColor and g.GetPlayerColor then a:SetColor(g:GetPlayerColor():ToColor()) end
                g.zcAccess = g.zcAccess or {}
                g.zcAccess[#g.zcAccess + 1] = a
            end
        end
    end
end

local holdWeapon -- defined with the weapon code further down
local function load(index)
    clearGhosts()
    local inst = L.seq.instances[index]
    if not inst then L.over, L.overAt = true, RealTime() return end
    L.index, L.inst, L.clip = index, inst, V.Prepare(inst.clip)
    L.cs = L.clip.first
    -- Every hit starts from a clean view. All of these DECAY over time instead of being written each frame, so without
    -- this the last shot's recoil kick, the red hit flash, the aim zoom and the slow-motion ramp all bleed across the
    -- cut into the next hit. L.note is deliberately left alone: it is feedback about the whole sequence ("Saved to your
    -- records"), not about this hit, and clearing it would swallow a message the player just asked for.
    L.rate, L.zoom, L.kick = 1, 0, 0
    L.hitFlash, L.hitDmg, L.hitGroup = 0, nil, nil
    L.bullet = nil -- nil = this hit's killing round has not been looked for yet; false = looked for, there isn't one
    L.ghosts = {}
    for i, actor in ipairs(L.clip.actors) do
        -- The attacker gets a body as well: the gamemode's first person IS the player's own body and
        -- world weapon seen from the eyes, so that is what the replay shows (head hidden, as it would be).
        if i ~= L.clip.pov or povGun:GetBool() then
            local model, guessed = modelFor(actor)
            local g = V.OwnReplayEntity(ClientsideModel(model, RENDERGROUP_OPAQUE))
            if IsValid(g) then
                -- The mannequin wears nobody's clothes: skin, bodygroup ids and material slots only mean something on
                -- the recorded model. Colour is not model-specific, so it rides either way.
                wear(g, not guessed and actor.sk or nil, not guessed and actor.bg or nil, actor.col, not guessed and actor.sm or nil)
                if not guessed then
                    local okA, errA = pcall(accessorise, g, actor.ac)
                    if not okA then print("[Killcam] accessories skipped for a ghost: " .. tostring(errA)) end
                end
                g:SetNoDraw(true) g:SetIK(false) g:SetPlaybackRate(0)
                g:SetLOD(0) -- a lower LOD sets up fewer bones, and writing a finger that is not being set up is an error ("Bone is unwriteable")
                g:AddCallback("BuildBonePositions", function(self)
                    if self.zcFlat or scoping then V.Gore.Bones(self) return end
                    if self.zcPunching and not self.zcNoDouble then
                        local okP, errP = pcall(punchOver, self)
                        if not okP then self.zcNoDouble = true print("[Killcam] punch overlay disabled for a ghost: " .. tostring(errP)) end
                    end
                    -- where the neck sits on this body, relative to the body: pose() hangs the eye off it (no forced bone setup)
                    local neck = self:LookupBone("ValveBiped.Bip01_Neck1")
                    local neckM = neck and self:GetBoneMatrix(neck)
                    if neckM then self.zcNeckPos, self.zcNeckAng = WorldToLocal(neckM:GetTranslation(), neckM:GetAngles(), self:GetPos(), self:GetAngles()) end
                    if self.zcItem and not self.zcCarry and IsValid(self.zcGun) then -- carried in the hand, not aimed: see heldFamily
                        local hand = self:LookupBone("ValveBiped.Bip01_R_Hand")
                        local handM = hand and self:GetBoneMatrix(hand)
                        local w = self.zcWeapon
                        if handM and w then
                            local at, turn = LocalToWorld(w.offsetVec or vector_origin, w.offsetAng or angle_zero, handM:GetTranslation(), handM:GetAngles())
                            self.zcGun:SetPos(at) self.zcGun:SetAngles(turn)
                            self.zcGun:SetRenderOrigin(at) self.zcGun:SetRenderAngles(turn)
                        end
                        V.Gore.Bones(self)
                        return
                    end
                    if self.zcNoIK then V.Gore.Bones(self) return end
                    local ok, err = pcall(holdWeapon, self) -- runs every frame for every ghost: one failure turns it off for that ghost, it never spams
                    if not ok then self.zcNoIK = true print("[Killcam] arm IK disabled for a ghost: " .. tostring(err)) end
                    V.Gore.Bones(self)
                end)
                if i == L.clip.pov then
                    g.zcPov = true
                    local head = g:LookupBone("ValveBiped.Bip01_Head1")
                    if head then g:ManipulateBoneScale(head, Vector(0.01, 0.01, 0.01)) end
                end
                L.ghosts[i] = g
            end
        end
    end
end
-- replay_v1 P3 exports (cl_part_09). A round clip has no pov at load, so every actor gets a ghost above.
V.Life.load, V.Life.clear, V.Life.wear, V.Life.modelFor = load, clearGhosts, wear, modelFor
function V.Life.State() return L end
function V.Life.Set(l) L = l end
-- First person in a round follows whoever is chosen, so the pov - and the hidden head that goes with it - moves.
function V.Life.SetPov(index)
    if not L or not L.clip or L.clip.pov == index then return end
    local function head(ent, small)
        if not IsValid(ent) then return end
        local bone = ent:LookupBone("ValveBiped.Bip01_Head1") -- no value on a miss
        if bone then ent:ManipulateBoneScale(bone, small and Vector(0.01, 0.01, 0.01) or Vector(1, 1, 1)) end
    end
    local old = L.ghosts and L.ghosts[L.clip.pov or 0]
    if IsValid(old) then old.zcPov = nil head(old, false) head(old.zcRag, false) end
    L.clip.pov = index
    local g = L.ghosts and L.ghosts[index or 0]
    if IsValid(g) then g.zcPov = true head(g, true) head(g.zcRag, true) end
end

-- Punches over moving legs. The game plays a punch as a GESTURE layered over the walk; a ClientsideModel has no layers, so a
-- hidden double of the body plays the punch and its upper body is carried onto the ghost's pelvis, bone by bone, inside the
-- ghost's own bone callback. The legs keep whatever the ghost was doing.
]========], 2)