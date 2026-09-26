assert(SERVER)
assert(not ZCMedicalBench20260919,'benchmark already active')
local U=include('zc_justice_v3/util.lua')
local C=include('zc_justice_v3/config.lua')
local Old=include('zc_justice_v3/medical_core.lua')(U,C)
local New=include('zc_incident_20260919/medical_core_candidate.lua')(U,C)
local old,new=Old.new(),New.new()
old:state('bench','life','round')
new:state('bench','life','round')
local r={started=os.time(),jit=jit and jit.version,rows={},comparisons=0,stopReason='complete'}
local seq=0
local id='ZCMedicalBench20260919'
local function finish()
    timer.Remove(id)
    ZCMedicalBench20260919=nil
    file.Write('zc_incident_20260919/medical_benchmark.json',util.TableToJSON(r,false))
    print('ZC_MEDICAL_BENCH_COMPLETE',#r.rows,r.stopReason)
end
ZCMedicalBench20260919={finish=finish}
local function batch(m)
    local t=SysTime()
    for i=1,16 do
        local before=(seq+i)%2==0 and 4900 or 4901
        m:change('bench',seq+i,'blood',before,9801-before,nil)
    end
    return (SysTime()-t)*1000
end
timer.Create(id,1,24,function()
    local row={}
    if #r.rows%2==0 then row.oldMs=batch(old);row.newMs=batch(new)
    else row.newMs=batch(new);row.oldMs=batch(old) end
    seq=seq+16
    if U.canonical(old.states)~=U.canonical(new.states)then
        r.stopReason='differential failure';finish();return
    end
    r.comparisons=r.comparisons+1
    r.rows[#r.rows+1]=row
    if row.oldMs+row.newMs>3 then r.stopReason='diagnostic time limit';finish()
    elseif #r.rows>=24 then finish()end
end)
