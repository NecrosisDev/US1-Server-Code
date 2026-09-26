if not SERVER then return end
util.AddNetworkString('zcChatAssistCatalog')
local last = setmetatable({}, {__mode='k'})
local function has(t,v) for _,x in ipairs(t) do if x==v then return true end end return false end
local function catalog(ply)
    local result = {}
    local U = ULib
    if not U or not U.cmds or not U.ucl then return result end
    for alias, route in pairs(U.sayCmds or {}) do
        local name = string.Trim(alias):lower()
        if name:match('^![%w_%-]+$') then
            local command = route.__cmd
            local cmd = command and U.cmds.translatedCmds[command:lower()]
            local item = {allowed=command and U.ucl.query(ply,command)==true or false,usage=name}
            if cmd then
                item.args = {}
                local opposite = (cmd.opposite or ''):lower()==command:lower()
                for i, info in ipairs(cmd.args or {}) do
                    if not info.invisible and not info.type.invisible then
                        local fixed = opposite and cmd.oppositeArgs and cmd.oppositeArgs[i] ~= nil
                        local arg = {label=info.hint or 'argument',optional=fixed or has(info,U.cmds.optional),
                            rest=has(info,U.cmds.takeRestOfLine) or info.repeat_min~=nil,repeatMin=info.repeat_min,kind='text'}
                        if not fixed then
                            if info.type==U.cmds.PlayerArg or info.type==U.cmds.PlayersArg then arg.kind='player';arg.label=info.hint or 'player'
                            elseif info.type==U.cmds.NumArg then arg.kind='number';arg.min=info.min;arg.max=info.max;arg.label=info.hint or 'number'
                            elseif info.type==U.cmds.BoolArg then arg.kind='bool' end
                        end
                        if info.repeat_min and info.repeat_min>0 then arg.optional=false end
                        item.args[#item.args+1]=arg
                        item.usage=item.usage..' '..(arg.optional and '[' or '<')..arg.label..(arg.optional and ']' or '>')
                    end
                end
            end
            result[name]=item
        end
    end
    -- Native COMMANDS has freeform help, not a typed schema. Do not invent one.
    for name, cmd in pairs(COMMANDS or {}) do
        local alias='!'..name
        if not result[alias] then
            result[alias]={allowed=COMMAND_ACCES and COMMAND_ACCES(ply,cmd)==true or false,
                usage=alias..(type(cmd[3])=='string' and (' '..cmd[3]) or '')}
        end
    end
    return result
end
net.Receive('zcChatAssistCatalog',function(bits,ply)
    if bits~=0 or not IsValid(ply) or ply:IsBot() or (last[ply] or -100)>CurTime()-5 then return end
    last[ply]=CurTime()
    local packed=util.Compress(util.TableToJSON(catalog(ply)))
    if not packed or #packed>60000 then return end
    net.Start('zcChatAssistCatalog');net.WriteUInt(#packed,16);net.WriteData(packed,#packed);net.Send(ply)
end)
