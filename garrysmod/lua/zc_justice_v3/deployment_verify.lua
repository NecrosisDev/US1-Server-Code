-- Server-only cold-start verification. No balance, damage, or role writes.
local V = {}
local function uses(fn, wanted, depth, seen)
    if type(fn) ~= 'function' or (depth or 0) > 6 then return false end
    seen = seen or {}
    if seen[fn] then return false end
    seen[fn] = true
    for index = 1, 80 do
        local name, value = debug.getupvalue(fn, index)
        if not name then break end
        if name == wanted then return true end
        if type(value) == 'function' and uses(value, wanted, (depth or 0) + 1, seen) then
            return true
        end
    end
    return false
end
function V.check(expected)
    assert(SERVER and engine.ActiveGamemode() == 'zcity', 'Wrong realm/gamemode')
    assert(expected.version == '3.3.0-shadow.2' and expected.enforcement == false)
    local config = include('zc_justice_v3/config.lua')
    assert(config.version == expected.version and config.enforcement_available == false)
    local observer, runtime = ZCJusticeV3Shadow, ZCJusticeV3Integration
    assert(observer and observer.enabled and observer.version == expected.version, 'Wrong observer')
    assert(runtime and runtime.enabled and runtime.version == expected.version, 'Wrong integration')
    assert(runtime.stats.errors == 0, 'Observer has an error')
    assert(runtime.stats.financial_writes == 0 and runtime.stats.public_writes == 0)
    assert(runtime.medical_model and runtime.MedicalMutation and runtime.WithMedicalTerminal)
    local hashes = {}
    for _, entry in ipairs(expected.files) do
        local body = assert(file.Read(entry.game, 'GAME'), 'Missing ' .. entry.game)
        assert(util.SHA256(body) == entry.sha256, 'Backing file changed: ' .. entry.game)
        local mounted = assert(file.Read(entry.lua, 'LUA'), 'Missing mounted source: ' .. entry.lua)
        assert(util.SHA256(mounted) == entry.sha256, 'Mounted source differs: ' .. entry.lua)
        hashes[entry.lua] = entry.sha256
    end
    for name, hash in pairs(expected.protected) do
        local body = assert(file.Read(name, 'GAME'), 'Protected source missing: ' .. name)
        assert(util.SHA256(body) == hash, 'Protected source changed: ' .. name)
    end
    local J, F, M, P = ZCityGuiltJustice, ZCityFFBrain, ZCityMetaSafety, ZCityPillCompat
    assert(J and type(J.Change) == 'function' and type(J.Assess) == 'function' and type(J.Flush) == 'function')
    assert(M and type(M.Change) == 'function', 'Privacy layer missing')
    assert(F and F.Settings.scale == 0.0005 and F.Settings.absoluteCap == 0.125)
    assert(zb and zb.modes and zb.modes.tdm and zb.modes.hmcd)
    assert(F.VictimScale(zb.modes.tdm) == 0.75 and F.VictimScale(zb.modes.hmcd) == 1)
    assert(P and type(P.ProtectEvent) == 'function', 'Pill protection unavailable')
    local hooktable = hook.GetTable()
    local guilt = hooktable.HomigradDamage and hooktable.HomigradDamage.GuiltReg
    assert(type(guilt) == 'function', 'Original guilt handler missing')
    -- Rebind synchronously and verify the installed guard's exact ownership.
    -- No player/organism is passed through a synthetic gameplay operation.
    P.ProtectEvent('Org Think', 'organism')
    local org_hooks = hook.GetTable()['Org Think']
    local guard = org_hooks and P.wraps[org_hooks] and P.wraps[org_hooks].Main
    assert(guard and guard.wrapper == org_hooks.Main, 'Pill guard does not own Main')
    assert(uses(guard.original, '_zcj_med_kill'), 'Guard still delegates to old physiology')
    assert(hook.GetTable().HomigradDamage.GuiltReg == guilt, 'Guilt handler changed')
    local organism = assert(hg and hg.organism)
    local modules, inputs = assert(organism.module), assert(organism.input_list)
    for _, name in ipairs({'blood', 'lungs', 'metabolism'}) do
        assert(modules[name] and uses(modules[name][2], '_zcj_med'), 'Missing delta tap: ' .. name)
    end
    assert(uses(modules.lungs[2], '_zcj_med_terminal'), 'Missing actual terminal tap')
    assert(uses(inputs.skull, '_zcj_med'), 'Skull attribution tap missing')
    assert(uses(inputs.arteria, '_zcj_med_artery'), 'Arterial attribution tap missing')
    assert(timer.Exists('FiberwireExtras_Check'), 'Fibre-wire timer missing')
    local manual = false
    for _, binding in ipairs(runtime.wrappers or {}) do
        assert(binding.table[binding.key] == binding.wrapper, 'Adapter ownership changed: ' .. binding.label)
        if binding.label == 'private_manual_wounds' then manual = true end
    end
    assert(manual, 'Manual wound adapter missing')
    runtime.coverage.medical = 'blood_brain_skull_taps_active_oxygen_poison_and_full_causality_pending'
    runtime:WriteStatus()
    return {version=expected.version, deployment_id=expected.deployment_id,
        passed=true, time=os.time(), enforcement=false, runtime_errors=runtime.stats.errors,
        carrier_guard=true, mounted_hashes=hashes, source_wrappers=#runtime.wrappers,
        financial_writes=0, public_writes=0, full_cause_coverage=false,
        map=game.GetMap(), observer_session=observer.session}
end
return V
