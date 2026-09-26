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
-- UI cohesion U4 (2026-09-26): this is an OLDER standalone copy; the viewer (zc_killcam/viewer_parts, cl_part_03..08)
-- carries the current one. It is only sent to clients while the server boots, so it may run before the viewer - and
-- then it must not define what the viewer owns: the convars zc_killcam_povgun / _autoplay / _fov (the first
-- definition wins the help text, which is how the two autoplay descriptions came to contradict each other) and the
-- ZCKC.Life* fonts. It reads those convars by name, tolerating their absence. After the viewer it does nothing.
ZCKillcamView = ZCKillcamView or {}
local V = ZCKillcamView
if V.Life then return end -- the viewer is loaded: never replace its hooks with this copy's
local function setting(name, fallback) -- a convar the viewer defines, read by name (nil until the viewer has run)
    local cv = GetConVar(name)
    if not cv then return fallback end
    if isbool(fallback) then return cv:GetBool() end
    return cv:GetFloat()
end

local TAGS = {ivi = "Innocent hit innocent", tvt = "Traitor hit traitor", ivt = "Innocent hit traitor", tvi = "Traitor hit innocent", other = "Not a traitor round"}
local REPLY = {[0] = "Reported to staff.", [1] = "That sequence is not yours.", [2] = "That sequence is gone.", [3] = "That hit cannot be reported.", [4] = "You already reported that hit.", [5] = "Report limit reached, try again later."}
local SLOW_FROM, SLOW_TO, SLOW, GHOST_MODEL = -100, 60, 0.25, "models/player/group01/male_07.mdl"
V.Tags = TAGS

-- weapons.Get merges the base classes in (RHPos, WorldPos ... mostly live on homigrad_base);
-- weapons.GetStored would only show what the weapon file itself declares. It copies, so cache.
local weaponTables = {}
local function weaponTable(class)
    if not class or class == "" then return nil end
    local t = weaponTables[class]
    if t == nil then
        t = weapons.Get(class) or false
        weaponTables[class] = t
    end
    return t or nil
end
-- The gamemode never shows SWEP.WorldModel when a weapon has WorldModelFake: that is the model it actually draws.
local function heldModel(class)
    local w = weaponTable(class)
    local model = w and (w.WorldModelFake or w.WorldModel)
    return isstring(model) and model ~= "" and util.IsValidModel(model) and model or nil, w
end

-- Where the gamemode holds a weapon, replicated from homigrad_base (SWEP:PosAngChanges then
-- SWEP:WorldModel_Transform, read from the US1 source 2026-09-21): the right hand sits at a per-weapon
-- offset FROM THE EYE along the aim, and the gun hangs off the hand. Nothing here follows the
-- player animation - the arms are then bent to reach (see solveArm).
-- Left out on purpose: sway, sprint lowering, bipod rest, aim-down-sights (not recorded yet).
local RH_POS, WORLD_POS, WORLD_ANG = Vector(7, -7, 5), Vector(13, -0.3, 3.4), Angle(5, 0, 180)
local function heldTransform(w, eyePos, pitch, yaw)
    local aim = Angle(pitch, yaw, 0)
    local handPos, handAng = LocalToWorld((w.RHPos or RH_POS) + (w.AdditionalPos or vector_origin), w.AdditionalAng or angle_zero, eyePos - aim:Up(), Angle(pitch, yaw, 90))
    handAng.r = handAng.r + 90
    handPos = handPos + handAng:Up()
    local pos, ang = LocalToWorld(w.WorldPos or WORLD_POS, (w.WorldAng or WORLD_ANG) + (w.WorldAng2 or angle_zero), handPos, handAng)
    ang:RotateAroundAxis(ang:Forward(), 180)
    if w.WorldModelFake then pos, ang = LocalToWorld(w.FakePos or vector_origin, w.FakeAng or angle_zero, pos, ang) end
    return pos, ang, handPos, handAng
end

local FORGIVE_WINDOW = 5 -- seconds the gamemode's forgiveness prompt owns the bottom of the screen and the F key

local deathAt, wasAlive = 0, true
hook.Add("Think", "ZCKillcam.LifeDeathClock", function()
    local me = LocalPlayer()
    if not IsValid(me) then return end
    local alive = me:Alive()
    if wasAlive and not alive then deathAt = RealTime() end
    wasAlive = alive
end)

local L -- the running sequence: {id, seq, index, cs, clip, ghosts, note, noteUntil, saved, over}

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
local function clearGhosts()
    if not L or not L.ghosts then return end
    for _, g in pairs(L.ghosts) do
        if IsValid(g) then
            if IsValid(g.zcGun) then g.zcGun:Remove() end
            if IsValid(g.zcRag) then g.zcRag:Remove() end
            g:Remove()
        end
    end
    L.ghosts = nil
end

local function modelFor(actor)
    if actor.m and actor.m ~= "" and util.IsValidModel(actor.m) then return actor.m end -- the model they actually wore
    if actor.name then
        for _, p in ipairs(player.GetAll()) do if p:Nick() == actor.name and p:GetModel() and p:GetModel() ~= "" then return p:GetModel() end end
    end
    return GHOST_MODEL
end

local holdWeapon -- defined with the weapon code further down
local function load(index)
    clearGhosts()
    local inst = L.seq.instances[index]
    if not inst then L.over, L.overAt = true, RealTime() return end
    L.index, L.inst, L.clip = index, inst, V.Prepare(inst.clip)
    L.cs = L.clip.first
    L.ghosts = {}
    for i, actor in ipairs(L.clip.actors) do
        -- The attacker gets a body as well: the gamemode's first person IS the player's own body and
        -- world weapon seen from the eyes, so that is what the replay shows (head hidden, as it would be).
        if i ~= L.clip.pov or setting("zc_killcam_povgun", true) then
            local g = ClientsideModel(modelFor(actor), RENDERGROUP_OPAQUE)
            if IsValid(g) then
                g:SetNoDraw(true) g:SetIK(false) g:SetPlaybackRate(0)
                g:AddCallback("BuildBonePositions", function(self)
                    if self.zcFlat or self.zcNoIK then return end
                    local ok, err = pcall(holdWeapon, self) -- runs every frame for every ghost: one failure turns it off for that ghost, it never spams
                    if not ok then self.zcNoIK = true print("[Killcam] arm IK disabled for a ghost: " .. tostring(err)) end
                end)
                if i == L.clip.pov then
                    local head = g:LookupBone("ValveBiped.Bip01_Head1")
                    if head then g:ManipulateBoneScale(head, Vector(0.01, 0.01, 0.01)) end
                end
                L.ghosts[i] = g
            end
        end
    end
