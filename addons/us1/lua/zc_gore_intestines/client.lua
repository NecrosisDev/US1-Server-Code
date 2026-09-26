if not CLIENT then return end
local VERSION = '20260920.intestines1'
local VISUAL_REVISION = '20260922.gore1'
if ZCityGoreIntestinesVisuals then
    assert(ZCityGoreIntestinesVisuals.Version == VERSION, 'Intestines: unload the previous visuals first')
    if ZCityGoreIntestinesVisuals.VisualRevision == VISUAL_REVISION then return end
    -- Superseding an earlier revision: its meshes belong to its own geometry.
    local old = ZCityGoreIntestinesVisuals
    if old.Mesh then old.Mesh:Destroy(); old.Mesh = nil end
    for _, m in ipairs(old.Meshes or {}) do if m then m:Destroy() end end
    old.Meshes = nil
end
local V = ZCityGoreIntestinesVisuals or {Version = VERSION}
V.VisualRevision = VISUAL_REVISION
V.nextDrop = 0
V.nextDecal = 0
V.decals = 0
V.Meshes = nil
V.stats = {draws = 0, drops = 0, decals = 0, refusedDecals = 0}
ZCityGoreIntestinesVisuals = V

-- CreateMaterial will not rebuild a material that already exists under the same
-- name, so a changed surface needs a new name, not edited keyvalues.
local flesh = CreateMaterial('zc_intestines_flesh_v2', 'VertexLitGeneric', {
    ['$basetexture'] = 'models/flesh', ['$bumpmap'] = 'models/flesh_nrm',
    ['$model'] = '1', ['$vertexcolor'] = '1',
    -- Wet gut rather than matte tube: tighter, brighter highlight plus a rim
    -- term so the silhouette stays readable against a dark floor. No $envmap -
    -- maps without built cubemaps render that as chrome.
    ['$phong'] = '1', ['$phongboost'] = '1.6', ['$phongexponent'] = '28',
    ['$phongfresnelranges'] = '[0.3 1 2]',
    ['$rimlight'] = '1', ['$rimlightexponent'] = '3.4', ['$rimlightboost'] = '1.1'
})
local drip = Material('effects/blood_drop') -- Reuse the installed blood sprite, without changing its shared material.
local maxDistance = 1536 * 1536
local seepDistance = 768 * 768
local decalDistance = 640 * 640

-- Decal names registered by the gamemode's shitdecals.lua on both realms.
local decalNames = {'Normal.Blood21', 'Normal.Blood22', 'Normal.Blood23', 'Normal.Blood24', 'Normal.Blood25'}
-- Client-side budget. Lua decals are not documented to respect r_decals, so the
-- trail owns its own ceiling and spacing instead of trusting the engine's.
local DECAL_MAX = 220
local DECAL_INTERVAL = 0.35

local SIDES = 10
-- Three profiles, picked per segment, so a chain does not read as one extruded
-- tube repeated end to end. Each spans the same segment the collision box does.
local profiles = {
    {{-5.6, 0.10}, {-5.0, 0.82}, {-4.2, 1.18}, {-2.8, 1.02}, {-1.0, 1.26},
     {0.8, 1.04}, {2.6, 1.22}, {4.2, 1.10}, {5.0, 0.80}, {5.6, 0.10}},
    {{-5.6, 0.10}, {-4.9, 0.90}, {-3.9, 1.05}, {-2.4, 1.30}, {-0.6, 1.08},
     {1.2, 1.28}, {2.9, 1.06}, {4.3, 1.20}, {5.1, 0.76}, {5.6, 0.10}},
    {{-5.6, 0.10}, {-5.1, 0.78}, {-4.0, 1.24}, {-2.6, 1.12}, {-0.8, 1.02},
     {1.0, 1.24}, {2.8, 1.14}, {4.1, 1.02}, {5.0, 0.84}, {5.6, 0.10}}
}

local function shade(radius, z, n)
    -- Underside and the pinched ends sit in shadow; the fat of each coil catches
    -- light. Baked per vertex so it costs nothing at draw time.
    local lit = 0.62 + 0.38 * math.Clamp(z * 0.5 + 0.5, 0, 1)
    local fat = 0.80 + 0.20 * math.Clamp(radius / 1.3, 0, 1)
    local band = 0.94 + 0.06 * math.sin(n * 1.7)
    local k = lit * fat * band
    return Color(math.Clamp(214 * k, 0, 255), math.Clamp(137 * k, 0, 255),
        math.Clamp(144 * k, 0, 255), 255)
end

