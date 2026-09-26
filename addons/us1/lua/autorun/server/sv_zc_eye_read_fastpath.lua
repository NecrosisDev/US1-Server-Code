-- Remove repeated reads and unused angle construction within one hg.eye call.
-- Server only. Positions, traces, return values, and call frequency stay unchanged.
if not SERVER then return end
local version='20260920.1'
local stateName='ZCEyeReadOptimization20260920'
local sourcePath='homigrad/sh_utility.lua'
local sourceHash='dd753e5dac28013a9a9e8d36246ef48f3f0991f3dcce8e2cee98fe3eef24a2f7'
local originalHash='3ebdf40c7faace45c2e6cfd68be98ae21f6efeaf5565767e8c434315929079fc'
local function candidateFactory(original, nativeBoneMatrix)
	return function(ply, dist, ent, aimvec, startpos)
		if not ply:IsPlayer() then return false end
		local fakeCam = false
		local ent = (IsValid(ent) and ent) or (IsValid(ply.FakeRagdoll) and ply.FakeRagdoll) or ply
        if ent.GetBoneMatrix ~= nativeBoneMatrix then
            return original(ply, dist, ent, aimvec, startpos)
        end
		local bon = ent:LookupBone("ValveBiped.Bip01_Neck1")
		if not bon then return end
		if not IsValid(ply) then return end
		if not ply.GetAimVector then return end
		local aim_vector = isvector(aimvec) and aimvec or isangle(aimvec) and aimvec:Forward() or ply:GetAimVector()
        local headm = ent:GetBoneMatrix(bon)
        if not bon or not headm then
			local tr = {
				start = ply:EyePos(),
				endpos = ply:EyePos() + aim_vector * (dist or 60),
				filter = ply
			}
			return ply:EyePos(), aim_vector * (dist or 60), ply
		end
		local eyeAng = aim_vector:Angle()
		eyeAng.r = isangle(aimvec) and aimvec.r or ply:EyeAngles().r
		local headAng = not startpos and headm:GetAngles()
		local pos = startpos or headm:GetTranslation() + (fakeCam and (headAng:Forward() * 2 + headAng:Up() * -2 + headAng:Right() * 3) or (eyeAng:Up() * 2 + headAng:Right() * 4 + headAng:Up() * 0  + headAng:Forward() * (4 + (ply.PlayerClassName == "Combine" and 4 or 0))))
		local trace = hg.hullCheck(ply:EyePos() - vector_up * 10, pos, ply)
		return trace.HitPos, aim_vector * (dist or 60), {ply, ent, ply.OldRagdoll}, trace, headm
	end
end

local reported={}
local function decline(reason)
    if not reported[reason] then
        reported[reason]=true
        print('[ZC Eye Read] original retained: '..reason)
    end
    return false
end
local function install()
    local previous=_G[stateName]
    if previous and previous.disabled then return false end
    if previous and previous.IsActive() then return true end
    local original=hg and hg.eye
    if not isfunction(original) then return false end
    local source=file.Read(sourcePath,'LUA')
    if not source or util.SHA256(source)~=sourceHash then return decline('source changed') end
    local d=debug.getinfo(original,'S')
    if d.source~='@addons/zcity/lua/'..sourcePath or d.linedefined~=767
        or util.SHA256(string.dump(original,true))~=originalHash then
        return decline('function owner or version changed')
    end
    local matrixReader=FindMetaTable('Entity').GetBoneMatrix
    if not isfunction(matrixReader) or debug.getinfo(matrixReader,'S').what~='C' then
        return decline('bone reader changed')
    end
    local candidate=candidateFactory(original,matrixReader)
    local state={version=version,original=original,candidate=candidate,sourceHash=sourceHash,originalHash=originalHash}
    function state.IsActive() return hg and hg.eye==candidate or false end
    function state.Rollback()
        if not state.IsActive() then return false,'function owner changed' end
        state.disabled=true
        hg.eye=original
        return true
    end
    hg.eye=candidate
    _G[stateName]=state
    print('[ZC Eye Read] per-call read reduction active ('..version..')')
    return true
end
-- Observer hooks never return the install result or stop other initialization hooks.
local function onLoad() install() end
hook.Add('PostGamemodeLoaded','ZCEyeReadInstall20260920',onLoad)
hook.Add('InitPostEntity','ZCEyeReadInstall20260920',onLoad)
hook.Add('HomigradRun','ZCEyeReadInstall20260920',onLoad)
install()
timer.Simple(0,onLoad)
