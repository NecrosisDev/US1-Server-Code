if not SERVER then return end
local VERSION = '20260922.gore2'
-- Autorefresh re-runs this file on every write, so an older loaded revision has
-- to be retired here rather than asserted at. Cleanup removes that revision's
-- groups; the hooks, convar and change-callback below all re-register by name.
if ZCityGoreIntestines then
    if ZCityGoreIntestines.Version == VERSION then return end
    if isfunction(ZCityGoreIntestines.Cleanup) then pcall(ZCityGoreIntestines.Cleanup) end
    ZCityGoreIntestines = nil
end
local I = {Version = VERSION, groups = {}, byCap = {}, pending = {}, count = 0, serial = 0,
    Links = 6, MaxGroups = 6, Length = 10, MinLinks = 3, loose = setmetatable({}, {__mode = 'k'}),
    stats = {created = 0, removed = 0, refused = 0, errors = 0}}
ZCityGoreIntestines = I
local enabled = CreateConVar('zc_intestines_enabled', '0', FCVAR_ARCHIVE,
    'Enable physical intestines on newly created ZCity torso caps. Requires approved rollout.', 0, 1)
-- PROVISIONAL(2026-09-22, break thresholds are a first guess - no reference for
-- how hard a crawler must be dragged or shot before gut tears, ratify-by: 2026-10-13)
local breakForce = CreateConVar('zc_intestines_breakforce', '900', FCVAR_ARCHIVE,
    'Force a ballsocket between intestine segments takes before it tears loose. 0 = unbreakable.', 0, 20000)
local breakTorque = CreateConVar('zc_intestines_breaktorque', '600', FCVAR_ARCHIVE,
    'Torque a ballsocket between intestine segments takes before it tears loose. 0 = unbreakable.', 0, 20000)
local looseLifetime = CreateConVar('zc_intestines_loose_lifetime', '45', FCVAR_ARCHIVE,
    'Seconds a torn-off length of intestine survives as an independent object.', 5, 300)

local upper = 'models/torsopartial/torsovar.mdl'
local lower = 'models/torsopartial/abdomenvar.mdl'

local function finite(v)
    return isvector(v) and v.x == v.x and v.y == v.y and v.z == v.z
        and math.abs(v.x) < 1000000 and math.abs(v.y) < 1000000 and math.abs(v.z) < 1000000
end
I.FiniteVector = finite
function I.IsSegment(e)
    return IsValid(e) and e:GetClass() == 'zc_intestine_segment' and e.ZCIntestineSegment == true
end

function I.RemoveGroup(g)
    if not g or g.removing then return end
    g.removing = true
    if I.groups[g] then I.groups[g] = nil; I.count = I.count - 1 end
    if I.byCap[g.cap] == g then I.byCap[g.cap] = nil end
    for _,e in ipairs(g.joints or {}) do if IsValid(e) then e:Remove() end end
    for _,e in ipairs(g.links or {}) do if IsValid(e) then e:Remove() end end
    if IsValid(g.cap) then g.cap:RemoveCallOnRemove(g.callback) end
    if IsValid(g.body) then g.body:RemoveCallOnRemove(g.callback) end
    I.stats.removed = I.stats.removed + 1
end