function V.BuildVertices(rings)
    local vertices = {}
    local function point(ring, side, n)
        local phi = side / SIDES * math.pi * 2
        local y, z = math.cos(phi), math.sin(phi)
        return {pos = Vector(ring[1], y * ring[2], z * ring[2]), normal = Vector(0, y, z),
            u = (ring[1] + 6) / 6, v = side / SIDES, color = shade(ring[2], z, n)}
    end
    for n = 1, #rings - 1 do
        for side = 0, SIDES - 1 do
            local a, b = point(rings[n], side, n), point(rings[n + 1], side, n + 1)
            local c, d = point(rings[n + 1], side + 1, n + 1), point(rings[n], side + 1, n)
            -- Outward winding. Vertices are built once and shared by every link.
            vertices[#vertices + 1] = a; vertices[#vertices + 1] = c; vertices[#vertices + 1] = b
            vertices[#vertices + 1] = a; vertices[#vertices + 1] = d; vertices[#vertices + 1] = c
        end
    end
    return vertices
end

function V.MeshFor(e)
    if not V.Meshes then
        local built = {}
        for i = 1, #profiles do
            built[i] = Mesh(flesh)
            built[i]:BuildFromTriangles(V.BuildVertices(profiles[i]))
        end
        V.Meshes = built
    end
    return V.Meshes[e:EntIndex() % #V.Meshes + 1]
end

local function markFloor(body, hitPos, normal)
    local now = CurTime()
    if now < V.nextDecal or V.decals >= DECAL_MAX then
        V.stats.refusedDecals = V.stats.refusedDecals + 1
        return
    end
    if hitPos:DistToSqr(EyePos()) > decalDistance then return end
    V.nextDecal = now + DECAL_INTERVAL
    V.decals = V.decals + 1
    V.stats.decals = V.stats.decals + 1
    util.Decal(decalNames[math.random(#decalNames)], hitPos + normal * 2, hitPos - normal * 2,
        IsValid(body) and body or nil)
end

function V.Seep(e, body, pos, tip)
    local now = CurTime()
    local age = now - e:GetBornAt()
    if age < 0 or now < V.nextDrop or now < (e.ZCNextSeep or 0) then return end
    if drip:IsError() or pos:DistToSqr(EyePos()) > seepDistance then return end
    -- No catch-up burst: one emission at a time for the whole client.
    -- Older bodies slow down instead of silently losing the effect.
    V.nextDrop = now + 0.09
    local slow = age > 25
    e.ZCNextSeep = now + (tip and (slow and 1.6 or 0.45) or (slow and 3.2 or 1.1))

    local emitter = ParticleEmitter(pos, false)
    if not IsValid(emitter) then return end

    local inherit = e:GetVelocity() * 0.1
    for _ = 1, tip and 2 or 1 do
        local p = emitter:Add(drip, pos + VectorRand(-0.5, 0.5))
        if p then
            p:SetVelocity(inherit + Vector(math.Rand(-4, 4), math.Rand(-4, 4), -14))
            p:SetDieTime(2.2)
            p:SetStartAlpha(235)
            p:SetEndAlpha(0)
            p:SetStartSize(tip and math.Rand(1.7, 2.2) or math.Rand(1.1, 1.6))
            p:SetEndSize(0.3)
            p:SetColor(math.random(112, 152), math.random(11, 22), math.random(11, 20))
            p:SetGravity(Vector(0, 0, -420))
            p:SetAirResistance(10)
            p:SetBounce(0)
            p:SetCollide(true)
            p:SetCollideCallback(function(_, hitPos, hitNormal)
                markFloor(body, hitPos, hitNormal)
            end)
            V.stats.drops = V.stats.drops + 1
        end
    end
    emitter:Finish()
end

function V.DrawSegment(e)
    -- A segment torn loose keeps drawing after its body is gone; bailing on an
    -- invalid body would leave invisible debris colliding for its whole lifetime.
    local body = e:GetIntestineBody()
    if IsValid(body) and (body:IsDormant() or body:GetNoDraw()) then return end
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    if ply.GetNetVar and ply:GetNetVar('disappearance', nil) then return end
    if IsValid(body) and body.GetNetVar and body:GetNetVar('disappearance', nil) then return end
    local pos = e:GetPos()
    if pos:DistToSqr(EyePos()) > maxDistance then return end
    local transform = e.ZCIntestineMatrix or Matrix(); e.ZCIntestineMatrix = transform
    transform:SetTranslation(pos); transform:SetAngles(e:GetAngles())
    render.SetMaterial(flesh)
    cam.PushModelMatrix(transform)
    V.MeshFor(e):Draw()
    cam.PopModelMatrix()
    V.stats.draws = V.stats.draws + 1
    -- Cheap throttle first: this runs per segment per frame, and building the
    -- emission point allocates. V.Seep re-checks before it emits.
    local now = CurTime()
    if now < V.nextDrop or now < (e.ZCNextSeep or 0) then return end
    local tip = e:GetIntestineTip()
    -- The mesh reaches x=5.6. The tip sheds from past the open end; the rest of
    -- the run sheds off its underside so the whole length reads as wet.
    local from = tip and (e:LocalToWorld(Vector(6.2, 0, 0)) + Vector(0, 0, 1.5))
        or e:LocalToWorld(Vector(math.Rand(-4, 4), 0, -1.35))
    V.Seep(e, body, from, tip)
end

function V.Cleanup()
    if V.Mesh then V.Mesh:Destroy(); V.Mesh = nil end
    for _, m in ipairs(V.Meshes or {}) do if m then m:Destroy() end end
    V.Meshes = nil
    V.nextDrop = 0
    V.nextDecal = 0
    V.decals = 0
end
hook.Add('PostCleanupMap', 'ZCIntestines_ClientCleanup', V.Cleanup)
hook.Add('ShutDown', 'ZCIntestines_ClientCleanup', V.Cleanup)
