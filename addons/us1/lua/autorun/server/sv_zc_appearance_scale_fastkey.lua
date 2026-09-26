-- Exact-source compatibility repair: avoid full appearance copies in a scale-only check.
-- No cadence, network schema, appearance values, hulls, or scale setters are changed.
if not SERVER then return end
local version='20260919.1'
local event,id='Player Think','HG.Appearance.SlidersScaleSync'
local runtimePath='homigrad/new_appearance/sliders/sv_sliders_runtime.lua'
local corePath='homigrad/new_appearance/sliders/sh_sliders_core.lua'
local function candidateFactory(APmodule)
 return function(ply)
    if not IsValid(ply) or not ply:Alive() or IsValid(ply.FakeRagdoll) then return end
    if not APmodule.Sliders.IsEnabled() then
        if ply._hgAppearanceScaleCache ~= nil
            or ply:GetNWFloat("hg_appearance_height_scale", 1) ~= 1
            or ply:GetNWFloat("hg_appearance_body_scale", 1) ~= 1 then
            APmodule.ResetPlayerScale(ply)
        end
        return
    end

    local appearance = ply._hgAppearanceTemporaryScale or ply.CurAppearance
    if not appearance then return end

    -- The scale key normalizes its four fields; copying clothes and attachments here is unnecessary.
    local wantedCache = APmodule.BuildScaleCacheKey(ply:GetModel(), appearance)
    if ply._hgAppearanceScaleCache ~= wantedCache then
        APmodule.ApplyPlayerScale(ply, appearance)
    end
 end
end
local reported={}
local function decline(reason)
 if not reported[reason]then reported[reason]=true;print('[ZC Appearance Scale] stock path retained: '..reason)end
 return false
end
local function install()
 local previous=ZCAppearanceScaleOptimization20260919
 if previous and(previous.disabled or previous.IsActive())then return end
 local ap=hg and hg.Appearance
 local original=(hook.GetTable()[event]or{})[id]
 if not ap or not original or not hook.GetULibTable then return false end
 if not isfunction(ap.NormalizeAppearanceTable)or not isfunction(ap.BuildScaleCacheKey)or not isfunction(ap.ApplyPlayerScale)then return false end
 local runtime=file.Read(runtimePath,'LUA');local core=file.Read(corePath,'LUA')
 if not runtime or util.SHA256(runtime)~='f56ca220b3206e54e1149bfb3d0aaa885d5ee4167ecf66f6ebc31e39cf14e689' or not core or util.SHA256(core)~='2341dd0bdcee23c5a25d337f2a5b2afdfde35ec42ba491dd25d343025378f922'then return decline('source version changed')end
 local d=debug.getinfo(original,'S')
 if d.source~='@lua/'..runtimePath or d.linedefined~=143 then return decline('callback owner changed')end
 local normalizer=debug.getinfo(ap.NormalizeAppearanceTable,'S')
 local cacheKey=debug.getinfo(ap.BuildScaleCacheKey,'S')
 if normalizer.source~='@lua/'..corePath or normalizer.linedefined~=98 or cacheKey.source~='@lua/'..corePath or cacheKey.linedefined~=68 then return decline('scale helper owner changed')end
 local previousNil=false
 for i=1,10 do
  local n,v=debug.getupvalue(ap.NormalizeAppearanceTable,i)
  if n=='previousNormalize'then previousNil=v==nil end
 end
 if not previousNil then return decline('normalizer chain changed')end
 local apply=debug.getinfo(ap.ApplyPlayerScale,'S')
 if apply.source~='@lua/'..runtimePath or apply.linedefined~=54 then return decline('scale setter owner changed')end
 local priority
 for p,rows in pairs(hook.GetULibTable()[event]or{})do if rows[id]and rows[id].fn==original then priority=p end end
 if priority==nil then return decline('callback priority unavailable')end
 local candidate=candidateFactory(ap)
 local state={version=version,original=original,candidate=candidate,priority=priority,normalizer=ap.NormalizeAppearanceTable,apply=ap.ApplyPlayerScale}
 function state.IsActive()return(hook.GetTable()[event]or{})[id]==candidate end
 function state.Rollback()
  if not state.IsActive()then return false,'callback owner changed'end
  state.disabled=true;hook.Add(event,id,original,priority);return true
 end
 hook.Add(event,id,candidate,priority)
 ZCAppearanceScaleOptimization20260919=state
 print('[ZC Appearance Scale] scale-only comparison active ('..version..')')
 return true
end
hook.Add('PostGamemodeLoaded','ZCAppearanceScaleInstall20260919',install)
hook.Add('InitPostEntity','ZCAppearanceScaleInstall20260919',install)
install()
timer.Simple(0,install)
