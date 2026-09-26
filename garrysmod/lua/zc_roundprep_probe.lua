-- Manual short-lived round-transition observation. Never starts a round.
-- Step 2 (2026-09-21): also times the ZB_PreRoundStart / ZB_StartRound / ZB_EndRound listener fan-out.
-- zb:EndRoundThink runs hook.Run("ZB_PreRoundStart") (sv_roundsystem.lua:156) inside the same frame, so zc_perf
-- bills every listener to Think/zb-think. Listeners are wrapped IN PLACE inside hook.GetTable()[event]: ULib owns
-- hook priorities on this server, so re-registering with hook.Add would reorder them. Restore is unchanged -
-- each wrap is recorded in P.targets and P.Stop puts the original back only if nothing else has taken the slot.
assert(SERVER and zb and not ZCRoundStartProbe and not ZCRoundPrepProbe, 'Existing probe or wrong realm')
local P={rows={},targets={},active=true,started=os.time(),map=game.GetMap()}
ZCRoundStartProbe=P
ZCRoundPrepProbe=P
local ROWCAP=2048
local function pack(...) return {n=select('#',...),...} end
local function wrap(t,k,label)
    local old=t[k]; if not isfunction(old) then return end
    local fn
    fn=function(...)
        if not P.active then return old(...) end
        local a=SysTime();local mode=zb.CROUND;local state=zb.ROUND_STATE
        local r=pack(pcall(old,...));local ms=(SysTime()-a)*1000
        if #P.rows<ROWCAP then P.rows[#P.rows+1]={label=label,ms=ms,at=CurTime(),mode=mode,state=state,
            players=#player.GetHumans(),ok=r[1],error=not r[1] and tostring(r[2]) or nil} end
        if not r[1] then error(r[2],0) end
        return unpack(r,2,r.n)
    end
    P.targets[#P.targets+1]={t=t,k=k,old=old,fn=fn};t[k]=fn
end
function P.Stop(reason)
    if not P.active then return end
    P.active=false;timer.Remove('ZCRoundStartProbeTimeout')
    local restored,conflicts=0,{}
    for _,r in ipairs(P.targets) do
        if r.t[r.k]==r.fn then r.t[r.k]=r.old;restored=restored+1
        else conflicts[#conflicts+1]=r.k end
    end
    P.finished=os.time();P.reason=reason;P.restored=restored;P.conflicts=conflicts
    file.Write('zc_roundprep_probe.json',util.TableToJSON({started=P.started,finished=P.finished,
        map=P.map,reason=reason,rows=P.rows,restored=restored,conflicts=conflicts},true))
    print('ROUND_PREP_PROBE_DONE',reason,#P.rows,restored,#conflicts)
end
local ok,err=xpcall(function()
    for _,k in ipairs({'EndRoundThink','RoundStart','KillPlayers','AutoBalance'}) do wrap(zb,k,'zb.'..k) end
    for name,mode in pairs(zb.modes) do
        for _,k in ipairs({'Intermission','GiveEquipment','RoundStart','SpawnPlayers'}) do
            if rawget(mode,k) then wrap(mode,k,name..'.'..k) end
        end
    end
    wrap(game,'CleanUpMap','game.CleanUpMap')
    for _,event in ipairs({'ZB_PreRoundStart','ZB_StartRound','ZB_EndRound'}) do
        local listeners=hook.GetTable()[event]
        if istable(listeners) then
            for name in pairs(listeners) do wrap(listeners,name,event..'/'..tostring(name)) end
        end
    end
    timer.Create('ZCRoundStartProbeTimeout',240,1,function() P.Stop('timeout') end)
end,debug.traceback)
if not ok then P.Stop('setup_error');error(err,0) end
print('ROUND_PREP_PROBE_STARTED',#P.targets,game.GetMap(),#player.GetHumans())
