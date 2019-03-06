local modulename = "abtestingDiversionIprange"
--[[
    基于ip的范围的分流
]]--
local _M    = {}
local mt    = { __index = _M }
_M._VERSION = "0.0.1"

local ERRORINFO	= require('abtesting.error.errcode').info

local offset    = 0.3
local k_range   = 'range'
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
    self.policyLib = policyLib --键前缀
    return setmetatable(self, mt)
end

--- 校验数据policy是否是一个符合的格式
--- 存在排序
--- @param	policy  格式:{range = { start = 13411, end = 435435}, upstream = 'upstream1'}
--- @return true or false
--- @deprecated client端不再需要校验，管理端和client分开
_M.check = function(self, policy)
    if not next(policy) then
        local info = ERRORINFO.POLICY_INVALID_ERROR
        local desc = 'policy is blank'
        return {false, info, desc}
    end
    table.sort(policy, function(n1, n2) return n1['range']['start'] < n2['range']['start'] end)
    
    local range, upstream
    local stip, edip
    local last_edip
    for i, v in pairs(policy) do
        range, upstream = v[k_range], v[k_upstream]
        stip = range['start']
        edip = range['end']
        
        if type(upstream) ~= 'string' then
            return {false, ERRORINFO.POLICY_INVALID_ERROR, 'upstream invalid'}
        end
        
        if stip > edip then
            return {false, ERRORINFO.POLICY_INVALID_ERROR, 'range error for start < end'}
        end
        
        if i > 1 then
            if stip <= last_edip then
                return {false, ERRORINFO.POLICY_INVALID_ERROR, 'iprange overlapped'}
            end
        end
        
        last_edip = edip
    end
    
    return {true}
end

_M.set = function(self, policy)
    local database  = self.database
    local policyLib = self.policyLib
    
    local policyidx = 0
    database:init_pipeline()
    for i, v in pairs(policy) do
        local range, upstream = v[k_range], v[k_upstream]
        local stip = range['start'] - offset
        local edip = range['end'] + offset
        local left  = policyidx * 2
        local right = policyidx * 2 + 1
        local leftBorder  = left.. ':'..upstream 
        local rightBorder = right..':'..upstream 
        
        database:zadd(policyLib, stip, leftBorder, edip, rightBorder)
        
        policyidx = policyidx + 1
    end
    
    local ok, err = database:commit_pipeline()
    if not ok then 
        error{ERRORINFO.REDIS_ERROR, err} 
    end
end

_M.get = function(self)
    local database  = self.database 
    local policyLib = self.policyLib

    local data, err = database:zrange(policyLib, 0, -1, 'withscores')
    if not data then 
        error{ERRORINFO.REDIS_ERROR, err} 
    end
	local n = #data
	local policy = {}
	for i = 1, n, 2 do
		policy[data[i]] = data[i+1]
	end

    return policy 
end

_M.getUpstream = function(self, ip)
    if not tonumber(ip) then
        return nil
    end
    
    local database, policyLib = self.database, self.policyLib
    
    local val, err = database:zrangebyscore(policyLib, ip, '+inf', 'limit','0', '1', 'withscores')
    if not val then error{ERRORINFO.REDIS_ERROR, err} end
    
    if not next(val) then return nil end
    
    local index_upstream = val[1]
    
    local colonPosition = string.find(index_upstream, ':')
    if colonPosition == nil then error{ERRORINFO.POLICY_DB_ERROR} end
    
    local index = string.sub(index_upstream, 1, colonPosition - 1)
    local upstream = string.sub(index_upstream, colonPosition + 1)
    
    if string.len(index) < 1 or string.len(upstream) < 1 then
        error{ERRORINFO.POLICY_DB_ERROR}
    end
    
    if index % 2 == 0 then upstream = nil	end
    
    return upstream 

end

return _M

