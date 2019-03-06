local modulename = "abtestingDiversionArgCity"
--[[
    基于参数city的分流
]]--
local _M    = {}
local mt    = { __index = _M }
_M._VERSION = "0.0.1"

local ERRORINFO	= require('abtesting.error.errcode').info

local k_city      = 'city'
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
    self.policyLib = policyLib --键前缀
    return setmetatable(self, mt)
end

--- 校验数据policy是否是一个符合的格式
--- @param	policy  格式:{{city = 'BJ0101', upstream = '192.132.23.125'}}
--- @return true or false
--- @deprecated client端不再需要校验，管理端和client分开
_M.check = function(self, policy)
    for _, v in pairs(policy) do
        local city      = v[k_city]
        local upstream  = v[k_upstream]

        if not city or not upstream then
            return {false, ERRORINFO.POLICY_INVALID_ERROR, ' need '..k_city..' and '..k_upstream}
        end

    end

    return {true}
end

--- 设置数据policy到redis中
--- @param	policy  格式:{{city = 'BJ0101', upstream = '192.132.23.125'}}
_M.set = function(self, policy)
    local database  = self.database --数据库对象
    local policyLib = self.policyLib --键前缀

    database:init_pipeline()
    for _, v in pairs(policy) do
        database:hset(policyLib, v[k_city], v[k_upstream])
    end
    local ok, err = database:commit_pipeline()
    if not ok then 
        error{ERRORINFO.REDIS_ERROR, err} 
    end

end

--- 获得所有的数据policy
--- @return policy表
_M.get = function(self)
    local database  = self.database  --数据库对象
    local policyLib = self.policyLib --键前缀

    local data, err = database:hgetall(policyLib)
    if not data then 
        error{ERRORINFO.REDIS_ERROR, err} 
    end

    return data
end

--- 获得city对应的upstream
--- @return upstream or nil
_M.getUpstream = function(self, city)
    
    local database	= self.database --数据库对象
    local policyLib = self.policyLib --键前缀
    
    local upstream, err = database:hget(policyLib , city)
    if not upstream then error{ERRORINFO.REDIS_ERROR, err} end
    
    if upstream == ngx.null then
        return nil
    else
        return upstream
    end

end


return _M
