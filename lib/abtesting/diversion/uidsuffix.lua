local modulename = "abtestingDiversionUidsuffix"
--[[
    基于uid后缀的分流
]]--
local _M    = {}
local mt    = { __index = _M }
_M._VERSION = "0.0.1"

local ERRORINFO	= require('abtesting.error.errcode').info

local k_suffix      = 'suffix'
local k_upstream    = 'upstream'

--- 构造对象
--- @param	database 数据库对象
--- @param policyLib 键前缀
_M.new = function(self, database, policyLib)
    if not database then
        error{ERRORINFO.PARAMETER_NONE, 'need avaliable redis db'}
    end
    if not policyLib then
        error{ERRORINFO.PARAMETER_NONE, 'need avaliable policy lib'}
    end

    self.database = database --数据库对象
    self.policyLib = policyLib
    return setmetatable(self, mt)
end

--- 校验数据policy是否是一个符合的格式
--- @param	policy  格式:{{suffix = '4', upstream = '192.132.23.125'}}
--- @return true or false
--- @deprecated client端不再需要校验，管理端和client分开
_M.check = function(self, policy)
    for _, v in pairs(policy) do
        local suffix    = tonumber(v[k_suffix])
        local upstream  = v[k_upstream]

        if not suffix or not upstream then
            return {false, ERRORINFO.POLICY_INVALID_ERROR, ' need '..k_suffix..' and '..k_upstream}
        end

        if suffix < 0 or suffix > 9 then
            return {false, ERRORINFO.POLICY_INVALID_ERROR, 'suffix is not between [0 and 10]'}
        end
    end

    return {true}
end

_M.set = function(self, policy)
    local database  = self.database 
    local policyLib = self.policyLib

    database:init_pipeline()
    for _, v in pairs(policy) do
        database:hset(policyLib, v[k_suffix], v[k_upstream])
    end
    local ok, err = database:commit_pipeline()
    if not ok then 
        error{ERRORINFO.REDIS_ERROR, err} 
    end

end

_M.get = function(self)
    local database  = self.database 
    local policyLib = self.policyLib

    local data, err = database:hgetall(policyLib)
    if not data then 
        error{ERRORINFO.REDIS_ERROR, err} 
    end

    return data
end

_M.getUpstream = function(self, uid)
    if not tonumber(uid) then
        return nil
    end
    
    local suffix	= uid % 10; 
    local database	= self.database
    local policyLib = self.policyLib
    
    local upstream, err = database:hget(policyLib , suffix)
    if not upstream then error{ERRORINFO.REDIS_ERROR, err} end
    
    if upstream == ngx.null then
        return nil
    else
        return upstream
    end

end


return _M
