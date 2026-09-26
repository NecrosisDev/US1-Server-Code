-- Compile the changed method only; preserve immutable/shared-reference upvalues.
return function(original,body,helper,label)
    assert(type(original)=='function','original method missing')
    local names,values={},{}
    for i=1,100 do
        local name,value=debug.getupvalue(original,i)
        if not name then break end
        assert(name:match('^[%a_][%w_]*$'),'unexpected upvalue name')
        assert(type(value)=='function' or type(value)=='table','mutable scalar upvalue: '..name)
        names[#names+1]=name;values[#values+1]=value
    end
    local prefix=#names>0 and ('local '..table.concat(names,',')..'=...\n') or ''
    local changed,n=body:gsub('^function SWEP:[%w_]+%(([^)]*)%)',function(args)
        return 'return function(self'..(args~='' and ','..args or '')..')'
    end,1)
    if n==0 then changed,n=body:gsub('^function util%.ScreenShake%(','return function(',1) end
    assert(n==1,'unsupported method header')
    local factory=CompileString(prefix..(helper or '')..'\n'..changed,label,false)
    assert(type(factory)=='function',tostring(factory))
    setfenv(factory,getfenv(original))
    local replacement=factory(unpack(values))
    assert(type(replacement)=='function','factory did not return a method')
    return replacement,names
end
