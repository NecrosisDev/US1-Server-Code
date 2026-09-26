IsValid=function(o) return type(o)=="table" and o.valid==true end
isnumber=function(o) return type(o)=="number" end
istable=function(o) return type(o)=="table" end
isangle=function(o) return type(o)=="table" and o.angle==true end
AngleRand=function() return {} end
vector_origin={}
local savedRandom=math.random
math.random=function() return 10000 end
local tick, repetitions, removed, forces, stopped, wmReads
local ang={angle=true, Add=function() end, Up=function() return {} end, RotateAroundAxis=function() end}
local function stop() stopped=stopped+1 end
local function setup()
    removed,forces,stopped,wmReads=0,{},0,0
    timer={Create=function(name,delay,n,fn) tick=fn;repetitions=n;assert(delay==.01) end,
           Remove=function() removed=removed+1 end}
    hg={ShadowControl=function(r,id,ss,a,mul,damp,pos,speed,speeddamp)
        assert(ss==.001 and a==ang and mul==1000 and damp==50 and speed==0 and speeddamp==0)
        forces[#forces+1]=id
    end}
    local org={pulse=70,avgpain=0}
    local phys={valid=true,GetAngles=function() return ang end}
    local rag={valid=true,organism=org,StopSound=stop, bone=0,index=0,phys=phys}
    function rag:LookupBone(name) assert(name=="ValveBiped.Bip01_Spine2"); return self.bone end
    function rag:TranslateBoneToPhysBone(id) assert(type(id)=="number" and id>=0);return self.index end
    function rag:GetPhysicsObjectNum(id) assert(type(id)=="number" and id>=0);return self.phys end
    local ent={valid=true,organism=org,StopSound=stop,IsPlayer=function() return true end,EntIndex=function() return 17 end}
    local weapon={valid=true,GetWM=function() wmReads=wmReads+1;return nil end}
    TASER.start(weapon,ent,rag,nil,5)
    return rag,ent,weapon,org,phys
end
local r,e,w,o,phys=setup()
check(TASER.angles(r)==ang,"bone index zero is valid")
tick()
check(table.concat(forces,",")=="3,4,5,2,6,7,8,9,11,12","valid body retains ten original shadow-control targets and forces")
check(o.avgpain==.02,"valid body retains pain increment")
for i=2,repetitions do tick() end
check(repetitions==400 and removed==1 and stopped==2,"natural completion removes timer and stops both sounds")
for _,scenario in ipairs({"no_bone","unmapped_bone","missing_physics","invalid_physics","missing_angles"}) do
    r,e,w,o,phys=setup()
    if scenario=="no_bone" then r.bone=nil
    elseif scenario=="unmapped_bone" then r.index=-1
    elseif scenario=="missing_physics" then r.phys=nil
    elseif scenario=="invalid_physics" then phys.valid=false
    else phys.GetAngles=function() return nil end end
    tick()
    check(#forces==0 and removed==0 and o.avgpain==.02,scenario..": skip only shaking; no invalid physics call")
end
for _,scenario in ipairs({"removed_body","removed_target","removed_weapon","replaced_body_org","replaced_target_org"}) do
    r,e,w,o,phys=setup()
    if scenario=="removed_body" then r.valid=false
    elseif scenario=="removed_target" then e.valid=false
    elseif scenario=="removed_weapon" then w.valid=false
    elseif scenario=="replaced_body_org" then r.organism={pulse=70}
    else e.organism={pulse=70} end
    tick()
    check(removed==1 and #forces==0 and wmReads==0 and o.avgpain==0,scenario..": safely cancel timer")
end
for _,pulse in ipairs({0/0,math.huge,-math.huge}) do
    r,e,w,o,phys=setup();o.pulse=pulse;tick()
    check(#forces==0 and o.avgpain==.02,"nonfinite pulse cannot reach physics controller")
end
r,e,w,o,phys=setup();o.pulse=nil;tick()
check(#forces==0 and o.avgpain==.02,"missing pulse cannot reach physics controller")
r,e,w,o,phys=setup();r.organism=nil;tick()
check(removed==1 and #forces==0,"removed organism cancels timer")
check(TASER.angles(nil)==nil,"nil ragdoll lookup is safe")
math.random=savedRandom