-- A torn joint must free what hung below it, not delete the run. Everything
-- from `from` down leaves the group, stops counting against it, and lives on its
-- own clock; the segment left at the end becomes the new seeping tip.
function I.Detach(g, from)
    if not g or g.removing then return end
    local links, cut = g.links, nil
    for i = 1, #links do if links[i] == from then cut = i break end end
    if not cut then return end
    local life = looseLifetime:GetFloat()
    for i = #links, cut, -1 do
        local e = links[i]
        links[i] = nil
        if IsValid(e) then
            -- Clear the back-reference first: ENT:OnRemove tears down the whole
            -- group through it, and a loose piece must never do that.
            e.ZCIntestineGroup = nil
            I.loose[e] = true
            e:SetIntestineTip(i == cut)
            SafeRemoveEntityDelayed(e, life)
        end
    end
    local last = links[#links]
    if IsValid(last) then last:SetIntestineTip(true) end
    I.stats.detached = (I.stats.detached or 0) + 1
end

function I.ResolveCap(cap)
    if not IsValid(cap) or cap:GetClass() ~= 'prop_dynamic' then return nil, 'cap' end
    local model = string.lower(cap:GetModel() or '')
    if model ~= upper and model ~= lower then return nil, 'model' end
    -- Metadata belongs to the reviewed Gore V2 MakeCap; generic look-alike props do not qualify.
    local body = cap.__zcGoreParent
    if not IsValid(body) or not body:IsRagdoll() then return nil, 'body' end
    local low = model == lower
    if not body:GetNWBool(low and 'ZCityTorsoLowerPart' or 'ZCityTorsoSevered', false) then return nil, 'state' end
    -- Lower Spine2 is intentionally frozen/hidden by the gore mod. Attach to its live pelvis instead.
    local bone = body:LookupBone(low and 'ValveBiped.Bip01_Pelvis' or 'ValveBiped.Bip01_Spine2')
    if bone == nil or bone < 0 then return nil, 'bone' end
    local id = body:TranslateBoneToPhysBone(bone)
    if id == nil or id < 0 then return nil, 'physics_bone' end
    local phys = body:GetPhysicsObjectNum(id)
    if not IsValid(phys) or not phys:IsMotionEnabled() then return nil, 'physics' end
    local pos = cap:GetPos()
    if not finite(pos) or not finite(phys:GetPos()) then return nil, 'position' end
    local velocity = phys:GetVelocity()
    if not finite(velocity) then return nil, 'velocity' end
    return {body = body, bone = id, phys = phys, pos = pos, velocity = velocity, lower = low}
end

function I.Attach(cap, manual)
    -- Manual attachment is a server-only API used by an owner-authorized trial.
    -- Automatic entity hooks never pass this flag.
    if not enabled:GetBool() and manual ~= true then return false, 'disabled' end
    if I.byCap[cap] then return false, 'duplicate' end
    if I.count >= I.MaxGroups then I.stats.refused = I.stats.refused + 1; return false, 'budget' end
    local anchor, reason = I.ResolveCap(cap)
    if not anchor then return false, reason end
    I.serial = I.serial + 1
    local g = {cap = cap, body = anchor.body, links = {}, joints = {}, callback = 'ZCIntestines_' .. I.serial}
    I.groups[g] = true; I.byCap[cap] = g; I.count = I.count + 1 -- Reserve before any entity/constraint callbacks.
    local ok, err = xpcall(function()
        local axis = Vector(0, 0, -1)
        local angles = axis:Angle()
        local previous, previousBone = anchor.body, anchor.bone
        -- Segments must spawn exactly Length apart: constraint.Ballsocket freezes
        -- the geometry it is created with, so anything closer welds each segment's
        -- top end to the previous one's middle. A run that will not fit is
        -- shortened, never compressed.
        local reach = I.Links * I.Length
        local room = util.TraceLine({start = anchor.pos, endpos = anchor.pos + axis * reach,
            filter = {anchor.body, cap}, mask = MASK_SOLID_BRUSHONLY})
        local links = math.Clamp(math.floor((room.Fraction or 1) * reach / I.Length), I.MinLinks, I.Links)
        for n = 1, links do
            local e = ents.Create('zc_intestine_segment')
            assert(IsValid(e), 'segment allocation failed')
            g.links[#g.links + 1] = e; e.ZCIntestineGroup = g
            e:SetPos(anchor.pos + axis * ((n - 0.5) * I.Length)); e:SetAngles(angles)
            e:Spawn(); assert(IsValid(e), 'segment initialization failed')
            e:SetIntestineBody(anchor.body); e:SetBornAt(CurTime()); e:SetIntestineTip(n == links)
            local phys = e:GetPhysicsObject(); assert(IsValid(phys), 'segment physics missing')
            phys:SetMass(0.85); phys:SetDamping(0.25, 1.1)
            -- Ballsocket localPos is relative to its SECOND physics object (the segment).
            local joint = constraint.Ballsocket(previous, e, previousBone, 0, Vector(-I.Length / 2, 0, 0),
                breakForce:GetFloat(), breakTorque:GetFloat(), 1)
            assert(IsValid(joint), 'joint allocation failed')
            g.joints[#g.joints + 1] = joint
            -- The joint going away now means it tore, not that the body did.
            joint:CallOnRemove(g.callback, function() I.Detach(g, e) end)
            phys:SetVelocity(anchor.velocity); phys:Wake()
            previous, previousBone = e, 0
        end
        assert(not g.removing and IsValid(cap) and IsValid(anchor.body), 'body removed during creation')
        cap:CallOnRemove(g.callback, function() I.RemoveGroup(g) end)
        anchor.body:CallOnRemove(g.callback, function() I.RemoveGroup(g) end)
    end, debug.traceback)
    if not ok then
        I.RemoveGroup(g); I.stats.errors = I.stats.errors + 1
        ErrorNoHalt('[ZCity intestines] ' .. tostring(err) .. '\n')
        return false, 'creation_failed'
    end
    I.stats.created = I.stats.created + 1
    return true, g
end

function I.Cleanup()
    local copy = {}; for g in pairs(I.groups) do copy[#copy + 1] = g end
    for _,g in ipairs(copy) do I.RemoveGroup(g) end
    I.pending = {}
end

hook.Add('OnEntityCreated', 'ZCIntestines_NewCap', function(e)
    if not enabled:GetBool() or not IsValid(e) or e:GetClass() ~= 'prop_dynamic' then return end
    if I.pending[e] then return end
    local pending = I.pending; pending[e] = true
    timer.Simple(0, function()
        if I.pending ~= pending or not pending[e] then return end
        pending[e] = nil
        if IsValid(e) then I.Attach(e) end
    end)
end)
hook.Add('ShouldCollide', 'ZCIntestines_OwnBody', function(a, b)
    local ga, gb = a.ZCIntestineGroup, b.ZCIntestineGroup
    if ga and not ga.removing and (ga == gb or b == ga.body) then return false end
    if gb and not gb.removing and a == gb.body then return false end
end)
hook.Add('PostCleanupMap', 'ZCIntestines_Cleanup', I.Cleanup)
hook.Add('ShutDown', 'ZCIntestines_Cleanup', I.Cleanup)
cvars.AddChangeCallback('zc_intestines_enabled', function(_, _, value)
    if tonumber(value) ~= 1 then I.Cleanup() end
end, 'ZCIntestines_Enable')

-- Narrow hammer integration: avoid its generic non-ragdoll branch's duplicate joints
-- and mismatched local-space anchor when pinning a segment to the world.
function I.BindNail(a, pa, b, pb, ba, bb)
    local world = game.GetWorld()
    if not I.IsSegment(a) and not I.IsSegment(b) then return false, false end
    if (not IsValid(a) and a ~= world) or (not IsValid(b) and b ~= world) or a == b
        or not finite(pa) or not finite(pb) then return false, false end
    if type(ba) ~= 'number' or type(bb) ~= 'number' or ba < 0 or bb < 0 or ba % 1 ~= 0 or bb % 1 ~= 0 then return false, false end
    if (a ~= world and not IsValid(a:GetPhysicsObjectNum(ba))) or (b ~= world and not IsValid(b:GetPhysicsObjectNum(bb))) then return false, false end
    -- The world has no unique physical attachment slot: never use world.Nails[0].
    -- Multiple independent wall pins must not share or replace one global record.
    local ra = a ~= world and a.Nails and a.Nails[ba] or nil
    local rb = b ~= world and b.Nails and b.Nails[bb] or nil
    if ra or rb then
        local shared = ra or rb
        if type(shared) ~= 'table' or (a ~= world and ra ~= shared) or (b ~= world and rb ~= shared)
            or not IsValid(shared[1]) or type(shared[2]) ~= 'number' or shared[2] < 1 then return false, false end
        local row = shared.ZCIntestineNail
        if type(row) ~= 'table' or not ((row.a == a and row.b == b and row.ba == ba and row.bb == bb)
            or (row.a == b and row.b == a and row.ba == bb and row.bb == ba)) then return false, false end
        shared[2] = shared[2] + 1 -- Both non-world ends share the hammer's existing un-nail decrement.
        shared[1]:SetKeyValue('forcelimit', tostring(row.force * shared[2]))
        return shared[2], shared[1]
    end
    local force = (a:IsRagdoll() or b:IsRagdoll()) and 9000 or 3000
    local joint = constraint.Weld(a, b, ba, bb, force, false, false)
    if not IsValid(joint) then return false, false end
    local row = {force = force, a = a, b = b, ba = ba, bb = bb}
    ra = {joint, 1, ZCIntestineNail = row}; rb = ra
    if a ~= world then a.Nails = a.Nails or {}; a.Nails[ba] = ra end
    if b ~= world then b.Nails = b.Nails or {}; b.Nails[bb] = rb end
    joint:CallOnRemove('ZCIntestines_NailA', function()
        if a ~= world and IsValid(a) and a.Nails and a.Nails[ba] == ra then a.Nails[ba] = nil end
    end)
    joint:CallOnRemove('ZCIntestines_NailB', function()
        if b ~= world and IsValid(b) and b.Nails and b.Nails[bb] == rb then b.Nails[bb] = nil end
    end)
    return 1, joint
end

-- Written on every (re)load so the applied revision and tunables can be read
-- off disk without a game console.
do
    local chr10 = string.char(10)
    local receipt = string.format(
        '%s version=%s links=%d maxgroups=%d length=%d minlinks=%d breakforce=%d enabled=%s' .. chr10,
        os.date('!%Y-%m-%dT%H:%M:%SZ'), VERSION, I.Links, I.MaxGroups, I.Length,
        I.MinLinks, breakForce:GetFloat(), tostring(enabled:GetBool()))
    file.CreateDir('zc_gore_receipts')
    file.Write('zc_gore_receipts/intestines.txt', receipt)
end
