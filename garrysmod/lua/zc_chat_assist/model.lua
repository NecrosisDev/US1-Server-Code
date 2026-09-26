-- Pure parsing/completion helpers. Byte spans are converted at the VGUI boundary.
local A = {}
function A.Tokens(text)
    local out, i, open = {}, 1, false
    while i <= #text do
        if text:sub(i,i):match('%s') then i = i + 1 else
            local first, value, quoted = i, '', false
            while i <= #text do
                local c = text:sub(i,i)
                if c == '"' then quoted = not quoted
                elseif c:match('%s') and not quoted then break
                else value = value .. c end
                i = i + 1
            end
            out[#out+1] = {value=value, first=first, last=i-1}
            open = quoted
        end
    end
    return out, open
end
function A.Validate(text, commands)
    if text:sub(1,1) ~= '!' then return true end
    local tokens, open = A.Tokens(text)
    local cmd = commands[(tokens[1] and tokens[1].value or ''):lower()]
    -- Uncatalogued addon commands remain owned by their original handler.
    if not cmd then
        local typed=(tokens[1] and tokens[1].value or ''):lower()
        for name in pairs(commands) do
            if name:sub(1,#typed)==typed then return false, 'Complete the command name before sending.' end
        end
        return true
    end
    if cmd.allowed == false then return false, 'You do not have access to this command.' end
    if not cmd.args then return true end
    if open then return false, 'Close the double quote before sending.' end
    local n = 2
    for _, arg in ipairs(cmd.args) do
        local token = tokens[n]
        if (not token or token.value == '') and not arg.optional then
            return false, 'Missing ' .. arg.label .. '. Usage: ' .. cmd.usage
        end
        if token then
            if arg.kind == 'number' then
                local v = tonumber(token.value)
                if not v or v ~= v or v == math.huge or v == -math.huge then return false, arg.label .. ' must be a number.' end
                if arg.min and v < arg.min or arg.max and v > arg.max then return false, arg.label .. ' is outside the allowed range.' end
            elseif arg.kind == 'bool' and not ({['0']=true,['1']=true,['true']=true,['false']=true})[token.value:lower()] then
                return false, arg.label .. ' must be 0, 1, true or false.'
            end
        end
        if arg.repeatMin and #tokens-n+1<arg.repeatMin then return false, 'Missing ' .. arg.label .. ' arguments.' end
        if arg.rest then return true end
        n = n + 1
    end
    if tokens[n] then return false, 'Too many arguments. Usage: ' .. cmd.usage end
    return true
end
function A.Context(text, caret, commands, commandMode)
    local left = text:sub(1,caret)
    if commandMode and left:sub(1,1) == '!' then
        local tokens = A.Tokens(left)
        if #tokens <= 1 and not left:find('%s') then return {kind='command', first=1, last=#text:match('^%S*'), stem=left:lower()} end
        local cmd = commands[(tokens[1] and tokens[1].value or ''):lower()]
        if cmd and cmd.args then
            local fresh = left:sub(-1):match('%s') and not select(2,A.Tokens(left))
            local index = #tokens - (fresh and 0 or 1)
            local arg = cmd.args[index]
            if arg and arg.kind == 'player' then
                local t = not fresh and tokens[#tokens]
                local first = t and t.first or caret+1
                local all = A.Tokens(text)
                local last = caret
                for _, item in ipairs(all) do if item.first == first then last=item.last end end
                return {kind='player', first=first,last=last,stem=t and t.value:lower() or ''}
            end
        end
        return
    end
    local first, mark, stem = left:match('()([@:])([^@:%s]*)$')
    if not first then
        first,stem=left:match('()@([^@:]*)$')
        if first then mark='@' end
    end
    if not first or first > 1 and not left:sub(first-1,first-1):match('%s') then return end
    local tail = text:sub(caret+1):match('^[^@:%s]*') or ''
    local last = caret + #tail
    if mark == ':' and text:sub(last+1,last+1) == ':' then last=last+1 end
    return {kind=mark=='@' and 'mention' or 'emoji',first=first,last=last,stem=stem:lower()}
end
function A.Suggestions(ctx, commands, names, emojis)
    local rows = {}
    if not ctx then return rows end
    local function add(label, value, detail)
        if label:lower():sub(1,#ctx.stem) == ctx.stem then rows[#rows+1]={label=label,value=value,detail=detail} end
    end
    if ctx.kind == 'command' then
        for name, cmd in pairs(commands) do if cmd.allowed ~= false then add(name,name,cmd.usage) end end
    elseif ctx.kind == 'emoji' then
        for name in pairs(emojis) do add(name,':'..name..':') end
    else
        for _, name in ipairs(names) do
            -- A quote cannot be represented safely in ULib's quoted nickname token.
            if ctx.kind == 'mention' then add(name,'@'..name)
            elseif not name:find('["%c]') then add(name,'"'..name..'"') end
        end
    end
    table.sort(rows,function(a,b) return a.label:lower()<b.label:lower() end)
    while #rows>8 do table.remove(rows) end
    return rows
end
function A.Apply(text, ctx, value)
    local last=ctx.last
    if ctx.kind=='mention' and text:sub(ctx.first,ctx.first+#value-1):lower()==value:lower() then
        last=math.max(last,ctx.first+#value-1)
    end
    local suffix=text:sub(last+1)
    local inserted=value .. (suffix:match('^%s') and '' or ' ')
    local prefix=text:sub(1,ctx.first-1)..inserted
    return prefix..suffix,#prefix
end
return A