end

local function stop()
    if L and IsValid(L.dialog) then L.dialog:Remove() end -- a popup left behind would hold the mouse over live play
    clearGhosts()
    L = nil
end
-- This file is hot-reloaded on the live server: the copy being replaced still owns its ghosts, so it is told to let go first.
if V.StopLife then pcall(V.StopLife) end
V.StopLife = stop

-- R1(b): offers a blob held by net.Receive("zckc_life") below (arrived while alive) at the next death/spectate
-- entry, instead of it being lost. State lives on V, not a new file-scope local - see the ceiling note up top.
hook.Add("Think", "ZCKillcam.LifePendingConsume", function()
    local pending = V.PendingLife
    if not pending then return end
    if RealTime() - pending.at > 90 then
        V.PendingLife = nil
        net.Start("zckc_life_drop") net.SendToServer() -- R7: so K.Drops.respawned is a real count, not a guess
        return
    end
    if pending.seq.map ~= game.GetMap() then V.PendingLife = nil return end
    if L then return end -- something is already playing (a fresh arrival, most likely) - do not step on it
    local me = LocalPlayer()
    if not IsValid(me) or me:Alive() then return end
    if V.PendingLifeFor == deathAt then return end -- already offered for this death
    V.PendingLifeFor = deathAt
    V.PendingLife = nil
    stop()
    L = {id = pending.id, seq = pending.seq, reported = {}, waiting = true, startAt = math.max(RealTime() + 1, deathAt + FORGIVE_WINDOW)}
end)

-- The weapon an actor held at this moment. Swapped when they switch.
local function arm(g, clip, wep)
    if g.zcGunId == wep then return end
    g.zcGunId = wep
    if IsValid(g.zcGun) then g.zcGun:Remove() end
    g.zcGun, g.zcWeapon, g.zcFingers = nil, nil, nil
    if V.Unarmed(clip, wep) then return end
    local model, w = heldModel(clip.weaponName[wep])
    if not model then return end
    local gun = ClientsideModel(model, RENDERGROUP_OPAQUE)
    if not IsValid(gun) then return end
    if w.WorldModelFake then
        if w.FakeScale then gun:SetModelScale(w.FakeScale, 0) end
        if w.FakeBodyGroups then gun:SetBodyGroups(w.FakeBodyGroups) end
        local idle = gun:LookupSequence(w.AnimList and w.AnimList.idle or "base_idle")
        if idle and idle >= 0 then gun:ResetSequence(idle) end
    end
    g.zcGun, g.zcWeapon = gun, w
end

-- Arms are bent onto the weapon with the gamemode's own two-bone solver, the way its TPIK does it
-- (hg.Solve2PartIK + hg.bone_apply_matrix, cl_tpik.lua / cl_bones.lua). Runs inside BuildBonePositions.
local ARM = {
    [-1] = {"ValveBiped.Bip01_R_UpperArm", "ValveBiped.Bip01_R_Forearm", "ValveBiped.Bip01_R_Hand"},
    [1] = {"ValveBiped.Bip01_L_UpperArm", "ValveBiped.Bip01_L_Forearm", "ValveBiped.Bip01_L_Hand"},
}
local function solveArm(g, sign, targetPos, targetAng)
    local names = ARM[sign]
    local upper, fore, hand, head = g:LookupBone(names[1]), g:LookupBone(names[2]), g:LookupBone(names[3]), g:LookupBone("ValveBiped.Bip01_Head1")
    if not (upper and fore and hand and head) then return end
    local upperM, foreM, handM, headM = g:GetBoneMatrix(upper), g:GetBoneMatrix(fore), g:GetBoneMatrix(hand), g:GetBoneMatrix(head)
    if not (upperM and foreM and handM and headM) then return end
    local shoulder = upperM:GetTranslation()
    local len0, len1 = shoulder:Distance(foreM:GetTranslation()), foreM:GetTranslation():Distance(handM:GetTranslation())
    handM:SetTranslation(targetPos)
    handM:SetAngles(targetAng)
    local elbow, wrist, upperAng, foreAng = hg.Solve2PartIK(shoulder, targetPos, len0, len1, upperM, handM, sign, headM, headM:GetAngles(), targetAng)
    if not elbow then return end
    foreAng:RotateAroundAxis(foreAng:Forward(), -45)
    upperM:SetAngles(upperAng)
    foreM:SetAngles(foreAng)
    foreM:SetTranslation(elbow)
    handM:SetTranslation(wrist)
    hg.bone_apply_matrix(g, upper, upperM, fore)
    hg.bone_apply_matrix(g, fore, foreM, hand)
    hg.bone_apply_matrix(g, hand, handM)
end

