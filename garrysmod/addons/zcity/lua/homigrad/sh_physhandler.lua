local function SetAbsVelocity(pEntity, vAbsVelocity)
	if (pEntity:GetInternalVariable("m_vecAbsVelocity") ~= vAbsVelocity) then
		// The abs velocity won't be dirty since we're setting it here
		pEntity:RemoveEFlags(EFL_DIRTY_ABSVELOCITY)

		// All children are invalid, but we are not
		local tChildren = pEntity:GetChildren()

		for i = 1, #tChildren do
			tChildren[i]:AddEFlags(EFL_DIRTY_ABSVELOCITY)
		end

		pEntity:SetSaveValue("m_vecAbsVelocity", vAbsVelocity)

		// NOTE: Do *not* do a network state change in this case.
		// m_vVelocity is only networked for the player, which is not manual mode
		local pMoveParent = pEntity:GetMoveParent()

		if (pMoveParent:IsValid()) then
			// First subtract out the parent's abs velocity to get a relative
			// velocity measured in world space
			// Transform relative velocity into parent space
			-- FIXME
			--pEntity:SetSaveValue("m_vecVelocity", (vAbsVelocity - pMoveParent:_GetAbsVelocity()):IRotate(pMoveParent:EntityToWorldTransform()))
			pEntity:SetSaveValue("velocity", vAbsVelocity)
		else
			pEntity:SetSaveValue("velocity", vAbsVelocity)
		end
	end
end

------------------------
-- Might be useful
------------------------
local inf,ninf,ind = 1/0,-1/0,(1/0)/(1/0)

--(ind==ind) == false :(. This should do though. >= and <= because you never know :3

function math.BadNumber(v) 
	return not v or v==inf or v==ninf or not (v>=0 or v<=0) or tostring(v) == "nan"
end

local max_reasonable_pos 		= 25000
local min_reasonable_pos 		= -25000

function IsReasonable( pos )
	local posY, posZ = pos.y, pos.z

	if (pos.x > max_reasonable_pos or posY < min_reasonable_pos or
		posY > max_reasonable_pos or posZ < min_reasonable_pos or
		posZ > max_reasonable_pos) then
		return false
	end
	return true
end

-- Server-only containment: freeze the reported body, then remove the captured
-- connected group outside the physics callback. Never traverse the group twice.
local pendingCrazyCleanup = setmetatable({}, {__mode = "k"})
local function HandleCrazyPhysicsServer(ent, physobj)
    if not IsValid(ent) or ent:IsWorld() or ent:IsPlayer() then return end
    if IsValid(physobj) then
        physobj:EnableMotion(false)
        physobj:Sleep()
    end
    if pendingCrazyCleanup[ent] or ent.__removed__ then return end
    local connected = constraint.GetAllConstrainedEntities(ent) or {}
    connected[ent] = ent
    local batch = {}
    for _, other in pairs(connected) do
        if IsValid(other) and not other:IsWorld() and not other:IsPlayer()
            and not other.__removed__ and not pendingCrazyCleanup[other] then
            local job = {entity = other, creation = other:GetCreationID()}
            pendingCrazyCleanup[other] = job
            batch[#batch + 1] = job
        end
    end
    if #batch == 0 then return end
    timer.Simple(0, function()
        local firstError
        for _, job in ipairs(batch) do
            local other = job.entity
            if pendingCrazyCleanup[other] == job then
                pendingCrazyCleanup[other] = nil
                if IsValid(other) and other:GetCreationID() == job.creation
                    and not other.__removed__ then
                    other.__removed__ = true
                    local ok, err = pcall(other.Remove, other)
                    if not ok then
                        if IsValid(other) then other.__removed__ = nil end
                        firstError = firstError or tostring(err)
                    end
                end
            end
        end
        if firstError then
            ErrorNoHalt("[ZCity physics] Deferred containment failed: " .. firstError .. "\n")
        end
    end)
end

hook.Add("OnCrazyPhysics","crazy_physics",function(ent, physobj)--function(a,msg,c,d, r,g,b)
	if SERVER then HandleCrazyPhysicsServer(ent, physobj); return end
	local a = ent:GetPos()
	local angles = ent:GetAngles()
	local x, y, z = a.x, a.y, a.z
	local p, yaw, r = angles.x, angles.y, angles.z

	local badang = math.BadNumber(p) or p==0
				or math.BadNumber(yaw) or yaw==0
				or math.BadNumber(r) or r==0
		
	local badpos = math.BadNumber(x) or x==0
				or math.BadNumber(y) or y==0
				or math.BadNumber(z) or z==0

	local pos = ent:GetPos()

	ent:CollisionRulesChanged()

	if physobj:IsValid() then
		physobj:EnableMotion(false)
		physobj:Sleep()
		physobj:SetPos(vector_origin)
		physobj:SetAngles(angle_zero)
		physobj:SetVelocity(vector_origin)
		physobj:SetAngleVelocity(vector_origin)
	end

	ent:SetLocalAngularVelocity(angle_zero)
	ent:SetVelocity(vector_origin)
	ent:SetLocalVelocity(vector_origin)

	SetAbsVelocity(ent, vector_origin)
	if SERVER then
		local t = constraint.GetAllConstrainedEntities(ent)
		for k,v in next, t or {} do
			local t = constraint.GetAllConstrainedEntities(v)
			for k,v in next, t or {} do
				if ent ~= v and IsValid(v) and not v.__removed__ then
					v.__removed__ = true
					v:Remove()
				end
			end

			if IsValid(v) and not v.__removed__ then
				v.__removed__ = true
				v:Remove()
			end
		end
	end
end)