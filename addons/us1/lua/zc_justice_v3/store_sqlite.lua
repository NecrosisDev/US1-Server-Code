-- Dedicated, result-aware SQLite transactions on an injected engine/test backend.
-- No native balance tables are created or updated by this library on its own.
return function(U)
    local S={};S.__index=S
    function S.new(api,codec,prefix)
        assert(type(prefix)=="string" and prefix:match("^zcj3_[a-z0-9_]+_$"),"invalid isolated prefix")
        assert(type(api.Query)=="function" and type(api.LastError)=="function")
        assert(type(codec.encode)=="function" and type(codec.decode)=="function")
        return setmetatable({api=api,codec=codec,table_name=prefix.."records",busy=false,locked=false},S)
    end
    local function quote(s)
        assert(type(s)=="string" and #s<=1048576 and not s:find("%z"),"invalid SQL text")
        return "'"..s:gsub("'","''").."'"
    end
    function S:q(statement)
        local result=self.api.Query(statement)
        if result==false then error("SQLite failure: "..tostring(self.api.LastError()),0) end
        return result -- nil is a successful statement with no result set.
    end
    function S:initialize()
        return self:transaction(function()
            self:q("CREATE TABLE IF NOT EXISTS "..self.table_name..
                " (space TEXT NOT NULL, id TEXT NOT NULL, payload TEXT NOT NULL, PRIMARY KEY(space,id))")
            local version=self:get("meta","schema")
            if version then assert(version.version==1,"unsupported schema")
            else self:insert("meta","schema",{version=1})end
            return true
        end)
    end
    function S:get(space,key)
        local result=self:q("SELECT payload FROM "..self.table_name.." WHERE space="..quote(space).." AND id="..quote(key).." LIMIT 1")
        if not result or not result[1] then return nil end
        local value=self.codec.decode(result[1].payload)
        assert(type(value)=="table","corrupt persistent row");return value
    end
    function S:put(space,key,value)
        assert(self.busy,"write outside owned transaction")
        local text=self.codec.encode(U.copy(value));assert(type(text)=="string" and #text<=262144,"row too large")
        self:q("INSERT OR REPLACE INTO "..self.table_name.." (space,id,payload) VALUES ("..
            quote(space)..","..quote(key)..","..quote(text)..")")
    end
    function S:insert(space,key,value)
        assert(self.busy,"write outside owned transaction")
        local text=self.codec.encode(U.copy(value));assert(type(text)=="string" and #text<=262144,"row too large")
        self:q("INSERT INTO "..self.table_name.." (space,id,payload) VALUES ("..
            quote(space)..","..quote(key)..","..quote(text)..")")
    end
    function S:scan(space)
        local result=self:q("SELECT id,payload FROM "..self.table_name.." WHERE space="..quote(space).." ORDER BY id") or {}
        local out={};for _,r in ipairs(result)do local v=self.codec.decode(r.payload);assert(type(v)=="table");out[r.id]=v end
        return out
    end
    function S:transaction(fn)
        if self.busy or self.locked then return false,"SQLite transaction ownership unavailable" end
        -- BEGIN may fail because another addon owns a transaction: never roll it back.
        local began,err=pcall(self.q,self,"BEGIN IMMEDIATE")
        if not began then return false,tostring(err)end
        self.busy=true
        local result=U.pack(pcall(fn,self))
        if result[1] then
            local committed,problem=pcall(self.q,self,"COMMIT")
            if not committed then result={n=2,false,problem}end
        end
        if not result[1] then
            local rolled=pcall(self.q,self,"ROLLBACK")
            if not rolled then self.locked=true end
        end
        self.busy=false
        if not result[1] then return false,tostring(result[2])end
        return true,(unpack or table.unpack)(result,2,result.n)
    end
    return S
end
