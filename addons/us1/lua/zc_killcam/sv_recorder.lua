-- Z-City killcam, phase 1: the flight recorder.
-- Samples every player at 30 Hz into flat, preallocated number arrays (struct of
-- arrays, one ring per player slot) and keeps a ring of discrete combat events.
-- Numeric sample rings are preallocated; optional ragdoll and carry observations allocate on demand.
-- Read-only towards every other system: it never touches karma, damage or movement.
if not SERVER then return end
ZCKillcam = ZCKillcam or {}
local K = ZCKillcam
K.Version = "20260922.rec33"

-- 30 Hz (owner, 2026-09-22). DEPTH is the ring in SAMPLES, so it moves with HZ: the round tape cuts 10 s chunks and
-- states that the ring must hold 16-20 s (sv_tape.lua:41), so 600 keeps exactly the 20 s the old 400 held at 20 Hz.
-- Measured on US1 before the change: 22 players, avg 0.321 ms a run, i.e. 6.4 ms of every second. 30 Hz puts the
-- same work at ~9.6 ms/s before the new fields below.
local HZ, DEPTH, EVENTS = 30, 600, 4096 -- 20 s per player at 30 Hz (first-person replays need the smoothness), less whatever hit stamps use; ten players on full auto push ~100 events/s
local PRE, POST = 8, 3
K.HZ, K.Depth, K.Pre, K.Post = HZ, DEPTH, PRE, POST

local enabled = CreateConVar("zc_killcam_enabled", "0", FCVAR_ARCHIVE, "Record the rolling killcam buffer (server only, invisible to players)")
-- The one part of a sample whose cost is not yet measured on a full server (ten GetPoseParameter calls a player,
-- half-rate). Its own switch, so it can be dropped without touching the rest of the recorder: 0 records no pose and
-- the viewer falls back to deriving four of the ten from velocity, exactly as it did before.
local poseOn = CreateConVar("zc_killcam_pose", "1", FCVAR_ARCHIVE, "Record player pose parameters so replays animate like the game (costs ~10 reads per player per other sample)")

local FLAG_ALIVE, FLAG_CROUCH, FLAG_RAGDOLL, FLAG_GROUND, FLAG_INTERACT, FLAG_RELOAD, FLAG_ADS, FLAG_REST = 1, 2, 4, 8, 16, 32, 64, 128
local FLAG_LASER, FLAG_LIGHT = 256, 512
local LEAN = 65536 -- lean -1.3 .. 1.3 in fifths, stored as (q + 8) * 65536, nothing when upright
local restLog = {} -- [slot] = {{t, x, y, z}, ...}: see noteRest
local FLAG_KEYS, FLAG_SPEED, POSTURE = 1024, 2048, 4096 -- 1024: this recorder knows the keys (older clips guess the sprint); posture 0..15 rides above
K.Flags = {alive = FLAG_ALIVE, crouch = FLAG_CROUCH, ragdoll = FLAG_RAGDOLL, ground = FLAG_GROUND, interact = FLAG_INTERACT, reload = FLAG_RELOAD, ads = FLAG_ADS, rest = FLAG_REST, laser = FLAG_LASER, light = FLAG_LIGHT, keys = FLAG_KEYS, speed = FLAG_SPEED, posture = POSTURE, lean = LEAN}
local EV_SHOT, EV_HIT, EV_DEATH, EV_SWING, EV_THROW, EV_PUNCH, EV_PULL, EV_UNPULL = 1, 2, 3, 4, 5, 6, 7, 8
K.Kinds = {shot = EV_SHOT, hit = EV_HIT, death = EV_DEATH, swing = EV_SWING, throw = EV_THROW, punch = EV_PUNCH, pull = EV_PULL, unpull = EV_UNPULL}

-- Sample rings. Index = (slot - 1) * DEPTH + cursor. st == 0 marks an empty cell.
local slots = math.max(game.MaxPlayers(), 1)
local st, sx, sy, sz, syaw, spitch, sflags, swep, shp, seye = {}, {}, {}, {}, {}, {}, {}, {}, {}, {}
local rad, sin, cos = math.rad, math.sin, math.cos
local sex, sey, sez = {}, {}, {} -- the first-person eye, relative to the sampled position; sez == 0 means "not known"
-- What the BODY was doing, as opposed to where it was (owner, 2026-09-22: the replay was not recording enough to look
-- like the game). Everything here was being GUESSED by the viewer from position alone:
--   svx/svy/svz  the real velocity. The viewer used to difference two positions 100 ms apart, which lags the truth by
--                50 ms, is flat wrong the moment anyone changes direction, and drove FOUR things at once: the nine-way
--                move_x / move_y blend, the walk/run/idle choice, the gait cycle and the held gun's walk bob.
--   sseq/scyc    the sequence the server was actually playing and how far through it was. The viewer picked between
--                five hard-coded sequences by speed, so a jump, a vault, a swim or any Z-City animation replayed as a walk.
--   spose        the model's pose parameters. Measured on US1 2026-09-22, the playermodel has ten - move_y, move_x,
--                aim_yaw, aim_pitch, vertical_velocity, vehicle_steer, head_yaw, head_pitch, zcg_yaw, zcg_pitch - and
--                the server keeps them all live (read off live players: aim_yaw 24.8, move_x -0.19). The replay set
--                four of the ten, from its own guesses, and left six unset. aim_yaw is the torso-against-feet twist:
--                without it a ghost's whole body snaps round with the mouse, which nothing in the game ever does.
local POSE_N = 10
local svx, svy, svz, sseq, scyc = {}, {}, {}, {}, {}
local sbodyYaw, sanimMode = {}, {}
local sgrip, scarry, scx, scy, scz, scp, scyaw = {}, {}, {}, {}, {}, {}, {}
local spose, spn = {}, {} -- POSE_N values per cell at (i - 1) * POSE_N + k; spn is how many of them are real (0 = none)
K.PoseN = POSE_N
local head, owner = {}, {} -- per slot: next cursor, UserID that owns the ring
local function reset()
    for i = 1, slots * DEPTH do st[i], sx[i], sy[i], sz[i], syaw[i], spitch[i], sflags[i], swep[i], shp[i], seye[i] = 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 sex[i], sey[i], sez[i] = 0, 0, 0
        svx[i], svy[i], svz[i], sseq[i], scyc[i], spn[i] = 0, 0, 0, -1, 0, 0
        sbodyYaw[i], sanimMode[i] = 0, 0
        sgrip[i], scarry[i], scx[i], scy[i], scz[i], scp[i], scyaw[i] = 0, 0, 0, 0, 0, 0, 0
        local pb = (i - 1) * POSE_N
        for k = 1, POSE_N do spose[pb + k] = 0 end
    end
    for s = 1, slots do head[s], owner[s] = 0, -1 end
end
reset()

