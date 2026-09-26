if not SERVER then return end
local rows={}
local tested=0
for _,ent in ipairs(ents.FindByClass("prop_physics"))do
    if tested>=20 then break end
    if not IsValid(ent)then continue end
    local mins,maxs=ent:OBBMins(),ent:OBBMaxs()
    local radius=math.max(math.abs(mins.x),math.abs(maxs.x),10)
    if radius>80 then continue end
    local dir=ent:GetForward()
    local center=ent:WorldSpaceCenter()
    local pre=util.TraceLine({
        start=center-dir*(radius+20),
        endpos=center+dir*(radius+20),
        mask=MASK_SOLID
    })
    if not pre.Hit or pre.Entity~=ent then continue end
    local hitPos=pre.HitPos
    local oldDist
    for dist=5,100,5 do
        local p=hitPos+dir*dist
        local tr=util.TraceLine({start=p,endpos=hitPos,mask=MASK_SOLID})
        if not tr.StartSolid then oldDist=dist break end
    end
    local start=hitPos+dir
    local finish=hitPos+dir*100
    local one=util.TraceLine({start=start,endpos=finish,mask=MASK_SOLID})
    local left
    if one.StartSolid and one.FractionLeftSolid and one.FractionLeftSolid>0 then
        left=1+(99*one.FractionLeftSolid)
    elseif not one.StartSolid then
        left=1
    end
    tested=tested+1
    rows[#rows+1]={
        ent=ent:EntIndex(),
        model=ent:GetModel(),
        old=oldDist,
        startsolid=one.StartSolid,
        allsolid=one.AllSolid,
        fractionLeft=one.FractionLeftSolid,
        exit=left
    }
end
file.CreateDir("zc_bullet_phase2")
file.Write("zc_bullet_phase2/fraction_test.json",util.TableToJSON(rows,true))
print("PEN_FRACTION_TEST",tested)
