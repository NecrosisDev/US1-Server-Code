function util.ScreenShake(vPos, nAmplitude, nFrequency, nDuration, nRadius, bAirshake, crfFilter)
	if SERVER then -- SERVER SIDE
		vPos = vPos or Vector(0,0,0)
		nRadius = nRadius or (nAmplitude * 100)
		local tEnts = crfFilter and {} or ents.FindInSphere(vPos, nRadius)
		--PrintTable(tEnts)
		local crf = crfFilter or RecipientFilter()
		--print(#tEnts)
		for i = 1, #tEnts do
			local eEnt = tEnts[i]
			if !IsValid(eEnt) then continue end
			if !eEnt:IsPlayer() then continue end
			crf:AddPlayer(eEnt)
		end
		crf = crf or crfFilter
		--print(crf)
		net.Start("util.ScreenShake")
			net.WriteVector(vPos)
			net.WriteFloat(nAmplitude)
			net.WriteFloat(nFrequency)
			net.WriteFloat(nDuration or 1)
			net.WriteFloat(nRadius)
			net.WriteBool(bAirshake)
		net.Send(crf)
	elseif CLIENT then -- CLIENT SIDE
		nRadius = nRadius or (nAmplitude * 100)
		ScreenShakers[#ScreenShakers + 1] = {
			vPos = vPos,
			nAmplitude = nAmplitude,
			nFrequency = nFrequency,
			nDuration = nDuration or 1,
			nRadius = nRadius,
			bAirshake = bAirshake,
			tCreated = CurTime()
		}
		hg.OldScreenShake(vPos, nAmplitude, nFrequency, nDuration, nRadius, bAirshake, crfFilter)
	end
end