-- Event ring.
local et, ek, ea, eb, ed, eg, ew, el, eu = {}, {}, {}, {}, {}, {}, {}, {}, {}
-- The truth of a shot: Z-City fires from the gun's muzzle along the GUN, not from the eye along the view (sh_bullet.lua:791).
-- Shot events keep the bullet's source and direction, hit events the damage position. All 0 = not known.
local epx, epy, epz, eyaw, epitch = {}, {}, {}, {}, {}
local eswing = {} -- optional native animation-start duration, cleared on ring reuse
local epenetration = {} -- immutable optional native trace samples and outcome
local eballistics = {} -- optional shot/impact facts, cleared on every ring reuse
local ebody, eballistic = {}, {} -- optional wound endpoints; never mixed across merged hits
-- A1 (killcam_polish, 2026-09-24): per hit, the landing point ON THE BODY: {v=1, b={x,y,z} body space (tenths, from
-- the sampler's reference position + eye yaw), k=hit bone key, l={x,y,z} in that bone's space, rw=distance from the
-- newest sample before the hit (tenths), age=that sample's age (cs)}. Inside the damage hook the victim stands where
-- the shooter saw them (lag compensation, homigrad_base sh_bullet.lua), the samples say where they were: the replay
-- draws the samples, so a world-space landing point can float off the body by the rewind. The client re-places it.
local eanchor = {}
-- UI cohesion U1 (2026-09-26): the organ rows each hit's round crossed, in entry order, for the death panel's body view
-- ({bone, key, name, label, class, dep}; dep = share of the round's energy left there, V2 only). nil for merged hits.
local eorgans = {}
local HIT_BONES = {"ValveBiped.Bip01_Head1", "ValveBiped.Bip01_Spine2", "ValveBiped.Bip01_Spine", "ValveBiped.Bip01_L_UpperArm",
    "ValveBiped.Bip01_R_UpperArm", "ValveBiped.Bip01_L_Thigh", "ValveBiped.Bip01_R_Thigh"} -- the client keeps the same list (V.HitBones)
local HIT_BONE = {[0] = 2, 1, 2, 3, 4, 5, 6, 7, [10] = 3} -- HITGROUP_* (generic/gear included) -> HIT_BONES key
for i = 1, EVENTS do et[i], ek[i], ea[i], eb[i], ed[i], eg[i], ew[i], el[i], eu[i] = 0, 0, 0, 0, 0, 0, 0, 0, 0 end
local ehead, ecount = 0, 0
-- A slot and even a UserID can outlive a life. Attribute a hit only to the
-- victim identity and life that received it, including respawns within PRE.
local victimUID, victimLife, lifeSerial = {}, {}, {}
for i = 1, EVENTS do victimUID[i], victimLife[i] = 0, 0 end
for s = 1, slots do lifeSerial[s] = 0 end
-- Owner-approved 2026-09-24 (killcam_revitalize): a ragdoll get-up (homigrad/fake/sv_tier_0.lua) sets the global
-- OverrideSpawn and calls ply:Spawn() in the MIDDLE of a life - that is not a new life.
hook.Add("PlayerSpawn", "ZCKillcam.RecorderLife", function(p)
    if OverrideSpawn then return end
    local s = p:EntIndex()
    lifeSerial[s] = (lifeSerial[s] or 0) + 1
end)
hook.Add("ZB_PreRoundStart", "ZCKillcam.RecorderLife", function()
    for s = 1, slots do lifeSerial[s] = lifeSerial[s] + 1 end
end)

-- Weapon classes are interned once so samples and events stay plain numbers.
local wepId, wepName = {}, {}
local function weaponId(w)
    if not IsValid(w) then return 0 end
    local class = w:GetClass()
    local id = wepId[class]
    if not id then id = #wepName + 1 wepName[id] = class wepId[class] = id end
    return id
end
K.WeaponName = function(id) return wepName[id] end
-- A label that is not a weapon class: "prop:<model name>" for a thrown prop, the entity class for a projectile.
-- Same table, so clip.weapons carries it and the client prints it like any weapon.
local function labelId(label)
    if not isstring(label) or label == "" then return 0 end
    local id = wepId[label]
    if not id then id = #wepName + 1 wepName[id] = label wepId[label] = id end
    return id
end
function K.LabelOf(ent)
    if not IsValid(ent) then return 0 end
    local class = ent:GetClass()
    if string.sub(class, 1, 7) == "ent_hg_" then return labelId(class) end
    local model = ent:GetModel()
    if isstring(model) and model ~= "" then return labelId("prop:" .. string.gsub(string.GetFileFromFilename(model), "%.mdl$", "")) end
    return labelId(class)
end

-- Kept across hot reloads: the other files hold this same table.
local stats = K.Stats or {samples = 0, runs = 0, sum = 0, max = 0, shots = 0, hits = 0, deaths = 0, wouldSave = 0}
K.Stats = stats

-- The name the GAME shows, which is not the Steam nick. homigrad's appearance system writes the player's authored
-- character name into the NWString "PlayerName" (new_appearance/sv_init.lua), and the playerclasses overwrite it with
-- what that class is called: a metrocop or combine CALLSIGN, "SWAT "..name, a rank and name for the national guard,
-- "Zombie", "Gordon". The gamemode reads it back everywhere it shows a name (cl_init.lua's spectate HUD, the mode
-- scoreboards). Labelling a replay with Nick() therefore prints a name that appeared NOWHERE in the round - which for
-- a tool staff ban from is a real problem, not a cosmetic one: the reporter and the reviewer see different people.
-- SteamID64 is carried separately on every record, so identity is never lost by preferring the displayed name.
-- GetNWString answers "" (not nil) when unset, so the fallback is on the empty string.
function K.DisplayName(p)
    if not IsValid(p) then return "?" end
    local shown = p.GetNWString and p:GetNWString("PlayerName", "") or ""
    if shown ~= "" then return shown end
    return p:Nick()
end

-- Steam names are separate from character/callsign names; never resolve an old clip against live players.
function K.SteamName(p)
    local name = p:Nick()
    return isstring(name) and string.gsub(name, "[%c]", " ") or nil
end

local function slotOf(p)
    local s = p:EntIndex()
    return s >= 1 and s <= slots and s or nil
end

-- Who owns a slot. Cached when the slot changes hands (the only allocation here), so a
-- killer who disconnects before the victim bleeds out still lands on the record.
local ident = {}
local rag = {} -- slot -> ragdoll track, see below
K.Identity = function(slot) return ident[slot] end
local BARE = "models/player.mdl"

-- What a player WEARS, not merely which model file they use: Z-City dresses them in bodygroups (the clothing on the
-- slav and civilwar packs IS a bodygroup) and gives every player their own colour. A replay built from the model path
-- alone is the default variant in the default colour - a different-looking person (owner, 2026-09-21: "show player
-- appearance as it's set up, instead of filling it in"). Read off the live player, so it is what it is and never a guess.
local LOOK_GAP = 1 -- how often K.Look re-reads a player: clothing changes mid-round, and GetBodygroup is a call per group
local SUB_MAX = 32 -- the engine's submaterial slots are 0..31 (Entity:SetSubMaterial)

-- These run on the sampler's path, whose whole discipline is that a steady state allocates NOTHING, and a player's
-- look almost never changes. So each read fills a reused scratch buffer, compares, and only builds a real table when
-- something actually moved. That also keeps the other half of the contract: a clip keeps whatever table it was handed,
-- so a change must produce a NEW table, never an edit of one some pending cut is already carrying.
local buf = {}
local function kept(old, n)
    if not old or #old ~= n then return false end
    for i = 1, n do if old[i] ~= buf[i] then return false end end
    return true
end
local function keptPairs(old, n) -- buf holds slot, path, slot, path, ... for n pairs
    if not old or #old ~= n then return false end
    for i = 1, n do
        local was = old[i]
        if was[1] ~= buf[i * 2 - 1] or was[2] ~= buf[i * 2] then return false end
    end
    return true
end

local function look(id, p, fresh)
    id.skin = p:GetSkin()

    local n, worn = p:GetNumBodyGroups(), false
    for g = 1, n do
        local v = p:GetBodygroup(g - 1)
        buf[g] = v
        if v ~= 0 then worn = true end
    end
    if not worn then
        id.groups = nil -- most players are all-zero; a table of zeroes is not worth a wire field
    elseif not kept(id.groups, n) then
        local groups = {}
        for g = 1, n do groups[g] = buf[g] end
        id.groups = groups
    end

    local c = p:GetPlayerColor()
    if c then
        local r, gr, b = math.Round(c.x * 255), math.Round(c.y * 255), math.Round(c.z * 255)
        local was = id.colour
        if not was or was[1] ~= r or was[2] ~= gr or was[3] ~= b then id.colour = {r, gr, b} end
    else
        id.colour = nil
    end

    -- CLOTHES AND THE FACE ARE SUBMATERIALS on this gamemode, not bodygroups: new_appearance's ForceApplyAppearance
    -- puts AClothes and AFacemap on with SetSubMaterial. A ghost without them wears the model's stock outfit and the
    -- stock face, which is most of what made replays look like the wrong person. How many slots a model has cannot
    -- change unless the model does, and GetMaterials allocates a table of paths, so it is counted only then.
    if fresh or id.subn == nil then
        local mats = p:GetMaterials()
        id.subn = math.min(mats and #mats or 0, SUB_MAX)
    end
    local subn = 0
    for i = 0, id.subn - 1 do
        local path = p:GetSubMaterial(i) -- "" when there is no override
        if path and path ~= "" then
            subn = subn + 1
            buf[subn * 2 - 1], buf[subn * 2] = i, path
        end
    end
    if subn == 0 then
        id.subs = nil
    elseif not keptPairs(id.subs, subn) then
        local subs = {}
        for i = 1, subn do subs[i] = {buf[i * 2 - 1], buf[i * 2]} end -- pairs, like clip.weapons: JSON turns a numeric key into a string
        id.subs = subs
    end

    -- Accessories are hats and packs the client spawns itself out of `hg.Accessories`, keyed by name, so the names are
    -- the whole record. GetNetVar belongs to the gamemode: ask for it, never assume it.
    local acc = p.GetNetVar and p:GetNetVar("Accessories") or nil
    local accn = 0
    if istable(acc) then
        for k = 1, #acc do
            local v = acc[k]
            if isstring(v) and v ~= "" and v ~= "none" then accn = accn + 1 buf[accn] = v end
        end
    elseif isstring(acc) and acc ~= "" and acc ~= "none" then
        accn, buf[1] = 1, acc
    end
    if accn == 0 then
        id.acc = nil
    elseif not kept(id.acc, accn) then
        local names = {}
        for k = 1, accn do names[k] = buf[k] end
        id.acc = names
    end
end

-- A look WITH a time on it. The identity carries only a player's CURRENT appearance, but a clip is cut about 1.3 s
-- after the death it is about (sv_life settle()), and a lot can change in that window: a class swap on death, a
-- model reset, clothes cleared by round cleanup. Reading the identity at CUT time therefore paints the whole
-- replay - including the seconds BEFORE the death - with whatever the player looks like afterwards.
--
-- Keeping the last few looks with their timestamps lets the cut ask how somebody looked AT THE TIME instead.
-- Comparison is by table identity, which is exactly what look() guarantees: it only ever hands out a NEW table when
-- something actually changed, so an unchanged look costs one comparison and no memory.
local LOOK_KEEP = 6
local lookLog = {} -- slot -> {oldest first} of {t, model, skin, groups, colour, subs, acc}
-- The MODEL is read from the live player rather than off the identity: id.model is maintained by claim() on the
-- SAMPLER path, so a look pass can otherwise snapshot a model that is one tick stale - which showed up as a clip
-- carrying the default model for a player who had already changed.
local function remember(slot, id, t, model)
    model = (model and model ~= BARE) and model or id.model
    local log = lookLog[slot]
    if not log then log = {} lookLog[slot] = log end
    local last = log[#log]
    if last and last.model == model and last.skin == id.skin and last.groups == id.groups
        and last.colour == id.colour and last.subs == id.subs and last.acc == id.acc and last.steam == id.steam then return end
    log[#log + 1] = {t = t, model = model, skin = id.skin, groups = id.groups, colour = id.colour,
        subs = id.subs, acc = id.acc, steam = id.steam}
    if #log > LOOK_KEEP then table.remove(log, 1) end
end
K.ForgetLooks = function(slot) lookLog[slot] = nil end

-- How a slot looked at time `t`: the newest snapshot taken at or before it, or the oldest kept when the log does
-- not reach that far back. nil only when nothing was ever recorded for that slot.
function K.LookAt(slot, t)
    local log = lookLog[slot]
    if not log or #log == 0 then return nil end
    local best = log[1]
    for i = 2, #log do
        if log[i].t <= t then best = log[i] else break end
    end
    return best
end

local function claim(p, s)
    local uid = p:UserID()
    if owner[s] ~= uid then -- the slot changed hands: never splice two players into one clip
        owner[s] = uid
        restLog[s] = nil
        local base = (s - 1) * DEPTH
        for i = base + 1, base + DEPTH do st[i] = 0 end
        head[s] = 0
        ident[s] = {slot = s, uid = uid, id = not p:IsBot() and p:SteamID64() or nil, name = K.DisplayName(p), steam = K.SteamName(p), traitor = false, model = p:GetModel()}
        lookLog[s] = nil -- a new owner starts with no history; the old player's looks are not theirs
        if rag[s] then rag[s].head = 0 for i = 1, #rag[s].t do rag[s].t[i] = 0 end end
    end
    -- The model is whatever they wear NOW: a slot is first claimed before the playerclass has dressed the player, when
    -- GetModel() is still the engine's bare "models/player.mdl" - the static, untextured figure seen in replays (owner,
    -- 2026-09-21). The dead keep what they wore, appearance and all.
    local id = ident[s]
    local model = p:GetModel()
    if id.model ~= model and model ~= BARE and p:Alive() then id.model = model id.fresh = true end
    return id
end

-- The rest of a player's look is read on its OWN timer, not here. Appearance changes about never; sampling runs at HZ
-- and its contract is that a steady state allocates nothing. Putting the read on the sampler's path made a pinned
-- allocation test fail about one run in four (measured against the deployed recorder, which never fails it) - not
-- because the read is heavy, but because the extra branch perturbs the hot loop. So it lives out here instead.
function K.Look()
    if not enabled:GetBool() then return end
    for _, p in ipairs(player.GetAll()) do
        local s = slotOf(p)
        local id = s and ident[s]
        if id and id.uid == p:UserID() and p:GetModel() ~= BARE and p:Alive() then
            id.steam = K.SteamName(p)
            look(id, p, id.fresh or id.subn == nil)
            id.fresh = nil
            remember(s, id, CurTime(), p:GetModel())
        end
    end
end

local function push(kind, a, b, dmg, hitgroup, wep, los, uid)
    ehead = ehead % EVENTS + 1
    ecount = ecount + 1
    victimUID[ehead] = b and ident[b] and ident[b].uid or 0
    victimLife[ehead] = b and lifeSerial[b] or 0
    et[ehead], ek[ehead], ea[ehead], eb[ehead] = CurTime(), kind, a or 0, b or 0
    ed[ehead], eg[ehead], ew[ehead], el[ehead], eu[ehead] = dmg or 0, hitgroup or 0, wep or 0, los and 1 or 0, uid or 0
    epx[ehead], epy[ehead], epz[ehead], eyaw[ehead], epitch[ehead] = 0, 0, 0, 0, 0
    eswing[ehead] = nil
    epenetration[ehead] = nil
    eorgans[ehead] = nil
    eballistics[ehead] = nil
    ebody[ehead], eballistic[ehead] = nil, nil
    return ehead
end

-- Things a replay has to animate that no engine hook reports (owner, 2026-09-21: "draw the melee swing and grenade throw
-- animations"): a melee swing (kind 4) and a grenade leaving the hand (kind 5). Told by sv_tape.lua's weapon wraps, which
-- observe SWEP:PlayAnim and SWEP:Throw. `how` rides in the damage field: 1 = primary / high, 2 = alternate / low.
-- Every reader of the event ring tests for the kinds it knows, so the new ones pass through them untouched.
function K.NoteAction(p, kind, how, weapon, duration)
    if not enabled:GetBool() or not IsValid(p) or not p:IsPlayer() then return end
    local s = slotOf(p)
    if not s or not kind or kind < EV_SWING or kind > EV_UNPULL then return end -- 4 swing, 5 throw, 6 punch (how: 1 left, 2 right), 7 grenade pull-back (how: 1 high, 2 low), 8 pull-back put away again
    local i = push(kind, s, 0, how == 2 and 2 or 1, 0, weaponId(IsValid(weapon) and weapon or p:GetActiveWeapon()), false, p:UserID())
    if kind == EV_SWING and isnumber(duration) and duration > 0 and duration <= 10 then
        eswing[i] = {v = 1, duration = duration} -- timestamp is the native PlayAnim start, not a later hit-test tick
    end
end

-- Ragdoll tracks: the pose of every physics bone of a downed or dead player's body, so the replay
-- can drive a real ragdoll through what actually happened instead of laying a mannequin flat.
-- A track is allocated the first time a slot ragdolls (one block of numbers), then reused.
local RAG_DEPTH, RAG_BONES = 450, 24 -- 15 s at 30 Hz: the round tape cuts 10 s chunks and needs the margin; Z-City bodies have fewer than 24 physics bones
local RAG_STRIDE = RAG_BONES * 6
K.RagBones = RAG_BONES
-- The pose block grows a frame at a time on the first lap of the ring: filling all of it up front
-- cost 2-18 ms in one run on US1 when a round end ragdolled everyone together.
local function ragTrack(s)
    local r = rag[s]
    if not r then
        r = {t = {}, from = {}, n = {}, d = {}, head = 0, bones = 0, model = "", still = 0}
        for i = 1, RAG_DEPTH do r.t[i], r.n[i] = 0, 0 end
        rag[s] = r
    end
    return r
end
local function writeRag(s, body, now)
    local r = ragTrack(s)
    local n = math.min(body:GetPhysicsObjectCount(), RAG_BONES)
    if n == 0 then return end
    -- A body at rest (every corpse, most of the time) is not re-recorded: once two identical frames
    -- are down, the newer one just has its time moved forward, so playback holds the pose and the
    -- ring keeps the fall instead of filling with copies of the landing.
    -- Hands/arms can move while pelvis and last bone sleep (+speed/+walk).
    -- Only coalesce when EVERY physics object sleeps, on the SAME body.
    local bodyModel = body:GetModel() or ""
    local sleeping = r.head > 0 and r.body == body and r.model == bodyModel and r.bones == n
    if sleeping then
        for b = 0, n - 1 do
            local phys = body:GetPhysicsObjectNum(b)
            if not IsValid(phys) or not phys:IsAsleep() then sleeping = false break end
        end
    end
    if sleeping then
        r.still = r.still + 1
        if r.still > 2 then r.t[r.head] = now return end
    else r.still = 0 end
    local previous = r.head
    local sameBody = r.body == body
    r.body = body
    local cursor = r.head % RAG_DEPTH + 1
    r.head = cursor
    r.from[cursor] = now
    r.t[cursor], r.n[cursor] = now, n -- the count is per frame: a slot's body can change (fake ragdoll -> corpse, model swap)
    r.bones = n
    -- A corpse wears what its owner wore, and the body is the one that knows: read its look when the body itself
    -- changes (fake ragdoll -> corpse, model swap), never every frame - GetBodygroup is a call per group.
    if not sameBody or r.model ~= bodyModel then
        r.model, r.skin = bodyModel, body:GetSkin()
        local groups, worn = {}, false
        for g = 0, body:GetNumBodyGroups() - 1 do
            local v = body:GetBodygroup(g)
            groups[g + 1] = v
            if v ~= 0 then worn = true end
        end
        r.groups = worn and groups or nil
    end
    local d, base = r.d, (cursor - 1) * RAG_STRIDE
    if d[base + RAG_STRIDE] == nil then for k = base + 1, base + RAG_STRIDE do d[k] = 0 end end -- first lap: append this frame's block in order, so it stays an array
    for b = 0, n - 1 do
        local phys = body:GetPhysicsObjectNum(b)
        if IsValid(phys) then
            local pos, ang = phys:GetPos(), phys:GetAngles()
            d[base + 1], d[base + 2], d[base + 3], d[base + 4], d[base + 5], d[base + 6] = pos.x, pos.y, pos.z, ang.p, ang.y, ang.r
        elseif sameBody and previous > 0 then -- including the wrap from frame 450 back to 1
            local from = (previous - 1) * RAG_STRIDE + b * 6
            for k = 1, 6 do d[base + k] = d[from + k] end
        else
            for k = 1, 6 do d[base + k] = 0 end
        end
        base = base + 6
    end
end
-- Visits ragdoll frames of one slot inside [t0, t1], oldest first: fn(t, data, base, bones).
function K.EachRagFrame(slot, t0, t1, fn)
    local r = rag[slot]
    if not r then return end
    for k = 1, RAG_DEPTH do
        local i = (r.head + k - 1) % RAG_DEPTH + 1
        local t = r.t[i]
        local began = r.from[i] or t
        if t > 0 and t >= t0 and began <= t1 then
            -- A coalesced sleeping pose spans [began,t]. Emit clipped boundaries
            -- even when the next sampler tick has moved its end past the cut.
            local first, last = math.max(began, t0), math.min(t, t1)
            fn(first, r.d, (i - 1) * RAG_STRIDE, r.n[i])
            if last > first then fn(last, r.d, (i - 1) * RAG_STRIDE, r.n[i]) end
        end
    end
end
function K.RagModel(slot) return rag[slot] and rag[slot].model or nil end
-- The corpse's own skin and bodygroups, for a replay that dresses the body instead of spawning the default variant.
function K.RagLook(slot)
    local r = rag[slot]
    if not r then return nil, nil end
    return r.skin, r.groups
end

-- Aiming down sights. The answer is SWEP:IsZoom() (homigrad_base shared.lua:298, shared realm): the NWBool "aiming" is
-- only the toggle-aim latch, and IsZoom also folds in sprinting, broken arms, buttstock recovery and ragdoll combat.
-- It is the gamemode's code running inside our 20 Hz timer, so it is fenced: one bad weapon must not stop sampling.
local function aiming(w)
    local zoom = w.IsZoom
    if not zoom then return false end
    local ok, down = pcall(zoom, w)
    if not ok then stats.adsErrors = (stats.adsErrors or 0) + 1 return false end
    return down and true or false
end

-- Where a rested gun's bipod really stands: SWEP:RestWeapon keeps the trace hit relative to the entity it landed on
-- (NWVector RestPos, SWEP:GetBipodPosAng - homigrad_base/shared.lua:2537). Logged only when it moves, 16 per slot.
local function noteRest(w, s, now)
    local ok, posa, _, anga = pcall(w.GetBipodPosAng, w)
    if not ok or not posa or not anga then return end
    local at = LocalToWorld(w:GetNWVector("RestPos"), angle_zero, posa, anga)
    local log = restLog[s]
    local last = log and log[#log]
    if last and (last[2] - at.x) ^ 2 + (last[3] - at.y) ^ 2 + (last[4] - at.z) ^ 2 < 1 then return end
    if not log then log = {} restLog[s] = log end
    if #log >= 16 then table.remove(log, 1) end
    log[#log + 1] = {now, at.x, at.y, at.z}
end
function K.RestNow(slot) -- the newest logged point {t, x, y, z}, for the round tape
    local log = restLog[slot]
    return log and log[#log] or nil
end
-- Rows {cs, x, y, z} in tenths of a unit from the clip origin: the point in force when the window opens, then every move inside it.
function K.RestRows(slot, t0, t1, death, ox, oy, oz)
    local log = restLog[slot]
    if not log then return end
    local out, before = {}, nil
    for _, e in ipairs(log) do
        if e[1] < t0 then before = e elseif e[1] <= t1 then
            if before then out[1] = before before = nil end
            out[#out + 1] = e
        end
    end
    if before then out[1] = before end
    if #out == 0 then return end
    local function round(v) return math.floor(v + 0.5) end
    for i, e in ipairs(out) do out[i] = {round((e[1] - death) * 100), round((e[2] - ox) * 10), round((e[3] - oy) * 10), round((e[4] - oz) * 10)} end
    return out
end

-- Read the same owner clock that CalcMainActivity uses, without running hooks,
-- setting cycles, or invoking animation callbacks. Cache sequence lookup per identity/model.
-- Mode 0 means no custom body facing; 1 one-shot, 2 forward loop, 3 reversed entry.
function K.AnimationState(p, id, now)
    local seq, cycle = p:GetSequence(), p:GetCycle()
    local custom = p:GetNWString("hg_CustomAnim", "")
    if custom == "" then return seq, cycle, 0, 0 end
    local stealth = ZCityStealth
    local hostage = ZCityHostage and ZCityHostage.Gameplay
    local owner, data, yaw, mode
    if stealth and stealth.OwnsPose(p) then
        owner = stealth
        data = stealth.Assets.clips[p:GetNWString("zsf_clip", "")]
        yaw = p:GetNWFloat("zsf_yaw", p:EyeAngles().y)
        mode = data and data.loop and 2 or 1
    elseif hostage and hostage.OwnsPose(p) then
        owner = hostage
        data = hostage.Data.clips[p:GetNWString("zch_sequence", "")]
        yaw = p:GetNWFloat("zch_yaw", p:EyeAngles().y) + hostage.EntryYawOffset(p)
        mode = p:GetNWString("zch_phase", "") == "entry_reverse" and 3 or (data and data.loop and 2 or 1)
    end
    -- Generic PlayCustomAnims users (ground kicks and PAT jump kicks) use
    -- elapsed/duration in CalcMainActivity. Mode 4 is a one-shot without a
    -- forced body yaw; modes 1-3 belong to the explicit interaction owners.
    if not owner or not data then owner, yaw, mode = nil, 0, 4 end
    local model = p:GetModel()
    if id.animName ~= custom or id.animModel ~= model then
        id.animName, id.animModel = custom, model
        id.animSequence = p:LookupSequence(custom)
    end
    local exact = id.animSequence
    if not exact or exact < 0 then return seq, cycle, 0, 0 end
    local duration = p:GetNWFloat("hg_CustomAnimDelay", 0)
    if duration <= 0 then return seq, cycle, 0, 0 end
    local elapsed = now - p:GetNWFloat("hg_CustomAnimStartTime", now)
    local captured = owner and owner.Cycle(p, elapsed, duration) or elapsed / duration
    if not isnumber(captured) or captured ~= captured or captured == math.huge or captured == -math.huge then
        return seq, cycle, 0, 0
    end
    return exact, math.Clamp(captured, 0, 1), yaw, mode
end

-- Observe successful grips and the native carry target; never run input,
-- constraints, animation callbacks or SWEP methods from the recorder.
-- The hand target follows hg.DragHands (cl_tpik.lua). Store its collision-clipped
-- position and aim, so playback does not trace against a later live world.
function K.HandState(p, body)
    local grip = IsValid(body) and ((IsValid(body.ConsLH) and 1 or 0) + (IsValid(body.ConsRH) and 2 or 0)) or 0
    if IsValid(body) or not p:Alive() or not p.GetNetVar then return grip, 0, 0, 0, 0, 0, 0 end
    local ent, suffix = p:GetNetVar("carryent"), ""
    if not IsValid(ent) then ent, suffix = p:GetNetVar("carryent2"), "2" end
    if not IsValid(ent) then return grip, 0, 0, 0, 0, 0, 0 end
    local pos = p:GetNetVar("carrypos" .. suffix)
    if not pos then return grip, 0, 0, 0, 0, 0, 0 end
    local target
    if ent:IsRagdoll() then
        local phys = ent:GetPhysicsObjectNum(p:GetNetVar("carrybone" .. suffix, 0))
        if IsValid(phys) then target = LocalToWorld(pos, angle_zero, phys:GetPos(), phys:GetAngles()) end
    else target = ent:LocalToWorld(pos) end
    local spine = p:LookupBone("ValveBiped.Bip01_Spine4")
    local matrix = spine and p:GetBoneMatrix(spine)
    if not target or not matrix then return grip, 0, 0, 0, 0, 0, 0 end
    local start = matrix:GetTranslation()
    local delta = target - start
    local tr = util.TraceLine({start = start, endpos = start + delta:GetNormalized() * math.min(delta:Length(), 40), filter = p})
    local at = tr.HitPos - tr.Normal * 4
    local aim = (target - p:EyePos()):Angle()
    local left = not (p.organism and p.organism.larmamputated)
    if hg and hg.CanUseLeftHand then left = left and hg.CanUseLeftHand(p) end
    local w = p:GetActiveWeapon()
    local right = p:GetNetVar("carrymass", 0) > 15 or (not left and IsValid(w) and w:GetClass() == "weapon_hands_sh")
    return grip, (left and 1 or 0) + (right and 2 or 0), at.x, at.y, at.z, aim.p, aim.y
end

-- One sample of one player, written straight into the rings.
local function write(p, s, now)
    local cursor = head[s] % DEPTH + 1
    head[s] = cursor
    local i = (s - 1) * DEPTH + cursor
    local body = p.FakeRagdoll
    local ragdoll = IsValid(body)
    if not ragdoll and not p:Alive() then -- the corpse the gamemode leaves behind
        local corpse = p:GetNWEntity("RagdollDeath")
        if IsValid(corpse) then body = corpse end
    end
    local pos = IsValid(body) and body:GetPos() or p:GetPos()
    local ang = p:EyeAngles()
    local w = p:GetActiveWeapon()
    local flags = (p:Alive() and FLAG_ALIVE or 0) + (p:Crouching() and FLAG_CROUCH or 0)
        + (ragdoll and FLAG_RAGDOLL or 0) + (p:OnGround() and FLAG_GROUND or 0)
        + (p:GetNWString("zch_role", "") ~= "" and FLAG_INTERACT or 0)
        + (IsValid(w) and w.reload ~= nil and FLAG_RELOAD or 0) -- homigrad_base sets SWEP.reload to the finish time while reloading
        + (IsValid(w) and aiming(w) and FLAG_ADS or 0)
        + (IsValid(w) and w.RestPosition ~= nil and w:GetNWBool("IsResting", false) and FLAG_REST or 0) -- bipod down / gun rested (SWEP:RestWeapon); only the ten weapons with a RestPosition are asked
    -- homigrad_base sh_attachment.lua: SWEP.lasertoggle is 0 off, 1 laser, 2 light, 3 both, and only means anything with an underbarrel unit fitted
    if flags % 256 >= 128 then noteRest(w, s, now) end
    -- ply.lean is the server's eased copy of the lean keys (homigrad_base/sh_anim.lua, hook Bones "homigrad-lean-bone"); + is left
    local lean = tonumber(p.lean) or 0
    if lean > 0.1 or lean < -0.1 then
        local q = math.floor(lean * 5 + 0.5)
        flags = flags + ((q > 7 and 7 or q < -7 and -7 or q) + 8) * LEAN
    end
    -- ply.posture is the server's copy of the weapon posture (homigrad_base/sh_options.lua, change_posture): 0 none .. 9
    local stance = tonumber(p.posture) or 0
    flags = flags + FLAG_KEYS + (p:KeyDown(IN_SPEED) and FLAG_SPEED or 0) + ((stance >= 1 and stance <= 15) and math.floor(stance) * POSTURE or 0)
    local beam = IsValid(w) and w.lasertoggle or 0
    if beam ~= 0 and istable(w.attachments) and istable(w.attachments.underbarrel) and w.attachments.underbarrel[1] then
        flags = flags + ((beam == 1 or beam == 3) and FLAG_LASER or 0) + ((beam == 2 or beam == 3) and FLAG_LIGHT or 0)
    end
    if IsValid(body) then writeRag(s, body, now) end
    sgrip[i], scarry[i], scx[i], scy[i], scz[i], scp[i], scyaw[i] = K.HandState(p, body)
    st[i], sx[i], sy[i], sz[i] = now, pos.x, pos.y, pos.z
    syaw[i], spitch[i], sflags[i] = ang.y, ang.p, flags
    swep[i], shp[i], seye[i] = weaponId(w), p:Health(), p:EyePos().z - pos.z -- the engine's eye height: the fallback
    -- Where Z-City's first person REALLY sits (owner, 2026-09-21: "the camera does not accurately follow"): not EyePos but
    -- hg.eye (homigrad/sh_utility.lua:767) - the NECK bone + 2 up the aim + 4 to the bone's right + 4 along it (8 for the
    -- Combine class). Measured live on US1: 2-6 units ahead of EyePos, up to 2.5 aside, ~1 below. The held gun hangs off
    -- the same point (sh_worldmodel.lua:173). Read with GetField so nothing but the matrix is allocated; hg.eye's hull
    -- check is left to the viewer, which has the map. Inside a ragdoll the viewer uses the body's own eyes.
    -- Asking for a bone makes the server set the skeleton up: measured on US1 at ~16 us a player, which tripled this
    -- sampler. So the eye is read on every other sample (15 Hz at 30) and carried over in between - it is an offset from
    -- the position, which is still sampled every time. PROVISIONAL(2026-09-21, half-rate eye not yet judged by eye, ratify-by: 2026-10-21)
    local ex, ey, ez = 0, 0, 0
    if not IsValid(body) and cursor % 2 == 0 then
        ex, ey, ez = sex[i - 1], sey[i - 1], sez[i - 1]
    elseif not IsValid(body) then
        local neck = p:LookupBone("ValveBiped.Bip01_Neck1")
        local m = neck and p:GetBoneMatrix(neck)
        if m then
            local ahead = p.PlayerClassName == "Combine" and 8 or 4
            local pitch, yaw = rad(ang.p), rad(ang.y)
            local up = 2 * sin(pitch)
            ex = m:GetField(1, 4) + up * cos(yaw) - 4 * m:GetField(1, 2) + ahead * m:GetField(1, 1) - pos.x
            ey = m:GetField(2, 4) + up * sin(yaw) - 4 * m:GetField(2, 2) + ahead * m:GetField(2, 1) - pos.y
            ez = m:GetField(3, 4) + 2 * cos(pitch) - 4 * m:GetField(3, 2) + ahead * m:GetField(3, 1) - pos.z
            if ez <= 0 or ez > 100 or ex * ex + ey * ey > 2500 then ex, ey, ez = 0, 0, 0 end -- bones the server never set up
        end
    end
    sex[i], sey[i], sez[i] = ex, ey, ez
    -- The body's own state. Velocity is the true one (Entity:GetVelocity is authoritative server-side; the client may
    -- estimate), so the viewer stops differencing positions. Known custom animations use their authoritative owner
    -- clock; native animation falls back to the entity state. Client prediction/smoothing can still differ visually.
    local vel = p:GetVelocity()
    svx[i], svy[i], svz[i] = vel.x, vel.y, vel.z
    sseq[i], scyc[i], sbodyYaw[i], sanimMode[i] = K.AnimationState(p, ident[s], now)
    -- Pose parameters, by INDEX - Entity:GetPoseParameter takes an id as well as a name, so no per-model name table is
    -- needed, and the same indices mean the same thing on the replay ghost because it wears the same model. Server-side
    -- the value is already in the parameter's own units (it is the CLIENT that answers 0-1), which is the unit
    -- SetPoseParameter wants on either realm. Read on the samples the eye does NOT use, so the two heavy reads alternate
    -- rather than landing on the same tick. PROVISIONAL(2026-09-22, half-rate pose not yet judged by eye, ratify-by: 2026-10-22)
    local pb = (i - 1) * POSE_N
    local n = 0
    if poseOn:GetBool() and (cursor % 2 == 0 or cursor == 1) then
        n = p:GetNumPoseParameters()
        if n > POSE_N then n = POSE_N end
        for k = 1, n do spose[pb + k] = p:GetPoseParameter(k - 1) end
    elseif poseOn:GetBool() and cursor > 1 then
        n = spn[i - 1]
        local prev = (i - 2) * POSE_N
        for k = 1, n do spose[pb + k] = spose[prev + k] end
    end
    spn[i] = n
end

-- BEGIN RECORDED GORE: observe organism state and native flesh props; never run damage code.
do
    local G = {history = {}, nextAt = {}, gibs = {}, serial = 0}
    K.Gore = G
    G.Limbs = {"larm", "rarm", "lleg", "rleg", "head"}
    G.Bones = {"ValveBiped.Bip01_L_Forearm", "ValveBiped.Bip01_R_Forearm", "ValveBiped.Bip01_L_Calf", "ValveBiped.Bip01_R_Calf", "ValveBiped.Bip01_Head1"}
    G.GibModel = "models/props_junk/watermelon01_chunk02a.mdl"
    function G.Number(n, limit)
        return type(n) == "number" and n == n and math.abs(n) <= limit
    end
    function G.Wounds(org, now, out)
        out = out or {}
        local n = 0
        for kind = 1, 2 do
            local list = kind == 1 and org.wounds or org.arterialwounds
            for i = 1, math.min(istable(list) and #list or 0, kind == 1 and 30 or 10) do
                local w = list[i]
                local p, a = istable(w) and w[2], istable(w) and w[3]
                if p and a and type(w[4]) == "string" and #w[4] <= 96 and not w[4]:find("[%c]")
                    and G.Number(w[1], 100000) and w[1] > 0 and G.Number(w[5], 1e9)
                    and G.Number(p.x, 256) and G.Number(p.y, 256) and G.Number(p.z, 256)
                    and G.Number(a.p, 3600) and G.Number(a.y, 3600) and G.Number(a.r, 3600) then
                    n = n + 1
                    local row = out[n] or {}
                    row[1], row[2], row[3], row[4] = w[4], math.Round(p.x * 10), math.Round(p.y * 10), math.Round(p.z * 10)
                    row[5], row[6], row[7] = math.Round(a.p), math.Round(a.y), math.Round(a.r)
                    row[8], row[9], row[10] = math.min(math.Round(w[1]), 1000), w[5], kind
                    out[n] = row
                end
            end
        end
        for i = #out, n + 1, -1 do out[i] = nil end
        return out
    end
    function G.Same(a, b)
        if a.mask ~= b.mask or a.m ~= b.m or a.bleed ~= b.bleed or a.fem ~= b.fem or #a.w ~= #b.w then return false end
        for i, row in ipairs(a.w) do for k = 1, 10 do if row[k] ~= b.w[i][k] then return false end end end
        return true
    end
    function K.SampleGore(p, s, now, force)
        if not enabled:GetBool() then return end
        local uid, life = p:UserID(), lifeSerial[s] or 0
        local history = G.history[s]
        if not history or history.uid ~= uid or history.life ~= life then
            local previous = history and history.uid == uid and history or nil
            if previous then previous.previous = nil end
            history = {uid = uid, life = life, start = now, f = {}, previous = previous}
            G.history[s], G.nextAt[s] = history, nil
        end
        if not force and (G.nextAt[s] or 0) > now then return end
        G.nextAt[s] = now + 0.1
        local body = p.FakeRagdoll
        if not IsValid(body) and not p:Alive() and p.GetNWEntity then body = p:GetNWEntity("RagdollDeath") end
        if not IsValid(body) then body = p end
        local org = istable(body.organism) and body.organism or p.organism
        if not istable(org) then return end
        local frame = history.scratch or {w = {}}
        history.scratch = frame
        frame.t, frame.m, frame.mask = now, body:GetModel(), 0
        G.Wounds(org, now, frame.w)
        frame.bleed = G.Number(org.blood, 100000) and org.blood > 10 and 1 or 0
        frame.fem = ThatPlyIsFemale and (ThatPlyIsFemale(body) and 1 or 0) or nil
        for i, name in ipairs(G.Limbs) do
            if org[name .. "amputated"] or (name == "head" and body.headexploded) then frame.mask = frame.mask + 2 ^ (i - 1) end
        end
        local previous = history.f[#history.f]
        if previous and G.Same(previous, frame) then return end
        -- Burst origins are sampled world points. Never manufacture an explosion for a pre-existing amputation.
        frame.cuts = {}
        if previous then
            for i, boneName in ipairs(G.Bones) do
                local flag = 2 ^ (i - 1)
                if bit.band(frame.mask, flag) ~= 0 and bit.band(previous.mask, flag) == 0 and body.LookupBone then
                    local bone = body:LookupBone(boneName)
                    local matrix = bone and body:GetBoneMatrix(bone)
                    local pos = matrix and matrix:GetTranslation()
                    if pos and G.Number(pos.x, 1e7) and G.Number(pos.y, 1e7) and G.Number(pos.z, 1e7) then
                        frame.cuts[#frame.cuts + 1] = {i, pos.x, pos.y, pos.z}
                    end
                end
            end
        end
        history.f[#history.f + 1] = frame
        history.scratch = nil -- only changed snapshots become immutable history
        while #history.f > 128 or (#history.f > 1 and history.f[2].t < now - 21) do table.remove(history.f, 1) end
    end
    function K.GoreRows(s, uid, t0, t1, death, origin)
        local history = G.history[s]
        local endAt
        if history and history.start > death then endAt, history = history.start, history.previous end
        if not history or history.uid ~= uid then return end
        if history.start > death then return end
        local result, anchor = {v = 1, f = {}}, nil
        for i, frame in ipairs(history.f) do if frame.t <= t0 then anchor = i end end
        for i = anchor or 1, #history.f do
            local f = history.f[i]
            if f.t <= t1 and (i == anchor or f.t >= t0) then
                local row = {math.Round((math.max(t0, f.t) - death) * 100), f.mask, f.m, {}, f.bleed, {}, f.fem}
                for _, wound in ipairs(f.w) do
                    local w = {} for k = 1, 10 do w[k] = wound[k] end
                    w[9] = math.Round((w[9] - death) * 100)
                    row[4][#row[4] + 1] = w
                end
                if f.t >= t0 then
                    for _, c in ipairs(f.cuts) do row[6][#row[6] + 1] = {c[1], math.Round((c[2] - origin.x) * 10), math.Round((c[3] - origin.y) * 10), math.Round((c[4] - origin.z) * 10)} end
                end
                result.f[#result.f + 1] = row
            end
        end
        if #result.f > 0 and endAt and endAt <= t1 then
            local last = result.f[#result.f]
            result.f[#result.f + 1] = {math.Round((endAt - death) * 100), 0, last[3], {}, 0, {}, last[7]}
        end
        return #result.f > 0 and result or nil
    end
    hook.Add("OnAmputateLimb", "ZCKillcam.Gore", function(org)
        local p = istable(org) and org.owner
        local s = IsValid(p) and p:IsPlayer() and slotOf(p)
        if s then K.SampleGore(p, s, CurTime(), true) end
    end)
    function G.TrackGib(ent)
        if not enabled:GetBool() or not IsValid(ent) or ent:GetClass() ~= "prop_physics"
            or ent:GetModel() ~= G.GibModel or ent:GetSubMaterial(0) ~= "models/flesh" then return end
        for _, track in ipairs(G.gibs) do if track.ent == ent then return end end
        -- Prefer fresh events when the bounded capture is full (Homicide chunks can persist indefinitely).
        if #G.gibs >= 32 then table.remove(G.gibs, 1) end
        G.serial = G.serial + 1
        G.gibs[#G.gibs + 1] = {ent = ent, id = G.serial, f = {}}
    end
    hook.Add("OnEntityCreated", "ZCKillcam.Gib", function(ent)
        if not enabled:GetBool() then return end
        timer.Simple(0, function() G.TrackGib(ent) end)
    end)
    function K.SampleGibs(now)
        if not enabled:GetBool() or (G.nextGib or 0) > now then return end
        G.nextGib = now + 0.1
        for i = #G.gibs, 1, -1 do
            local track = G.gibs[i]
            local ent = track.ent
            if not track.ended and IsValid(ent) and ent:GetModel() == G.GibModel and ent:GetSubMaterial(0) == "models/flesh" and not ent:GetNoDraw() then
                local p, a, scale = ent:GetPos(), ent:GetAngles(), ent:GetModelScale()
                if G.Number(p.x, 1e7) and G.Number(p.y, 1e7) and G.Number(p.z, 1e7)
                    and G.Number(a.p, 3600) and G.Number(a.y, 3600) and G.Number(a.r, 3600) and G.Number(scale, 10) then
                    track.f[#track.f + 1] = {now, p.x, p.y, p.z, a.p, a.y, a.r, scale}
                    while #track.f > 211 do table.remove(track.f, 1) end
                end
            else track.ended = track.ended or now end
            if track.ended and track.ended < now - 21 then table.remove(G.gibs, i) end
        end
    end
    function K.GibRows(t0, t1, death, origin, radius)
        local out = {}
        for _, track in ipairs(G.gibs) do
            local f, near, anchor = {}, false, nil
            for i, r in ipairs(track.f) do if r[1] <= t0 then anchor = i end end
            for i = anchor or 1, #track.f do
                local r = track.f[i]
                if r[1] <= t1 and (i == anchor or r[1] >= t0) then
                    local x, y, z = r[2] - origin.x, r[3] - origin.y, r[4] - origin.z
                    if x*x + y*y + z*z <= radius*radius then near = true end
                    f[#f + 1] = {math.Round((r[1] - death) * 100), math.Round(x * 10), math.Round(y * 10), math.Round(z * 10), math.Round(r[5]), math.Round(r[6]), math.Round(r[7]), math.Round(r[8] * 1000)}
                end
            end
            if near and #f > 0 then out[#out + 1] = {m = G.GibModel, f = f} end
        end
        return #out > 0 and out or nil
    end
end
-- END RECORDED GORE

-- BEGIN RECORDED OBJECTS (owner 2026-09-24: "record prop-kills and grenades in a proper way"). Things that fly:
-- a grenade or any other ent_hg_* projectile from the moment it exists, and a physics prop from the moment the hands
-- weapon lets go of it. Sampled at 20 Hz in the gib-track shape (model + frames), so the clip cutter and the client
-- treat them exactly like gibs, tagged k = "throw" | "prop" so the client draws the real model. Nothing here runs
-- damage code; attribution happens in the hit hook through K.ObjectThrower.
do
    local O = {tracks = {}, serial = 0}
    K.Objects = O
    local OBJ_MAX, OBJ_FRAMES, OBJ_LIFE, OBJ_HZ = 16, 211, 12, 1 / 20
    local function fin(v, lim) return isnumber(v) and v == v and math.abs(v) < lim end
    local function owner(ent)
        local o = ent.GetOwner and ent:GetOwner()
        if not (IsValid(o) and o:IsPlayer()) then o = ent.Owner end
        if not (IsValid(o) and o:IsPlayer()) then o = ent.owner end
        if not (IsValid(o) and o:IsPlayer()) then o = ent.thrower end
        if not (IsValid(o) and o:IsPlayer()) and ent.GetPhysicsAttacker then o = ent:GetPhysicsAttacker(5) end
        return IsValid(o) and o:IsPlayer() and o or nil
    end
    -- kind "throw" (projectile) | "prop" (a physics prop somebody let go of); `by` the player, when known now.
    function K.TrackObject(ent, kind, by)
        if not enabled:GetBool() or not IsValid(ent) or ent:IsPlayer() then return end
        local model = ent:GetModel()
        if not isstring(model) or model == "" then return end
        by = IsValid(by) and by:IsPlayer() and by or owner(ent)
        for _, t in ipairs(O.tracks) do
            -- still in flight (or carried before it came to rest): one continuous track; a finished one starts a new track
            if t.ent == ent and not t.ended then t.still, t.born = nil, CurTime() if by then t.by = by:UserID() end return end
        end
        if #O.tracks >= OBJ_MAX then table.remove(O.tracks, 1) end
        O.serial = O.serial + 1
        O.tracks[#O.tracks + 1] = {ent = ent, kind = kind, model = model, id = O.serial, f = {}, by = by and by:UserID() or nil, born = CurTime(), c = ent:GetClass()}
        stats.objects = (stats.objects or 0) + 1
    end
    -- Who let go of this thing, if the recorder saw it happen (falls back to the entity's own owner fields).
    function K.ObjectThrower(ent)
        if not IsValid(ent) then return nil end
        for _, t in ipairs(O.tracks) do
            if t.ent == ent then
                local p = t.by and Player(t.by)
                if IsValid(p) and p:IsPlayer() then return p end
            end
        end
        return owner(ent)
    end
    hook.Add("OnEntityCreated", "ZCKillcam.Object", function(ent)
        if not enabled:GetBool() then return end
        timer.Simple(0, function()
            if IsValid(ent) and string.sub(ent:GetClass(), 1, 7) == "ent_hg_" then K.TrackObject(ent, "throw") end
        end)
    end)
    function K.SampleObjects(now)
        if not enabled:GetBool() or (O.nextAt or 0) > now then return end
        O.nextAt = now + OBJ_HZ
        for i = #O.tracks, 1, -1 do
            local t = O.tracks[i]
            local ent = t.ent
            if not t.ended and IsValid(ent) and not (ent.GetNoDraw and ent:GetNoDraw()) and now - t.born <= OBJ_LIFE then
                if not t.by then local o = owner(ent) if o then t.by = o:UserID() end end
                local p, a, scale = ent:GetPos(), ent:GetAngles(), ent:GetModelScale()
                if fin(p.x, 1e7) and fin(p.y, 1e7) and fin(p.z, 1e7) and fin(a.p, 3600) and fin(a.y, 3600) and fin(a.r, 3600) and fin(scale, 10) then
                    local last = t.f[#t.f]
                    local moved = not last or (last[2] - p.x) ^ 2 + (last[3] - p.y) ^ 2 + (last[4] - p.z) ^ 2 > 1
                    if moved then t.still = nil else t.still = t.still or now end
                    -- a prop that has come to rest for a second is done; a projectile is sampled until it is gone
                    if t.kind == "prop" and t.still and now - t.still > 1 then
                        t.ended = now
                    else
                        t.f[#t.f + 1] = {now, p.x, p.y, p.z, a.p, a.y, a.r, scale}
                        while #t.f > OBJ_FRAMES do table.remove(t.f, 1) end
                    end
                end
            else
                t.ended = t.ended or now
            end
            if t.ended and t.ended < now - 21 then table.remove(O.tracks, i) end
        end
    end
    -- Rows in the gib format (K.GibRows), tagged with the kind: {m = model, k = kind, f = frames}.
    function K.ObjectRows(t0, t1, death, origin, radius)
        local out = {}
        for _, t in ipairs(O.tracks) do
            local f, near, anchor = {}, false, nil
            for i, row in ipairs(t.f) do if row[1] <= t0 then anchor = i end end
            for i = anchor or 1, #t.f do
                local row = t.f[i]
                if row[1] <= t1 and (i == anchor or row[1] >= t0) then
                    local x, y, z = row[2] - origin.x, row[3] - origin.y, row[4] - origin.z
                    if x * x + y * y + z * z <= radius * radius then near = true end
                    f[#f + 1] = {math.Round((row[1] - death) * 100), math.Round(x * 10), math.Round(y * 10), math.Round(z * 10), math.Round(row[5]), math.Round(row[6]), math.Round(row[7]), math.Round(row[8] * 1000)}
                end
            end
            -- O1 (2026-09-25): by = the thrower's UserID, c = the entity class, so the client can tell two throws apart
            if near and #f > 1 then out[#out + 1] = {m = t.model, k = t.kind, f = f, by = t.by, c = t.c} end
        end
        return #out > 0 and out or nil
    end
    hook.Add("ZB_PreRoundStart", "ZCKillcam.Objects", function() O.tracks = {} end)
end
-- END RECORDED OBJECTS

function K.Sample()
    if not enabled:GetBool() then return end
    local began = SysTime()
    local now = CurTime()
    local n = 0
    for _, p in ipairs(player.GetAll()) do
        local s = slotOf(p)
        if s then
            claim(p, s)
            write(p, s, now)
            K.SampleGore(p, s, now)
            n = n + 1
        end
    end
    K.SampleGibs(now)
    K.SampleObjects(now)
    local cost = SysTime() - began
    stats.samples, stats.runs, stats.sum = stats.samples + n, stats.runs + 1, stats.sum + cost
    if cost > stats.max then stats.max = cost end
end

-- An exact extra sample at the moment of a hit, so a flick shot replays on target instead of
-- interpolating past it. At most five a second per player, so a long burst cannot eat the ring.
local lastStamp = {}
function K.Stamp(p, s, now)
    if (lastStamp[s] or 0) > now then return end
    lastStamp[s] = now + 0.2
    write(p, s, now)
end
timer.Create("ZCKillcam.Sample", 1 / HZ, 0, K.Sample)
timer.Create("ZCKillcam.Look", LOOK_GAP, 0, K.Look) -- what players wear, well off the sampler's path

-- Every bullet is an event (owner, 2026-09-21: each one gets its true line). Only calls inside the same 20 ms merge: the
-- pellets of one shotgun blast. The fastest gun fires every 50 ms, so the event ring was doubled to 4096.
-- BEGIN SHOT TELEMETRY: immutable launch facts, never a client weapon-definition lookup.
do
    local function number(n, maximum)
        return type(n) == "number" and n == n and n > 0 and n <= maximum and n or nil
    end
    function K.ShotBallistics(info)
        if not istable(info) then return end
        local ammo = info.AmmoType
        if type(ammo) == "number" and game.GetAmmoName then ammo = game.GetAmmoName(ammo) end
        local def = type(ammo) == "string" and hg and hg.ammotypeshuy and hg.ammotypeshuy[ammo]
        if not istable(def) or not istable(def.BulletSettings) then return end
        -- sh_ammostuff keys this registry by display name; def.name is the internal ammo ID.
        local name = ammo
        local out = {v = 1}
        -- Native ZCity bullet.Speed is a launch setting in m/s, not measured arrival velocity.
        out.muzzle = number(info.Speed, 10000)
        out.diameter = number(def.BulletSettings.Diameter, 100)
        if type(name) == "string" and #name > 0 and #name <= 64 and not name:find("[%c]") then out.caliber = name end
        if out.muzzle or out.diameter or out.caliber then return out end
    end
end
-- END SHOT TELEMETRY

local lastShot, shotEvent = {}, {}
local function recordShot(ent, info, weapon)
    if not enabled:GetBool() or not IsValid(ent) then return end
    -- Z-City's Lua bullets fire from the weapon entity, not the player.
    if not ent:IsPlayer() then ent = info and info.Attacker or ent:GetOwner() end
    if not IsValid(ent) or not ent:IsPlayer() then return end
    local s = slotOf(ent)
    if not s then return end
    local now = CurTime()
    if (lastShot[s] or 0) > now then return end
    lastShot[s] = now + 0.02
    stats.shots = stats.shots + 1
    local i = push(EV_SHOT, s, 0, 0, 0, weaponId(IsValid(weapon) and weapon or ent:GetActiveWeapon()), false)
    eballistics[i] = K.ShotBallistics(info)
    shotEvent[s] = {i = i, at = now, uid = ent:UserID(), life = lifeSerial[s] or 0}
    local src, dir = info and info.Src, info and info.Dir
    if src and dir then -- read, never written: the bullet is not ours to change
        local dx, dy, dz = dir.x, dir.y, dir.z
        epx[i], epy[i], epz[i] = src.x, src.y, src.z
        eyaw[i], epitch[i] = math.deg(math.atan2(dy, dx)), math.deg(math.atan2(-dz, math.sqrt(dx * dx + dy * dy)))
    end
    K.Stamp(ent, s, now) -- exact aim at the shot, not only at hits
    -- No return value: this hook must never alter the bullet.
end
hook.Add("EntityFireBullets", "ZCKillcam.Shot", recordShot)
-- Native contact damage has no simulated bullet. Its owner emits this once per discharge,
-- before applying damage; observing it must not synthesize engine hooks or fire another shot.
hook.Add("ZCityHostageContactShot", "ZCKillcam.ContactShot", function(owner, weapon, source, direction)
    if not IsValid(weapon) or not isvector(source) or not isvector(direction) then return end
    recordShot(owner, {Src = source, Dir = direction, AmmoType = weapon.Primary and weapon.Primary.Ammo}, weapon)
end)

-- The organism owner exposes its wound-trace endpoints immediately before HomigradDamage.
-- Copy only one unambiguous bullet corridor, never infer an exit from a body box. These are
-- simulation trace endpoints (not an anatomical surface or proof of a particular organ injury).
-- At most one pending record per player slot; consume only the same damage object, tick and life.
local pendingBody = {}
local function bodyVictim(p)
    if IsValid(p) and not p:IsPlayer() and hg and hg.RagdollOwner then p = hg.RagdollOwner(p) end
    return IsValid(p) and p:IsPlayer() and p or nil
end
local function finitePoint(p)
    return isvector(p) and p.x == p.x and p.y == p.y and p.z == p.z
        and math.abs(p.x) < 1e7 and math.abs(p.y) < 1e7 and math.abs(p.z) < 1e7
end
-- BEGIN RECORDED PENETRATION
local V2_REASONS = {lodged = true, exited = true, maxpen = true, boundary = true, limit = true}
local V2_MARKS = {entry = true, deflect = true, lodge = true, maxpen = true, exit = true, armor = true, expand = true, fragment = true}
local V2_MARK_LIMIT = 12
local function finiteNumber(value, minimum, maximum)
    return type(value) == "number" and value == value and value >= minimum and value <= maximum
end
local function boundedInteger(value, minimum, maximum)
    if finiteNumber(value, minimum, maximum) and value % 1 == 0 then return value end
end
local function copyV2(trace, first)
    local raw = trace.v2
    if not istable(raw) or raw.v ~= 2 or not V2_REASONS[raw.reason]
        or not finiteNumber(raw.e, 0, 1) then return end
    local modeConVar = GetConVar("hg_ballistics_v2")
    local mode = modeConVar and modeConVar:GetInt() or 0
    if mode < 1 or mode > 2 then return end

    local out = {
        v = 2,
        mode = mode == 2 and "live" or "shadow",
        reason = raw.reason,
        energy = raw.e,
        deflections = boundedInteger(raw.deflects, 0, 8) or 0,
        armored = raw.armored == true,
        expanded = raw.expanded == true,
        fragments = boundedInteger(raw.fragments, 0, 16) or 0,
        events = {},
    }
    if not istable(raw.events) then return out end
    for i = 1, math.min(#raw.events, 256) do
        local event = raw.events[i]
        local pos = istable(event) and event.pos
        if istable(event) and V2_MARKS[event.kind] and finitePoint(pos)
            and pos:DistToSqr(first) <= 150 * 150 then
            out.events[#out.events + 1] = {
                event.kind,
                pos.x,
                pos.y,
                pos.z,
                boundedInteger(event.frag, 1, 16),
            }
            if #out.events >= V2_MARK_LIMIT then break end
        end
    end
    return out
end
function K.CopyPenetration(entry, data)
    local trace = istable(data) and data.trace_result
    if not istable(trace) or trace.v ~= 1 or type(trace.reason) ~= "number"
        or trace.reason % 1 ~= 0 or trace.reason < 1 or trace.reason > 5
        or not istable(trace.points) or #trace.points < 1 or #trace.points > 20
        or not istable(entry) or #entry ~= 1 or not finitePoint(entry[1]) then return end
    local points = {{entry[1].x, entry[1].y, entry[1].z}}
    local previous, length = entry[1], 0
    for _, point in ipairs(trace.points) do
        if not finitePoint(point) then return end
        local step = previous:Distance(point)
        length = length + step
        if length > 100 then return end
        if step >= 0.01 then
            points[#points + 1] = {point.x, point.y, point.z}
            previous = point
        end
    end
    -- No zero-distance continuation, and never promote a native guard to a stop.
    if length < 0.01 and trace.reason ~= 1 then return end
    return {v = 1, reason = trace.reason, points = points, v2 = copyV2(trace, entry[1])}
end
-- END RECORDED PENETRATION

-- BEGIN IMPACT TELEMETRY: the native Lua bullet hook runs before its damage dispatch.
local pendingImpact = {}
hook.Add("PostEntityFireBullets", "ZCKillcam.ImpactFacts", function(ent, data)
    if not enabled:GetBool() or not istable(data) then return end
    local tr = data.Trace
    if not istable(tr) then return end
    local victim = bodyVictim(tr.Entity)
    local v = victim and slotOf(victim)
    if not v then return end
    pendingImpact[v] = nil
    local attacker = data.Attacker
    if not IsValid(attacker) and IsValid(ent) then attacker = ent:IsPlayer() and ent or ent:GetOwner() end
    local a = IsValid(attacker) and attacker:IsPlayer() and slotOf(attacker)
    local launch = a and shotEvent[a]
    if not launch or launch.at ~= CurTime() or launch.uid ~= attacker:UserID()
        or launch.life ~= (lifeSerial[a] or 0) or et[launch.i] ~= launch.at or ek[launch.i] ~= EV_SHOT
        or not tr.Hit or tr.HitSky or not finitePoint(tr.StartPos) or not finitePoint(tr.HitPos)
        or not finitePoint(tr.HitNormal) or not finitePoint(tr.Normal) then return end
    -- Only the original segment: a ricochet/penetration retrace is not muzzle-to-impact range.
    local origin = Vector(epx[launch.i], epy[launch.i], epz[launch.i])
    if origin:DistToSqr(tr.StartPos) > 4 then return end
    local length = tr.StartPos:Distance(tr.HitPos)
    if length < 0.1 or length > 1e6 or tr.HitNormal:LengthSqr() < 0.01 or tr.Normal:LengthSqr() < 0.01 then return end
    local direction, normal = tr.Normal:GetNormalized(), tr.HitNormal:GetNormalized()
    if direction:Dot((tr.HitPos - tr.StartPos):GetNormalized()) < 0.99 then return end
    local cosine = -direction:Dot(normal)
    if cosine < -0.001 then return end -- outward-facing or invalid normal
    local facts = {v = 1, range = length / 52.5, angle = math.deg(math.acos(math.Clamp(cosine, 0, 1)))}
    local shot = eballistics[launch.i]
    if shot then facts.muzzle, facts.caliber, facts.diameter = shot.muzzle, shot.caliber, shot.diameter end
    pendingImpact[v] = {at = CurTime(), a = a, auid = attacker:UserID(), uid = victim:UserID(),
        life = lifeSerial[v] or 0, x = tr.HitPos.x, y = tr.HitPos.y, z = tr.HitPos.z, facts = facts}
    -- Observe only: no return, callback replacement or damage changes.
end)
local function takeImpact(v, victim, a, attacker, info)
    local pending = pendingImpact[v]
    pendingImpact[v] = nil
    if not pending or pending.at ~= CurTime() or pending.a ~= a or pending.auid ~= attacker:UserID()
        or pending.uid ~= victim:UserID() or pending.life ~= (lifeSerial[v] or 0)
        or not info.IsDamageType or not info:IsDamageType(DMG_BULLET) or info:IsDamageType(DMG_BUCKSHOT) then return end
    local p = info.GetDamagePosition and info:GetDamagePosition()
    if finitePoint(p) and p:DistToSqr(Vector(pending.x, pending.y, pending.z)) <= 4 then return pending.facts end
end
-- END IMPACT TELEMETRY

-- The organ rows a round crossed (`boxes` = the walk's hitBoxs set, indices into the SAME tick's ShootMatrixTick boxes
-- sv_input walked). Entry order and energy share come from the V2 result when there is one (trace.v2.hits); a v1
-- walk only knows the set, listed by box index. Fenced by the caller: a surprise here costs the list, never the hit.
local ORGAN_LIMIT = 12
local function organList(ent, boxes, data)
    local org = hg and hg.organism
    if not istable(boxes) or next(boxes) == nil or not istable(org) or not isfunction(org.GetHitBoxOrgans)
        or not isfunction(org.ShootMatrixTick) then return nil end
    local body = isfunction(hg.GetCurrentCharacter) and hg.GetCurrentCharacter(ent) or ent
    if not IsValid(body) then return nil end
    local organs = org.GetHitBoxOrgans(body:GetModel(), body)
    if not istable(organs) then return nil end
    local boxs = org.ShootMatrixTick(body, organs)
    if not istable(boxs) then return nil end
    local trace = istable(data) and data.trace_result
    local raw = istable(trace) and trace.v2
    local order, dep = {}, {}
    if istable(raw) and istable(raw.hits) then
        for _, h in ipairs(raw.hits) do
            local i = istable(h) and h.box
            if isnumber(i) and boxes[i] and not h.frag then
                if dep[i] == nil then order[#order + 1] = i dep[i] = 0 end
                dep[i] = dep[i] + (tonumber(h.dep) or 0)
            end
        end
    end
    local rest = {}
    for i in pairs(boxes) do if isnumber(i) and dep[i] == nil then rest[#rest + 1] = i end end
    table.sort(rest)
    for _, i in ipairs(rest) do order[#order + 1] = i end
    local V2 = org.BallisticsV2
    local out = {}
    for _, i in ipairs(order) do
        local box = boxs[i]
        local rows = istable(box) and box[6] ~= nil and organs[box[6]]
        local row = istable(rows) and rows[box[7]]
        if istable(row) and isstring(row[1]) and isstring(box[6]) and isnumber(box[7]) then
            local label = isfunction(org.OrganLabel) and org.OrganLabel(row) or row[1]
            local class = istable(V2) and isfunction(V2.Classify) and V2.Classify(row) or nil
            out[#out + 1] = {bone = box[6], key = box[7], name = row[1], label = tostring(label), class = class,
                dep = raw and dep[i] and math.Round(math.Clamp(dep[i], 0, 1), 3) or nil}
            if #out >= ORGAN_LIMIT then break end
        end
    end
    return #out > 0 and out or nil
end
hook.Add("PreHomigradDamageBulletBleedAdd", "ZCKillcam.BodyTrace", function(p, _, info, _, _, boxes, entry, data)
    if not enabled:GetBool() then return end
    local hurt = p
    p = bodyVictim(p)
    local v = p and slotOf(p)
    if not v then return end
    pendingBody[v] = nil
    if not info or not info.IsDamageType or not info:IsDamageType(DMG_BULLET)
        or info:IsDamageType(DMG_BUCKSHOT) then return end
    local fine, organs = pcall(organList, hurt, boxes, data)
    if not fine then organs = nil end
    local penetration = istable(boxes) and next(boxes) ~= nil and K.CopyPenetration(entry,data)
    if penetration then
        local a,b = penetration.points[1],penetration.points[#penetration.points]
        pendingBody[v] = {info=info,at=CurTime(),uid=p:UserID(),life=lifeSerial[v] or 0,
            points={a[1],a[2],a[3],b[1],b[2],b[3]},penetration=penetration,organs=organs}
        return
    end
    local out = istable(data) and data.output_hole
    local a, b = istable(entry) and #entry == 1 and entry[1], istable(out) and #out == 1 and out[1]
    local span = finitePoint(a) and finitePoint(b) and a:Distance(b) or 0
    if not istable(boxes) or next(boxes) == nil or span < 1 or span > 100 then
        -- no usable corridor: still keep what the round crossed
        if organs then pendingBody[v] = {info = info, at = CurTime(), uid = p:UserID(), life = lifeSerial[v] or 0, organs = organs} end
        return
    end
    pendingBody[v] = {info = info, at = CurTime(), uid = p:UserID(), life = lifeSerial[v] or 0,
        points = {a.x, a.y, a.z, b.x, b.y, b.z}, organs = organs}
end)
local function takeBody(v, p, info)
    local data = pendingBody[v]
    pendingBody[v] = nil
    if data and data.info == info and data.at == CurTime() and data.uid == p:UserID()
        and data.life == (lifeSerial[v] or 0) then return data.points, data.penetration, data.organs end
end

-- Pellets and rapid hits on the same pair merge into the previous hit event.
local losTrace, losResult = {mask = MASK_SHOT, output = nil}, {}
losTrace.output = losResult
hook.Add("HomigradDamage", "ZCKillcam.Hit", function(ply, dmgInfo, hitgroup, ent, harm)
    if not enabled:GetBool() then return end
    local victim = ply
    if IsValid(victim) and not victim:IsPlayer() and hg and hg.RagdollOwner then victim = hg.RagdollOwner(victim) end
    local attacker = dmgInfo:GetAttacker()
    -- P8 (owner 2026-09-24): a prop kill or a grenade names the prop / the grenade (or the world) as the attacker.
    -- The player behind it is the one the recorder saw let go of it, else the entity's physics attacker or owner.
    -- `via` is the thing that actually hit, and it labels the hit instead of the thrower's current weapon.
    local via
    local infl = dmgInfo.GetInflictor and dmgInfo:GetInflictor()
    if IsValid(infl) and (infl:IsPlayer() or infl:IsWeapon()) then infl = nil end
    if not (IsValid(attacker) and attacker:IsPlayer()) then
        local thing = infl or (IsValid(attacker) and not attacker:IsPlayer() and attacker or nil)
        local who = thing and K.ObjectThrower(thing)
        if who then attacker, via = who, thing end
    elseif IsValid(infl) then
        via = infl -- a grenade with its attacker set properly still gets labelled as the grenade
    end
    if not IsValid(victim) or not victim:IsPlayer() or not IsValid(attacker) or not attacker:IsPlayer() or attacker == victim then return end
    local a, v = slotOf(attacker), slotOf(victim)
    if not a or not v then return end
    local facts = takeImpact(v, victim, a, attacker, dmgInfo)
    local corridor, penetration, organs = takeBody(v, victim, dmgInfo)
    claim(victim, v)
    claim(attacker, a).traitor = attacker.isTraitor == true
    local amount = tonumber(harm) or 0
    local now = CurTime()
    if ehead > 0 and ek[ehead] == EV_HIT and ea[ehead] == a and eb[ehead] == v and eu[ehead] == attacker:UserID()
        and victimUID[ehead] == victim:UserID() and victimLife[ehead] == (lifeSerial[v] or 0)
        and now - et[ehead] < 0.05 then
        epenetration[ehead] = nil
        eorgans[ehead] = nil
        eballistics[ehead] = nil
        ebody[ehead], eballistic[ehead] = nil, 0 -- merged pellets/hits have no single reliable corridor
        ed[ehead] = ed[ehead] + amount
        return
    end
    losTrace.start, losTrace.endpos, losTrace.filter = attacker:EyePos(), victim:WorldSpaceCenter(), attacker
    util.TraceLine(losTrace)
    local body = victim.FakeRagdoll
    local clear = not losResult.Hit or losResult.Entity == victim or (IsValid(body) and losResult.Entity == body)
    stats.hits = stats.hits + 1
    local before = (v - 1) * DEPTH + ((head[v] or 0) - 1) % DEPTH + 1 -- A1: the newest sample BEFORE this hit's stamp
    K.Stamp(attacker, a, now)
    K.Stamp(victim, v, now)
    local wep = via and K.LabelOf(via) or weaponId(attacker:GetActiveWeapon())
    if via then stats.objectHits = (stats.objectHits or 0) + 1 end
    local i = push(EV_HIT, a, v, amount, hitgroup, wep, clear, attacker:UserID())
    eballistics[i] = facts
    ebody[i] = corridor
    epenetration[i] = penetration
    eorgans[i] = organs
    eballistic[i] = dmgInfo.IsDamageType and dmgInfo:IsDamageType(DMG_BULLET)
        and not dmgInfo:IsDamageType(DMG_BUCKSHOT) and 1 or 0
    local at = dmgInfo.GetDamagePosition and dmgInfo:GetDamagePosition() -- where the bullet landed; the engine leaves it at the origin when it does not know
    if at and (at.x ~= 0 or at.y ~= 0 or at.z ~= 0) then epx[i], epy[i], epz[i] = at.x, at.y, at.z end
    eanchor[i] = nil -- the ring reuses indices
    if epx[i] then -- A1: the same point in body space and hit-bone space, and how far the hook's body sits from the samples.
        -- Fenced: this runs inside the gamemode's damage path, so a surprise here costs the anchor, never the hit.
        local ok = pcall(function()
        local body = victim.FakeRagdoll
        local down = IsValid(body)
        local ref = down and body or victim -- what write() samples as the position
        local rpos = ref:GetPos()
        local anchor = {v = 1}
        -- A1r (2026-09-25): a downed victim is drawn as its ragdoll, and the player entity's own skeleton is not where
        -- that body lies: the hit bone is read off the ragdoll (r = 1). Body space (eye yaw around the root) means
        -- nothing for a body on the ground, so it is only sent for a standing one.
        if down then
            anchor.r = 1
            stats.anchorRag = (stats.anchorRag or 0) + 1
        else
            local b = WorldToLocal(at, angle_zero, rpos, Angle(0, victim:EyeAngles().y, 0))
            anchor.b = {math.Round(b.x * 10), math.Round(b.y * 10), math.Round(b.z * 10)}
        end
        local k = HIT_BONE[hitgroup]
        local id = k and ref:LookupBone(HIT_BONES[k])
        local m = id and ref:GetBoneMatrix(id)
        if m then
            local l = WorldToLocal(at, angle_zero, m:GetTranslation(), m:GetAngles())
            anchor.k, anchor.l = k, {math.Round(l.x * 10), math.Round(l.y * 10), math.Round(l.z * 10)}
        end
        if (st[before] or 0) > 0 and owner[v] ~= -1 then
            anchor.rw = math.Round(rpos:Distance(Vector(sx[before], sy[before], sz[before])) * 10)
            anchor.age = math.Round((now - st[before]) * 100)
            local imp = stats.impact
            if not imp then imp = {n = 0, sum = 0, max = 0, sumAge = 0} stats.impact = imp end
            imp.n, imp.sum, imp.sumAge = imp.n + 1, imp.sum + anchor.rw / 10, imp.sumAge + anchor.age
            if anchor.rw / 10 > imp.max then imp.max = anchor.rw / 10 end
        end
        eanchor[i] = anchor
        end)
        if not ok then stats.anchorErrors = (stats.anchorErrors or 0) + 1 end
    end
    hook.Run("ZCKillcam_Hit", attacker, victim, a, v, wep) -- the life-sequence recorder opens or extends an instance
end)

-- The killer is the owner of the last hit on the victim inside the clip window:
-- in a body-sim game most deaths are bleed-outs, and the engine attacker is unreliable.
function K.LastAttacker(v, now)
    local i = ehead
    for _ = 1, math.min(ecount, EVENTS) do
        if now - et[i] > PRE then return end
        if ek[i] == EV_HIT and eb[i] == v and ident[v]
            and victimUID[i] == ident[v].uid and victimLife[i] == (lifeSerial[v] or 0) then return ea[i], eu[i] end
        i = i - 1
        if i < 1 then i = EVENTS end
    end
end

-- Owner rule: innocent kills traitor -> traitor's record; innocent kills innocent -> both.
function K.Classify(killerTraitor, victimTraitor)
    if killerTraitor then return nil end
    return victimTraitor and "t_killed" or "ivi"
end

hook.Add("PlayerDeath", "ZCKillcam.Death", function(victim)
    if not enabled:GetBool() or not IsValid(victim) then return end
    local v = slotOf(victim)
    if not v then return end
    claim(victim, v)
    local a, uid = K.LastAttacker(v, CurTime())
    -- The slot must still belong to the player who landed the hit, or nobody is named.
    local killer = a and ident[a]
    if killer and killer.uid ~= uid then killer = nil end
    if not killer then a, uid = nil, nil end
    stats.deaths = stats.deaths + 1
    if killer then
        local live = Entity(a)
        -- Roles are read now; round cleanup may clear them a frame later.
        if IsValid(live) and live:IsPlayer() and live:UserID() == uid then killer.traitor = live.isTraitor == true end
    end
    local tag = killer and K.Classify(killer.traitor, victim.isTraitor == true) or nil
    if tag then stats.wouldSave = stats.wouldSave + 1 end
    push(EV_DEATH, a or 0, v, 0, 0, 0, false, uid)
    hook.Run("ZCKillcam_Death", victim, killer, tag) -- phase 2 cuts the clip; `killer` is an identity table
end)

-- Read API for the clip cutter and tests. Visits samples of one slot inside [t0, t1], oldest first.
function K.EachSample(slot, t0, t1, fn)
    if owner[slot] == -1 then return end -- never-used slot: nothing to walk
    local base, cursor = (slot - 1) * DEPTH, head[slot] or 0
    for k = 1, DEPTH do
        local i = base + (cursor + k - 1) % DEPTH + 1
        local t = st[i]
        -- `pose` and `pbase` hand the reader the flat pose block rather than ten more arguments: values live at
        -- pose[pbase + 1 .. pbase + pn], and pn is 0 when this sample has none (recording off, or a model with none).
        if t > 0 and t >= t0 and t <= t1 then fn(t, sx[i], sy[i], sz[i], syaw[i], spitch[i], sflags[i], swep[i], shp[i], seye[i], sex[i], sey[i], sez[i],
            svx[i], svy[i], svz[i], sseq[i], scyc[i], spose, (i - 1) * POSE_N, spn[i], sbodyYaw[i], sanimMode[i], sgrip[i], scarry[i], scx[i], scy[i], scz[i], scp[i], scyaw[i]) end
    end
end
function K.EachEvent(t0, t1, fn)
    local count = math.min(ecount, EVENTS)
    for k = count - 1, 0, -1 do
        local i = (ehead - k - 1) % EVENTS + 1
        if et[i] >= t0 and et[i] <= t1 then fn(et[i], ek[i], ea[i], eb[i], ed[i], eg[i], ew[i], el[i] == 1, eu[i], epx[i], epy[i], epz[i], eyaw[i], epitch[i], ebody[i], eballistic[i], eballistics[i], epenetration[i], eswing[i], eanchor[i], eorgans[i]) end
    end
end

concommand.Add("zc_killcam_stats", function(p)
    if IsValid(p) and not p:IsAdmin() then return end
    local runs = math.max(stats.runs, 1)
    local line = string.format("[Killcam %s] enabled=%s runs=%d samples=%d avg=%.1fus max=%.1fus shots=%d hits=%d deaths=%d wouldSave=%d weapons=%d adsErrors=%d luaKB=%d",
        K.Version, tostring(enabled:GetBool()), stats.runs, stats.samples, stats.sum / runs * 1e6, stats.max * 1e6,
        stats.shots, stats.hits, stats.deaths, stats.wouldSave, #wepName, stats.adsErrors or 0, collectgarbage("count"))
    if IsValid(p) then p:PrintMessage(HUD_PRINTCONSOLE, line) else print(line) end
    local imp = stats.impact -- A1: how far the lag-compensated body sat from the newest sample at each hit
    if imp and imp.n > 0 then
        local rw = string.format("[Killcam] impact rewind: hits=%d avg=%.1fu (%.1f in) max=%.1fu (%.1f in) | sample age avg %.0f ms (33 ms of a 250 u/s run = 8 u) | anchorErrors=%d",
            imp.n, imp.sum / imp.n, imp.sum / imp.n * 0.75, imp.max, imp.max * 0.75, imp.sumAge / imp.n * 10, stats.anchorErrors or 0)
            .. string.format(" | on a ragdoll %d", stats.anchorRag or 0) -- A1r
        if IsValid(p) then p:PrintMessage(HUD_PRINTCONSOLE, rw) else print(rw) end
    end
end)

-- Short gameplay effects observed on the server. No voice/chat, music or ambient-loop capture.
-- Bounded ring, per-source budget and duplicate suppression keep busy fights from growing memory.
do
local ring, head, count, budget = {}, 0, 0, {}
local function number(n, default, low, high)
    n = tonumber(n)
    if not n or n ~= n then n = default end
    return math.Clamp(n, low, high)
end
function K.ReplaySoundPath(path)
    if not isstring(path) or #path > 180 or string.find(path, "..", 1, true) or string.find(path, "[%c:]" ) then return end
    path = string.lower(string.gsub(path, "^[*#@<>^)]*", ""))
    if not (string.match(path, "%.wav$") or string.match(path, "%.mp3$") or string.match(path, "%.ogg$")) then return end
    if not (string.find(path, "weapons/", 1, true) or string.match(path, "^player/")
        or string.match(path, "^physics/") or string.match(path, "^vo/npc/")) then return end
    return path
end
local function sourcePlayer(ent)
    if not IsValid(ent) then return end
    if ent:IsPlayer() then return ent end
    local p = hg and hg.RagdollOwner and hg.RagdollOwner(ent)
    if not IsValid(p) and ent.GetOwner then p = ent:GetOwner() end
    if IsValid(p) and p:IsPlayer() then return p end
end
function K.NoteReplaySound(ent, path, pos, level, pitch, volume, kind, original)
    if not enabled:GetBool() then return end
    path = K.ReplaySoundPath(path)
    if not path then return end
    local p = sourcePlayer(ent)
    local slot = p and slotOf(p) or 0
    if not slot then return end
    if not isvector(pos) and IsValid(ent) then pos = ent:GetPos() end
    if not finitePoint(pos) then return end
    local now, uid = CurTime(), p and p:UserID() or 0
    local source = slot > 0 and slot or 0 -- all unowned world effects share a budget
    local b = budget[source]
    if not b or b.uid ~= uid or now - b.at >= 1 then b = {uid=uid, at=now, n=0} budget[source] = b end
    if b.n >= 24 then return end
    if b.path == path and now - (b.last or 0) < 0.025 then return end
    volume = number(volume, 1, 0, 1)
    if volume == 0 then return end
    kind = kind or (string.find(path, "footstep", 1, true) and 1
        or (string.find(path, "flesh", 1, true) or string.find(path, "blunt_light", 1, true) or string.find(path, "physics/body/", 1, true)) and 3 or 4)
    if kind == 4 and p then
        local w = p:GetActiveWeapon()
        if IsValid(w) then
            local snd = w.Primary and w.Primary.Sound
            if istable(snd) then snd = snd[1] end
            if snd == path or snd == original or w.SupressedSound == path then kind = 2 end
        end
    end
    head = head % 2048 + 1; count = math.min(count + 1, 2048)
    local row = ring[head] or {}; ring[head] = row
    row[1], row[2], row[3] = now, slot, uid
    row[4], row[5], row[6], row[7] = pos.x, pos.y, pos.z, path
    row[8], row[9], row[10], row[11] = number(level, 75, 0, 140), number(pitch, 100, 25, 255), volume, kind
    b.n, b.path, b.last = b.n + 1, path, now
end
hook.Add("EntityEmitSound", "ZCKillcam.Sound", function(data)
    if (data.Flags or 0) ~= 0 then return end -- stop/change commands are not new one-shot effects
    local ok = pcall(K.NoteReplaySound, data.Entity, data.SoundName, data.Pos, data.SoundLevel, data.Pitch, data.Volume, nil, data.OriginalSoundName)
    if not ok then stats.soundErrors = (stats.soundErrors or 0) + 1 end
    -- No return: never cancel, replace or alter the live sound.
end)
hook.Add("PlayerFootstep", "ZCKillcam.Step", function(p, pos, _, path, volume)
    local ok = pcall(K.NoteReplaySound, p, path, pos, 75, 100, volume, 1)
    if not ok then stats.soundErrors = (stats.soundErrors or 0) + 1 end
end)
function K.EachSound(t0, t1, fn)
    for k = count - 1, 0, -1 do
        local row = ring[(head - k - 1) % 2048 + 1]
        if row[1] >= t0 and row[1] <= t1 and CurTime() - row[1] <= 20 then fn(row) end
    end
end
hook.Add("ZB_PreRoundStart", "ZCKillcam.Sound", function() ring, head, count, budget = {}, 0, 0, {} end)
end
