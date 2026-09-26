-- Pure mode snapshots. Never invokes a live GuiltCheck callback as a query.
return function(U,C)
    local M={}
    local teams={tdm=true,cstrike=true,hl2dm=true,gwars=true,criresp=true,wildcard=true,
        riot=true,uncontainedriot=true,coop=true,defense=true}
    function M.compile(input)
        local s=U.copy(input);U.id(s.name)
        local kind,tdm,hidden=nil,false,false
        for _,name in ipairs(s.chain or {s.name})do
            if name=="hmcd" or name=="fear" then hidden=true;kind="homicide" end
            if not kind and teams[name] then kind="team" end
            if name=="tdm" or name=="cstrike" then tdm=true end
        end
        if s.has_subroles then hidden=true;kind="homicide" end
        local disabled=s.guilt_disabled or s.developer or s.mutator_disabled
        if s.name=="masscasualty" or s.name=="fear" then disabled=true end
        return {name=s.name,variant=s.variant,kind=kind,hidden=hidden,public_tdm=tdm and not hidden,
            scored=not disabled and kind~=nil,policy=C.policy,custom_rule_complete=s.custom_rule_complete==true,
            reason=disabled and "CONFIGURED_UNSCORED" or kind and "REGISTERED_FAMILY" or "UNSUPPORTED_MODE"}
    end
    function M.relation(mode,a,v)
        if a.account==v.account then return "exempt"end
        if not mode.scored or a.exempt or v.exempt then return "exempt"end
        if mode.kind=="homicide" then return a.traitor==v.traitor and "protected" or "enemy"end
        if mode.kind=="team" then
            if a.team==nil or v.team==nil then return "unsupported"end
            return a.team==v.team and "protected" or "enemy"
        end
        return "unsupported"
    end
    return M
end