function holdWeapon(g)
    local gun, w = g.zcGun, g.zcWeapon
    if not g.zcHandPos or not IsValid(gun) or not w or not (hg and hg.Solve2PartIK and hg.bone_apply_matrix) then return end
    if w.WorldModelFake then
        -- These models carry the hands' bones, posed for this weapon: hands and fingers are copied from them.
        gun:SetupBones()
        local rh, lh = gun:LookupBone("ValveBiped.Bip01_R_Hand"), gun:LookupBone("ValveBiped.Bip01_L_Hand")
        local rhM, lhM = rh and gun:GetBoneMatrix(rh), lh and gun:GetBoneMatrix(lh)
        if rhM then solveArm(g, -1, rhM:GetTranslation(), rhM:GetAngles()) end
        if lhM then solveArm(g, 1, lhM:GetTranslation(), lhM:GetAngles()) end
        local map = g.zcFingers
        if not map then
            map = {}
            for bone = 0, gun:GetBoneCount() - 1 do
                local name = gun:GetBoneName(bone)
                if name and string.find(name, "Finger", 1, true) and ((rhM and string.find(name, "_R_", 1, true)) or (lhM and string.find(name, "_L_", 1, true))) then
                    local mine = g:LookupBone(name)
                    if mine then map[#map + 1] = {bone, mine} end
                end
            end
            g.zcFingers = map
        end
        for _, pair in ipairs(map) do
            local m = gun:GetBoneMatrix(pair[1])
            if m then g:SetBoneMatrix(pair[2], m) end
        end
    else
        -- SWEP:SetHandPos, the branch for ordinary world models.
        local base, ang = g.zcHandPos - g.zcHandAng:Up(), g.zcHandAng
        local rhPos, rhAng = LocalToWorld(w.RHPosOffset or vector_origin, w.RHAngOffset or angle_zero, base, ang)
        solveArm(g, -1, rhPos, rhAng)
        local lhBase = Angle(ang.p, ang.y, ang.r)
        lhBase:RotateAroundAxis(ang:Forward(), -90)
        local lhPos, lhAng = LocalToWorld(w.LHPos or Vector(15, 0, -4), w.LHAng or Angle(-110, -90, -90), base, lhBase)
        lhPos, lhAng = LocalToWorld(w.LHPosOffset or vector_origin, w.LHAngOffset or angle_zero, lhPos, lhAng)
        solveArm(g, 1, lhPos, lhAng)
    end
end

-- Player models pick their animation set by hold type (idle_ar2, run_pistol, cwalk_smg1 ...).
local function holdType(clip, wep)
    if V.Unarmed(clip, wep) then return "all" end
    local stored = weaponTable(clip.weaponName[wep])
    local ht = stored and isstring(stored.HoldType) and stored.HoldType ~= "" and string.lower(stored.HoldType) or "ar2"
    return ht
end
local PASSIVE = {idle = "idle_all_01", walk = "walk_all", run = "run_all_01", cidle = "cidle_all", cwalk = "cwalk_all"}
local function sequenceFor(g, ht, move)
    if ht ~= "all" then
        local seq = g:LookupSequence(move .. "_" .. ht)
        if seq and seq >= 0 then return seq end
        seq = g:LookupSequence(move .. "_ar2")
        if seq and seq >= 0 then return seq end
    end
    return g:LookupSequence(PASSIVE[move])
end

-- A downed or dead actor with recorded poses is shown as a real ragdoll, every physics bone placed where it was.
local function poseRagdoll(g, actor, cs, origin)
    local a, b, f = V.RagAt(actor, cs)
    if not a then return false end
    if g.zcRagBad then return false end
    local body = g.zcRag
    if not IsValid(body) then
        local model = actor.rag.m
        body = ClientsideRagdoll(model and model ~= "" and util.IsValidModel(model) and model or g:GetModel())
        if not IsValid(body) then return false end
        -- Recorded bones are indexed by physics object: on a different skeleton they would twist the body, so fall back to the mannequin.
        if body:GetPhysicsObjectCount() ~= (actor.rag.n or 0) then body:Remove() g.zcRagBad = true return false end
        body:SetNoDraw(false)
        body:DrawShadow(true)
        g.zcRag = body
    end
    local n = math.min(actor.rag.n or 0, body:GetPhysicsObjectCount())
    for bone = 0, n - 1 do
        local phys = body:GetPhysicsObjectNum(bone)
        local i = 1 + bone * 6
        if IsValid(phys) and a[i + 6] and b[i + 6] then
            phys:EnableMotion(false)
            phys:SetPos(Vector(origin[1] + a[i + 1] + (b[i + 1] - a[i + 1]) * f, origin[2] + a[i + 2] + (b[i + 2] - a[i + 2]) * f, origin[3] + a[i + 3] + (b[i + 3] - a[i + 3]) * f), true)
            phys:SetAngles(LerpAngle(f, Angle(a[i + 4], a[i + 5], a[i + 6]), Angle(b[i + 4], b[i + 5], b[i + 6])))
        end
    end
    body:SetNoDraw(false)
    return true
end

local function pose(g, actor, cs, origin, clip)
    local x, y, z, yaw, _, flags, wep, _, eye = V.StateAt(actor, cs)
    if x and (V.HasFlag(flags, 4) or not V.HasFlag(flags, 1)) and poseRagdoll(g, actor, cs, origin) then
        g:SetNoDraw(true)
        if IsValid(g.zcGun) then g.zcGun:SetNoDraw(true) end
        return
    end
    if IsValid(g.zcRag) then g.zcRag:SetNoDraw(true) end
    if not x then
        g:SetNoDraw(true)
        if IsValid(g.zcGun) then g.zcGun:SetNoDraw(true) end
        return
    end
    arm(g, clip, wep)
    if IsValid(g.zcGun) then g.zcGun:SetNoDraw(false) end
    local _, _, _, _, pitch = V.StateAt(actor, cs)
    local px, py = V.StateAt(actor, cs - 10)
    local vx, vy = px and (x - px) * 10 or 0, py and (y - py) * 10 or 0
    local speed = math.sqrt(vx * vx + vy * vy)
    local alive, down, crouch = V.HasFlag(flags, 1), V.HasFlag(flags, 4), V.HasFlag(flags, 2)
    local move = crouch and (speed > 20 and "cwalk" or "cidle") or (speed > 170 and "run" or (speed > 20 and "walk" or "idle"))
    local seq = sequenceFor(g, holdType(clip, wep), move)
    if seq and seq >= 0 and g:GetSequence() ~= seq then g:ResetSequence(seq) end
    -- The walk and run sequences are nine-way blends: without move_x / move_y they play frozen on the spot.
    local rad = math.rad(yaw)
    local fx, fy = math.cos(rad), math.sin(rad)
    local scale = speed > 1 and 1 / speed or 0
    g:SetPoseParameter("move_x", (vx * fx + vy * fy) * scale)
    g:SetPoseParameter("move_y", (vx * fy - vy * fx) * scale)
    g:SetPoseParameter("aim_pitch", math.Clamp(pitch or 0, -89, 89))
    g:SetPoseParameter("head_pitch", math.Clamp(pitch or 0, -60, 60))
    -- Gait follows distance covered, so feet keep pace at any playback speed (and hold still when paused).
    g.zcStride = (g.zcStride or 0) + (g.zcLastCs and math.max(cs - g.zcLastCs, 0) / 100 * speed or 0)
    g.zcLastCs = cs
    g:SetCycle(speed > 20 and (g.zcStride / (move == "run" and 190 or 95)) % 1 or (cs / 100 * 0.25) % 1)
    g:InvalidateBoneCache()
    g:SetPos(Vector(origin[1] + x, origin[2] + y, origin[3] + z + ((down or not alive) and 8 or 0)))
    g:SetAngles((down or not alive) and Angle(-90, yaw, 0) or Angle(0, yaw, 0)) -- down or dead: laid flat
    g:SetNoDraw(false)
    g.zcFlat = down or not alive
    if IsValid(g.zcGun) then
        if g.zcFlat then
            g.zcGun:SetNoDraw(true)
        else
            local kick = clip.actors[clip.pov or 0] == actor and (L.kick or 0) or 0
            local gp, ga, hp, ha = heldTransform(g.zcWeapon, Vector(origin[1] + x, origin[2] + y, origin[3] + z + (eye or 64)), (pitch or 0) - kick * 1.6, yaw)
            gp = gp - ga:Forward() * kick * 1.5
            g.zcGun:SetPos(gp) g.zcGun:SetAngles(ga)
            g.zcGun:SetRenderOrigin(gp) g.zcGun:SetRenderAngles(ga)
            g.zcHandPos, g.zcHandAng = hp, ha
        end
    end
end

----------------------------------------------------------------- sound and flash
-- Played with no engine attenuation and our own distance falloff: the audio listener is not
-- guaranteed to follow a replay camera, so positional playback could come out silent.
local FLESH = {"physics/flesh/flesh_impact_bullet1.wav", "physics/flesh/flesh_impact_bullet2.wav", "physics/flesh/flesh_impact_bullet3.wav", "physics/flesh/flesh_impact_bullet4.wav", "physics/flesh/flesh_impact_bullet5.wav"}
local STEPS = {"player/footsteps/concrete1.wav", "player/footsteps/concrete2.wav", "player/footsteps/concrete3.wav", "player/footsteps/concrete4.wav"}
local FALLBACK_SHOT = "weapons/ar2/fire1.wav"
local shotSound = {}
local function fireSound(class)
    if shotSound[class] ~= nil then return shotSound[class] end
    local stored = weaponTable(class)
    local snd = stored and stored.Primary and stored.Primary.Sound
    if istable(snd) then snd = snd[1] end
    if not isstring(snd) or snd == "" then snd = FALLBACK_SHOT end
    shotSound[class] = snd
    return snd
end

local function worldPos(clip, actor, cs, up)
    local x, y, z = V.StateAt(actor, cs)
    if not x then return end
    local o = clip.origin
    return Vector(o[1] + x, o[2] + y, o[3] + z + (up or 0))
end

local function play(path, pos, ear, rate, loud)
    if not pos or not ear then return end
    local vol = math.Clamp(1 - pos:Distance(ear) / (loud and 4000 or 1200), loud and 0.2 or 0, 1)
    if vol <= 0 then return end
    -- slow motion drops the pitch with it, which is most of what sells it
    sound.Play(path, ear, 0, math.Clamp(38 + rate * 62, 50, 100), vol) -- pitch follows the slow-motion ramp
end

local function fireEvents(from, to, rate)
    local clip = L.clip
    local ear = select(1, L.eye and L.eye() or nil)
    for _, e in ipairs(clip.events) do
        if e[1] > from and e[1] <= to then
            local actor = clip.actors[e[3]]
            if e[2] == 1 and actor then
                local pos = worldPos(clip, actor, e[1], 56)
                play(fireSound(clip.weaponName[e[7]]), pos, ear, rate, true)
                if pos then
                    local light = DynamicLight(4096 + e[3])
                    if light then light.pos, light.r, light.g, light.b, light.brightness, light.size, light.decay, light.dietime = pos, 255, 190, 110, 3, 180, 1800, CurTime() + 0.08 end
                end
                if e[3] == clip.pov then L.kick = 1 end
            elseif e[2] == 2 and clip.actors[e[4]] then
                if e[4] == clip.target then L.hitFlash, L.hitDmg, L.hitGroup = 1, e[5], e[6] end
                play(FLESH[math.random(#FLESH)], worldPos(clip, clip.actors[e[4]], e[1], 40), ear, rate, false)
            end
        end
    end
    -- footsteps: one per stride of distance covered
    for i, g in pairs(L.ghosts) do
        if IsValid(g) and g.zcStride and not g:GetNoDraw() then
            local stepAt = math.floor(g.zcStride / 70)
            if g.zcStep and stepAt > g.zcStep then play(STEPS[math.random(#STEPS)], g:GetPos(), ear, rate, false) end
            g.zcStep = stepAt
        end
    end
end

----------------------------------------------------------------- playback
local function eyeOf(clip, cs)
    local actor = clip.actors[clip.pov or 0]
    if not actor then return end
    local x, y, z, yaw, pitch, _, _, _, eye = V.StateAt(actor, cs)
    if not x then return end
    local o = clip.origin
    local kick = L and L.kick or 0
    return Vector(o[1] + x, o[2] + y, o[3] + z + (eye or 64)), Angle(pitch - kick * 1.6, yaw, 0)
end

-- Scene changes (spectating -> replay, hit -> hit, replay -> spectating) all pass through a curtain:
-- fade to black, do the switch while nothing is visible, hold a title card, fade back in.
local outroAt = 0

-- Vote-rework contract: true while ANY replay or highlight owns the screen (playing, fading, waiting, or the end
-- card up) - INCLUDING the short black fade back into spectating after stop(), which is the last bit of screen
-- time this file still owns (see the HUDPaint fallback below: `not L` fades `outroAt` out over 0.45s). Turns
-- false exactly when that fade finishes, i.e. exactly when the player's screen is back to the world.
function V.IsPlaying() return L ~= nil or (RealTime() - outroAt) < 0.45 end
local function through(hold, fade, switch)
    if L.pending then return end
    L.curtainTo, L.curtainTime, L.cardHold, L.pending = 1, fade, hold, switch
end
local function go(index)
    through(index <= #L.seq.instances and 1.25 or 0, 0.25, function()
        L.waiting, L.card = false, L.seq.instances[index] and index or nil
        load(index)
    end)
end
local function leave()
    if L.leaving then return end
    L.leaving = true
    L.pending = nil
    -- R3: tell the server this recipient is done watching the highlight, so it can release the intermission
    -- hold as soon as everyone has (sv_highlight.lua zckc_hl_done), instead of always waiting the worst case.
    -- Never sent for a life sequence - only a highlight holds the round.
    if L.seq and L.seq.kind == "highlight" and not L.hlDoneSent then
        L.hlDoneSent = true
        net.Start("zckc_hl_done") net.SendToServer()
    end
    through(0, 0.2, function() stop() outroAt = RealTime() end)
end
local function curtain()
    L.curtain = math.Approach(L.curtain or 0, L.curtainTo or 0, RealFrameTime() / (L.curtainTime or 0.25))
    if L.pending and L.curtain >= 1 then
        local switch = L.pending
        L.pending = nil
        switch()
        if not L then return false end
        L.cardUntil = RealTime() + (L.cardHold or 0)
        if L.over then L.curtainTo, L.curtainTime = 0.6, 0.4 end -- the end card sits on a dimmed view of where you are spectating
    elseif not L.pending and not L.over and L.curtainTo == 1 and RealTime() >= (L.cardUntil or 0) then
        L.curtainTo, L.curtainTime, L.card = 0, 0.35, nil
    end
    return true
end

local keys = {}
local function pressed(code)
    local down = input.IsKeyDown(code)
    local edge = down and not keys[code]
    keys[code] = down
    return edge
end

hook.Add("Think", "ZCKillcam.Life", function()
    if not L then return end
    local me = LocalPlayer()
    if not IsValid(me) or me:Alive() then return stop() end -- never hijack a living player's view
    local typing = vgui.GetKeyboardFocus() ~= nil or gui.IsConsoleVisible() or gui.IsGameUIVisible()
    local r, f, space, tab, q = pressed(KEY_G), pressed(KEY_V), pressed(KEY_SPACE), pressed(KEY_B), pressed(KEY_Q)
    if not curtain() then return end
    if L.leaving then return end
    if space and L.card and not L.pending and L.curtainTo == 1 then L.cardUntil, space = 0, false end
    if L.waiting then -- offered, not started: spectating carries on untouched underneath
        if typing then return end
        if q then return leave() end
        if space or (setting("zc_killcam_autoplay", true) and RealTime() >= L.startAt) then go(1) end
        return
    end
    if not typing then
        if q then return leave() end
        if tab and V.OpenSequence then local id, seq = L.id, L.seq stop() return V.OpenSequence(id, seq) end
        if f and not L.saved then net.Start("zckc_save") net.SendToServer() end
        if r and not L.over and not L.dialog then
            if L.inst.reportable then
                L.dialog = V.ReportDialog(L.id, L.index, L.inst, function() if L then L.dialog = nil end end)
            else say(REPLY[3]) end
        end
        if space and not L.over then return go(L.index + 1) end
    end
    if L.over then
        -- R3: a highlight has nobody to report to or save for, so its end card is pure waiting once the player
        -- has seen it - and now that leave() reports "done" (below), a shorter cap here also releases the round's
        -- intermission hold sooner. Life replays keep the old 8s: report/save are real choices there.
        local cap = (L.seq and L.seq.kind == "highlight") and 4 or 8
        if RealTime() - L.overAt > cap then leave() end
        return
    end
    if L.dialog then return end -- paused while writing a report
    local want = (L.cs >= SLOW_FROM and L.cs <= SLOW_TO) and SLOW or 1
    L.rate = Lerp(math.min(RealFrameTime() * 5, 1), L.rate or 1, want)
    local rate = (L.curtainTo == 1 or L.pending) and 0 or L.rate -- nothing moves while the card is up
    local before = L.cs
    L.cs = math.min(L.cs + RealFrameTime() * 100 * rate, L.clip.last)
    if L.cs >= L.clip.last then go(L.index + 1) end
    L.hitFlash = math.max((L.hitFlash or 0) - RealFrameTime() * 1.6, 0)
    L.kick = math.max((L.kick or 0) - RealFrameTime() * rate * 9, 0)
    L.eye = function() return eyeOf(L.clip, L.cs) end
    fireEvents(before, L.cs, rate)
    for i, g in pairs(L.ghosts) do if IsValid(g) then pose(g, L.clip.actors[i], L.cs, L.clip.origin, L.clip) end end
end)

-- The gamemode has CalcView hooks of its own and hook order is not ours to choose, so the replay
-- renders the frame itself. CalcView stays as the fallback if the render call fails.
-- The gamemode's first person runs at hg_fov clamped to 75-100. A normal view is then widened by the
-- engine for screens wider than 4:3; render.RenderView takes the number as given, so the same widening is applied here.
-- PROVISIONAL(2026-09-21, the widening is reasoned from the owner's "FOV a little low" report, not measured: zc_killcam_fov overrides, ratify-by: 2026-10-05)
local function replayFov(widen)
    local fov = setting("zc_killcam_fov", 0) -- the viewer's convar (cl_part_06); 0 = follow hg_fov
    if fov <= 0 then
        local hgFov = GetConVar("hg_fov")
        fov = math.Clamp(hgFov and hgFov:GetFloat() or 90, 75, 100)
    end
    if not widen then return fov end
    return math.deg(2 * math.atan(math.tan(math.rad(fov) / 2) * (ScrW() / ScrH()) / (4 / 3)))
end

local drawOverlay -- defined with the overlay, below
local rendering = false
hook.Add("RenderScene", "ZCKillcam.Life", function()
    if not L or L.over or L.waiting or rendering then return end
    local origin, angles = eyeOf(L.clip, L.cs)
    if not origin then return end
    rendering = true
    local ok = pcall(render.RenderView, {origin = origin, angles = angles, x = 0, y = 0, w = ScrW(), h = ScrH(), fov = replayFov(true), znear = 1,
        drawhud = false, drawviewmodel = false, dopostprocess = false})
    rendering = false
    L.ownsFrame = ok
    if ok then
        -- The spectator HUD ("Spectating player: ...") describes the live round, not the replay, so it is
        -- off (drawhud = false) and the replay paints its own overlay on the finished frame.
        cam.Start2D()
        local fine, err = pcall(drawOverlay)
        cam.End2D()
        if not fine and not L.overlayErr then L.overlayErr = true print("[Killcam] overlay: " .. tostring(err)) end
        return true
    end
end)
hook.Add("CalcView", "ZCKillcam.Life", function()
    if not L or L.over or L.waiting then return end
    local origin, angles = eyeOf(L.clip, L.cs)
    if not origin then return end
    L.ownsFrame = false
    return {origin = origin, angles = angles, fov = replayFov(false), znear = 1, drawviewer = false}
end)

-- Living players are hidden while the replay runs: it shows the past, not where people are now.
hook.Add("PrePlayerDraw", "ZCKillcam.LifeHide", function() if L and not L.over and not L.waiting then return true end end)

-- While the replay plays, the spectator controls (next/previous target, view mode) are swallowed,
-- so clicking through a replay does not shuffle who you were spectating.
local SPECTATE_BINDS = {["+attack"] = true, ["+attack2"] = true, ["+reload"] = true}
hook.Add("PlayerBindPress", "ZCKillcam.LifeBinds", function(_, bind)
    if L and not L.over and not L.waiting and SPECTATE_BINDS[string.lower(bind)] then return true end
end)

hook.Add("PostDrawOpaqueRenderables", "ZCKillcam.Life", function(_, sky)
    if sky or not L or L.over or L.waiting then return end
    local clip, cs = L.clip, L.cs
    for _, e in ipairs(clip.events) do -- hits linger as a red line from the shooter's eye to the body
        local age = cs - e[1]
        if e[2] == 2 and age >= 0 and age <= 50 and clip.actors[e[3]] and clip.actors[e[4]] then
            local ax, ay, az, _, _, _, _, _, eye = V.StateAt(clip.actors[e[3]], e[1])
            local bx, by, bz = V.StateAt(clip.actors[e[4]], e[1])
            if ax and bx then
                local o = clip.origin
                render.DrawLine(Vector(o[1] + ax, o[2] + ay, o[3] + az + (eye or 64) - 6), Vector(o[1] + bx, o[2] + by, o[3] + bz + 40), Color(255, 70, 60), true)
            end
        end
    end
end)

hook.Add("PreDrawHalos", "ZCKillcam.Life", function()
    if not L or L.over or L.waiting then return end
    local you = L.ghosts[L.clip.target or 0]
    if IsValid(you) and not you:GetNoDraw() then halo.Add({you}, Color(90, 170, 255), 1, 1, 2, true, true) end
end)

----------------------------------------------------------------- overlay
-- Styled after the gamemode's own HUD and menus (read from its source 2026-09-21): white text, near-black translucent
-- panels and the dark red outline its forgiveness menu uses. The ZCKC.Life* font names are the viewer's to define
-- (U4: the viewer draws with V.Font now); until the viewer has run they fall back to the engine's default font.

local DIM, TEXT, RED, BLUE, GREEN, AMBER = Color(170, 170, 170), Color(255, 255, 255), Color(225, 60, 60), Color(70, 130, 180), Color(140, 215, 120), Color(255, 175, 75)
local PANEL, EDGE = Color(28, 28, 28, 208), Color(155, 0, 0, 240)
V.LifeStyle = {panel = PANEL, edge = EDGE, text = TEXT, dim = DIM, red = RED}

local function panel(x, y, w, h, edge)
    surface.SetDrawColor(PANEL) surface.DrawRect(x, y, w, h)
    if edge then surface.SetDrawColor(edge) surface.DrawOutlinedRect(x, y, w, h, 2) end
end

-- A tag in an outlined box; returns its width. align: 0 left, 1 centre, 2 right of x.
local function tagBox(text, x, y, colour, align)
    surface.SetFont("ZCKC.LifeSmall")
    local tw, th = surface.GetTextSize(text)
    local bw = tw + 16
    local bx = align == 1 and x - bw / 2 or (align == 2 and x - bw or x)
    surface.SetDrawColor(28, 28, 28, 230) surface.DrawRect(bx, y, bw, th + 6)
    surface.SetDrawColor(colour) surface.DrawOutlinedRect(bx, y, bw, th + 6, 1)
    draw.SimpleText(text, "ZCKC.LifeSmall", bx + 8, y + 3, colour)
    return bw
end

-- Key hints as keycaps: {{"G", "Report this hit"}, ...}. centre = lay the row out around x.
local function keyRow(hints, x, y, centre)
    surface.SetFont("ZCKC.LifeSmall")
    local _, th = surface.GetTextSize("G")
    local gap, total = 18, 0
    for _, hint in ipairs(hints) do
        local kw, lw = surface.GetTextSize(hint[1]), surface.GetTextSize(hint[2])
        hint.kw, hint.lw = kw + 10, lw
        total = total + hint.kw + 6 + lw + gap
    end
    if centre then x = x - (total - gap) / 2 end
    for _, hint in ipairs(hints) do
        surface.SetDrawColor(DIM) surface.DrawOutlinedRect(x, y, hint.kw, th + 4, 1)
        draw.SimpleText(hint[1], "ZCKC.LifeSmall", x + hint.kw / 2, y + 2, TEXT, TEXT_ALIGN_CENTER)
        draw.SimpleText(hint[2], "ZCKC.LifeSmall", x + hint.kw + 6, y + 2, DIM)
        x = x + hint.kw + 6 + hint.lw + gap
    end
end

local function weaponName(class) return (string.gsub(class or "unknown weapon", "^weapon_", "")) end

local function drawWaiting(w, seq)
    local ease = math.min((RealTime() - L.shownAt) / 0.4, 1)
    surface.SetAlphaMultiplier(ease)
    local auto = setting("zc_killcam_autoplay", true)
    local text = string.format(auto and "Every hit you took this life (%d) replays shortly" or "A replay of every hit you took this life (%d) is ready", #seq.instances)
    surface.SetFont("ZCKC.LifeBody")
    local tw, th = surface.GetTextSize(text)
    local pw = math.max(tw + 40, ScreenScale(150))
    local x, y = w / 2 - pw / 2, ScreenScale(8)
    panel(x, y, pw, th * 2 + 26, EDGE)
    draw.SimpleText(text, "ZCKC.LifeBody", w / 2, y + 8, TEXT, TEXT_ALIGN_CENTER)
    keyRow({{"Space", auto and "Watch now" or "Watch"}, {"Q", "Skip"}}, w / 2, y + th + 14, true)
    if auto then -- the wait, as a bar draining along the bottom edge of the banner
        local total = math.max(L.startAt - L.shownAt, 0.01)
        surface.SetDrawColor(TEXT) surface.DrawRect(x + 2, y + th * 2 + 22, (pw - 4) * math.Clamp((L.startAt - RealTime()) / total, 0, 1), 2)
    end
    surface.SetAlphaMultiplier(1)
end

local function drawOver(w, h, seq)
    local hits, dmg, reported, who, attackers = 0, 0, 0, {}, 0
    for i, it in ipairs(seq.instances) do
        hits, dmg = hits + (it.hits or 0), dmg + (tonumber(it.dmg) or 0)
        if L.reported and L.reported[i] then reported = reported + 1 end
        if not who[it.attacker or "?"] then who[it.attacker or "?"] = true attackers = attackers + 1 end
    end
    local y = h * 0.4
    draw.SimpleText("That was every hit you took this life", "ZCKC.LifeHead", w / 2, y, TEXT, TEXT_ALIGN_CENTER)
    local _, hh = surface.GetTextSize("A")
    local line = string.format("%d hit%s   ·   %d attacker%s   ·   %d damage", hits, hits == 1 and "" or "s", attackers, attackers == 1 and "" or "s", dmg)
    draw.SimpleText(line .. (reported > 0 and string.format("   ·   %d reported", reported) or ""), "ZCKC.LifeBody", w / 2, y + hh + 6, DIM, TEXT_ALIGN_CENTER)
    keyRow({{"V", L.saved and "Saved" or "Save replay"}, {"B", "Review top-down"}, {"Q", "Back to spectating"}}, w / 2, y + hh * 2 + 22, true)
    local bw = ScreenScale(70)
    local left = math.Clamp(1 - (RealTime() - L.overAt) / 8, 0, 1)
    surface.SetDrawColor(60, 60, 60, 255) surface.DrawRect(w / 2 - bw / 2, y + hh * 3 + 34, bw, 2)
    surface.SetDrawColor(TEXT) surface.DrawRect(w / 2 - bw / 2, y + hh * 3 + 34, bw * left, 2)
    draw.SimpleText("Returning to spectating", "ZCKC.LifeSmall", w / 2, y + hh * 3 + 42, DIM, TEXT_ALIGN_CENTER)
end

local function drawPlaying(w, h, seq)
    local inst = L.inst
    -- P4: these were re-formatted and re-measured every HUDPaint (every rendered frame); they only actually
    -- change when the instance does, so they are built once per instance and reused here instead. No new
    -- file-scope locals - the cache lives on L, which already exists for this running sequence.
    if L.hudFor ~= L.index then
        L.hudFor = L.index
        L.hudTop = string.format("Hit %d of %d   ·   %.0fs before your death", L.index, #seq.instances, inst.ago or 0)
        L.hudAttacker = string.format("Through %s's eyes", tostring(inst.attacker))
        surface.SetFont("ZCKC.LifeHead")
        L.hudAttackerW = surface.GetTextSize(L.hudAttacker)
        L.hudWeaponDmg = string.format("%s   ·   %d hit%s, %s dmg", weaponName(inst.wep), inst.hits or 0, inst.hits == 1 and "" or "s", tostring(inst.dmg or 0))
    end
    local pad, top, bottom = ScreenScale(10), ScreenScale(24), ScreenScale(34)
    surface.SetDrawColor(PANEL) surface.DrawRect(0, 0, w, top) surface.DrawRect(0, h - bottom, w, bottom)
    surface.SetDrawColor(EDGE) surface.DrawRect(0, top, w, 2) surface.DrawRect(0, h - bottom - 2, w, 2)
    draw.SimpleText(L.hudTop, "ZCKC.LifeSmall", pad, ScreenScale(3), DIM)
    draw.SimpleText(L.hudAttacker, "ZCKC.LifeHead", pad, ScreenScale(9), TEXT)
    local nameW = L.hudAttackerW
    draw.SimpleText(L.hudWeaponDmg, "ZCKC.LifeBody", pad + nameW + 14, ScreenScale(12), DIM)
    tagBox(TAGS[inst.tag] or "", w - pad, ScreenScale(4), inst.reportable and RED or AMBER, 2)
    local rate = L.rate or 1
    draw.SimpleText(rate < 0.95 and string.format("%.2fx slow motion", rate) or "", "ZCKC.LifeSmall", w - pad, ScreenScale(15), DIM, TEXT_ALIGN_RIGHT)
    if not L.clip.pov then draw.SimpleText("The attacker left before this could be captured from their side", "ZCKC.LifeSmall", w / 2, top + 8, AMBER, TEXT_ALIGN_CENTER) end
    -- the strip is the progress bar: one cell per hit, the playing one fills as it runs
    local n = #seq.instances
    local cell = math.min((w - pad * 2) / n, ScreenScale(90))
    local frac = math.Clamp((L.cs - L.clip.first) / (L.clip.last - L.clip.first), 0, 1)
    local sy = h - bottom + ScreenScale(4)
    for i, it in ipairs(seq.instances) do
        local x = pad + (i - 1) * cell
        local done = L.reported and L.reported[i]
        surface.SetDrawColor(60, 60, 60, 255) surface.DrawRect(x, sy, cell - 6, 3)
        if i < L.index then surface.SetDrawColor(done and GREEN or DIM) surface.DrawRect(x, sy, cell - 6, 3)
        elseif i == L.index then
            surface.SetDrawColor(TEXT) surface.DrawRect(x, sy, (cell - 6) * frac, 3)
            surface.SetDrawColor(RED) surface.DrawRect(x + (cell - 6) * ((0 - L.clip.first) / (L.clip.last - L.clip.first)), sy - 3, 2, 9) -- the hit
        end
        local status = done and "reported" or (i == L.index and "playing" or (not it.reportable and "can't report" or tostring(it.dmg or 0) .. " dmg"))
        draw.SimpleText(tostring(it.attacker), "ZCKC.LifeSmall", x, sy + 6, i == L.index and TEXT or DIM)
        draw.SimpleText(status, "ZCKC.LifeSmall", x, sy + 6 + ScreenScale(6), done and GREEN or DIM)
    end
    local hints = {}
    if inst.reportable and not (L.reported and L.reported[L.index]) then hints[#hints + 1] = {"G", "Report this hit"} end
    hints[#hints + 1] = {"V", L.saved and "Saved" or "Save"}
    hints[#hints + 1] = {"Space", "Next hit"}
    hints[#hints + 1] = {"B", "Top-down"}
    hints[#hints + 1] = {"Q", "Back to spectating"}
    keyRow(hints, pad, h - ScreenScale(10))
    if (L.hitFlash or 0) > 0 then -- you were hit: red at the edges and the number
        local a = L.hitFlash
        surface.SetDrawColor(155, 0, 0, 90 * a)
        surface.DrawRect(0, top + 2, ScreenScale(8), h - top - bottom - 4) surface.DrawRect(w - ScreenScale(8), top + 2, ScreenScale(8), h - top - bottom - 4)
        draw.SimpleTextOutlined(string.format("-%s  %s", tostring(L.hitDmg or "?"), V.HitGroupName and V.HitGroupName(L.hitGroup) or ""), "ZCKC.LifeHead", w / 2, h * 0.62 - (1 - a) * 24, Color(255, 90, 90, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 200 * a))
    end
end

local function drawCard(w, h, seq)
    local it = L.card and seq.instances[L.card]
    if not it or L.pending then return end -- only once the scene behind it has been switched
    surface.SetAlphaMultiplier(math.Clamp((L.curtain - 0.5) * 2, 0, 1))
    local y = h * 0.4
    draw.SimpleText(string.format("HIT %d OF %d", L.card, #seq.instances), "ZCKC.LifeSmall", w / 2, y, DIM, TEXT_ALIGN_CENTER)
    surface.SetDrawColor(EDGE) surface.DrawRect(w / 2 - ScreenScale(12), y + ScreenScale(8), ScreenScale(24), 2)
    draw.SimpleText(tostring(it.attacker), "ZCKC.LifeTitle", w / 2, y + ScreenScale(11), TEXT, TEXT_ALIGN_CENTER)
    draw.SimpleText(string.format("%s   ·   %s damage   ·   %.0fs before your death", weaponName(it.wep), tostring(it.dmg or 0), it.ago or 0), "ZCKC.LifeBody", w / 2, y + ScreenScale(29), DIM, TEXT_ALIGN_CENTER)
    tagBox((TAGS[it.tag] or "") .. (it.reportable and "   ·   reportable" or ""), w / 2, y + ScreenScale(39), it.reportable and RED or AMBER, 1)
    keyRow({{"Space", "Skip"}}, w / 2, h - ScreenScale(24), true)
    surface.SetAlphaMultiplier(1)
end

function drawOverlay()
    if not L then return end
    local w, h = ScrW(), ScrH()
    local seq = L.seq
    L.shownAt = L.shownAt or RealTime()
    if L.over then
        surface.SetDrawColor(0, 0, 0, 255 * (L.curtain or 0)) surface.DrawRect(0, 0, w, h)
        drawOver(w, h, seq)
    elseif L.waiting then
        drawWaiting(w, seq)
    else
        drawPlaying(w, h, seq)
    end
    if not L.over and (L.curtain or 0) > 0 then
        surface.SetDrawColor(0, 0, 0, 255 * L.curtain) surface.DrawRect(0, 0, w, h)
        drawCard(w, h, seq)
    end
    if L.note and RealTime() < (L.noteUntil or 0) then
        draw.SimpleTextOutlined(L.note, "ZCKC.LifeBody", w / 2, ScreenScale(34), GREEN, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, color_black)
    end
end

hook.Add("HUDPaint", "ZCKillcam.Life", function()
    if not L then -- the fade back into spectating, after the replay has let go (never over a living player)
        local a = 1 - (RealTime() - outroAt) / 0.45
        if a > 0 and IsValid(LocalPlayer()) and not LocalPlayer():Alive() then surface.SetDrawColor(0, 0, 0, 255 * a) surface.DrawRect(0, 0, ScrW(), ScrH()) end
        return
    end
    -- While the replay owns the frame it draws the overlay itself (see RenderScene) and the gamemode's HUD is off.
    if L.ownsFrame and not L.over and not L.waiting then return end
    drawOverlay()
end)

----------------------------------------------------------------- arrival
local parts = {}
net.Receive("zckc_life", function()
    local id, status = net.ReadString(), net.ReadUInt(3)
    if status ~= 0 then return end
    local n, total, len = net.ReadUInt(8), net.ReadUInt(8), net.ReadUInt(16)
    local bucket = parts[id]
    if not bucket then
        bucket = {n = 0}
        parts = {[id] = bucket}
    end
    if not bucket[n] then bucket[n] = net.ReadData(len) bucket.n = bucket.n + 1 end
    if bucket.n < total then return end
    parts[id] = nil
    local raw = util.Decompress(table.concat(bucket, "", 1, total))
    local seq = raw and util.JSONToTable(raw)
    if not seq or not seq.instances or #seq.instances == 0 then return end
    if seq.map ~= game.GetMap() then return end
    -- R1(b): a blob that arrives while the player is still alive used to be dropped outright, which is most of
    -- "replays sometimes not shown" - every respawn mode loses one this way. Hold it instead (on V, not a new
    -- file-scope local - see the ceiling note at the top of this file) and offer it at the next death/spectate
    -- entry, for up to 90s. Never interrupts a living player: nothing here touches L while me:Alive().
    if LocalPlayer():Alive() then
        V.PendingLife = {id = id, seq = seq, at = RealTime()}
        return
    end
    stop()
    -- Offered first, started after the forgiveness window: see the header.
    L = {id = id, seq = seq, reported = {}, waiting = true, startAt = math.max(RealTime() + 1, deathAt + FORGIVE_WINDOW)}
end)
