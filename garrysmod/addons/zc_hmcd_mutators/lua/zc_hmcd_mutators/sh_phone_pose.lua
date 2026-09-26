-- Pure two-segment arm solve; callers provide checked positions and lengths.
local P = {}
local function finite(n) return type(n) == "number" and n == n and math.abs(n) < math.huge end
function P.VectorOK(v) return isvector(v) and finite(v.x) and finite(v.y) and finite(v.z) end
function P.Blend(phase, elapsed)
    local t = math.max(0, math.min(1, elapsed / 0.6))
    t = t * t * (3 - 2 * t)
    if phase == 1 then return t end
    if phase == 2 then return 1 end
    if phase == 3 then return 1 - t end
    return 0
end
function P.Solve(shoulder, target, pole, upper, lower)
    if not P.VectorOK(shoulder) or not P.VectorOK(target) or not P.VectorOK(pole)
        or not finite(upper) or not finite(lower) or upper < 0.5 or lower < 0.5 or upper > 64 or lower > 64 then return end
    local delta = target - shoulder
    local distance = delta:Length()
    if distance < 0.001 then return end
    local direction = delta / distance
    distance = math.max(math.abs(upper - lower) + 0.01, math.min(upper + lower - 0.01, distance))
    local sideways = pole - direction * pole:Dot(direction)
    if sideways:LengthSqr() < 0.0001 then
        local fallback = math.abs(direction.z) < 0.9 and Vector(0, 0, -1) or Vector(0, 1, 0)
        sideways = fallback - direction * fallback:Dot(direction)
    end
    sideways = sideways:GetNormalized()
    local along = (upper * upper - lower * lower + distance * distance) / (2 * distance)
    local height = math.sqrt(math.max(0, upper * upper - along * along))
    local elbow = shoulder + direction * along + sideways * height
    local hand = shoulder + direction * distance
    if not P.VectorOK(elbow) or not P.VectorOK(hand) then return end
    return elbow, hand
end
-- ValveBiped right-hand +X follows the fingers; -Y faces out of the palm.
-- Raise the fingers toward the ear while turning the palm toward the head.
function P.HandAngle(blend, yaw)
    return Angle(-10 - 95 * blend, yaw, -90 - 90 * blend)
end
function P.PhoneTransform(wrist, wristAngle)
    -- This mesh is displaced from its origin: +Y is the screen, +Z the earpiece.
    -- Map screen to palm -Y and earpiece to fingers +X, then anchor its center
    -- in the palm. Rotating about the mesh center avoids swinging the phone away.
    local center, angle = LocalToWorld(Vector(3, -1.1, 0), Angle(-90, 0, 180), wrist, wristAngle)
    local pivot = LocalToWorld(Vector(0, 3.86, -18.73), Angle(0, 0, 0), Vector(0, 0, 0), angle)
    return center - pivot, angle
end
return P
