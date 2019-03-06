local modulename = "abtestingDiversionUrl"
--[[
    基于url的分流策略
]]--
local _M    = {}
local mt    = { __index = _M }
_M._VERSION = "0.0.1"

local ERRORINFO	= require('abtesting.error.errcode').info

local k_url      = 'url'
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

--- 校验数据policy合法
--- @param	policy  格式:{{url = '/a/b/c/d', upstream = '192.132.23.125'}}
--- @return true or false
--- @deprecated client端不再需要校验，管理端和client分开
_M.check = function(self, policy)
    for _, v in pairs(policy) do
        local url       = v[k_url]
        local upstream  = v[k_upstream]

        if not url or not upstream then
            return {false, ERRORINFO.POLICY_INVALID_ERROR, ' need '..k_url..' and '..k_upstream}
        end
    end
    return {true}
end

--- 设置数据policy入库
--- @param	policy  格式:{{url = '/a/b/c/d', upstream = '192.132.23.125'}}
--- @return
_M.set = function(self, policy)
    local database  = self.database 
    local policyLib = self.policyLib

    database:init_pipeline()
    for _, v in pairs(policy) do
        database:hset(policyLib, v[k_url], v[k_upstream])
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

_M.getUpstream = function(self, url)

    local url           = url; 
    local database	= self.database
    local policyLib = self.policyLib
    
    local upstream, err = database:hget(policyLib , url)
    if not upstream then error{ERRORINFO.REDIS_ERROR, err} end
    
    if upstream == ngx.null then
        return nil
    else
        return upstream
    end

end


return _M
