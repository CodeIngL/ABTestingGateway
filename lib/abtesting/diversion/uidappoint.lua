local modulename = "abtestingDiversionUidappoint"
--[[
    基于uid的appoint的分流
]]--
local _M    = {}
local mt    = { __index = _M }
_M._VERSION = "0.0.1"

local ERRORINFO	= require('abtesting.error.errcode').info

local k_uidset  = 'uidset'
local k_upstream= 'upstream'

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
--- @param	policy  格式:{{upstream = '192.132.23.125', uidset ={ 214214, 23421,12421} }, {}}
--- @return true or false
--- @deprecated client端不再需要校验，管理端和client分开
_M.check = function(self, policy)
    for _, v in pairs(policy) do
        local uidset    = v[k_uidset]
        local upstream  = v[k_upstream]
        
        local v_uidset    = uidset and (type(uidset) == 'table')
        local v_upstream  = upstream and upstream ~= ngx.null
        
        if not v_uidset or not v_upstream then
            local info = ERRORINFO.POLICY_INVALID_ERROR 
            local desc = ' k_uidset or k_upstream error'
            return {false, info, desc}
        end
        
        for _, uid in pairs(uidset) do 
            if not tonumber(uid) then
                local info = ERRORINFO.POLICY_INVALID_ERROR 
                local desc = 'uid invalid '
                return {false, info, desc}
            end
        end
        --TODO: need to check upstream alive
    end
    
    return {true}
end

--	policyData will be in hash table  uid:upstream
_M.set = function(self, policy)
    local database  = self.database 
    local policyLib = self.policyLib
    
    database:init_pipeline()
    for _, v in pairs(policy) do
        local uidset   = v[k_uidset]
        local upstream = v[k_upstream] 
        for _, uid in pairs(uidset) do
            database:hset(policyLib, uid, upstream)
        end
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
    
    local database, key = self.database, self.policyLib
    
    local backend, err = database:hget(key, uid)
    if not backend then error{ERRORINFO.REDIS_ERROR, err} end
    
    if backend == ngx.null then backend = nil end
    
    return backend
end

return _M
