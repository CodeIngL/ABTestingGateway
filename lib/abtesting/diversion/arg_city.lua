local modulename = "abtestingDiversionArgCity"
--[[
    ���ڲ���city�ķ���
]]--
local _M    = {}
local mt    = { __index = _M }
_M._VERSION = "0.0.1"

local ERRORINFO	= require('abtesting.error.errcode').info

local k_city      = 'city'
local k_upstream    = 'upstream'

--- �������
--- @param	database ���ݿ����
--- @param policyLib ��ǰ׺
_M.new = function(self, database, policyLib)
    if not database then
        error{ERRORINFO.PARAMETER_NONE, 'need avaliable redis db'}
    end
    if not policyLib then
        error{ERRORINFO.PARAMETER_NONE, 'need avaliable policy lib'}
    end

    self.database = database --���ݿ����
    self.policyLib = policyLib --��ǰ׺
    return setmetatable(self, mt)
end

--- У������policy�Ƿ���һ�����ϵĸ�ʽ
--- @param	policy  ��ʽ:{{city = 'BJ0101', upstream = '192.132.23.125'}}
--- @return true or false
--- @deprecated client�˲�����ҪУ�飬����˺�client�ֿ�
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

--- ��������policy��redis��
--- @param	policy  ��ʽ:{{city = 'BJ0101', upstream = '192.132.23.125'}}
_M.set = function(self, policy)
    local database  = self.database --���ݿ����
    local policyLib = self.policyLib --��ǰ׺

    database:init_pipeline()
    for _, v in pairs(policy) do
        database:hset(policyLib, v[k_city], v[k_upstream])
    end
    local ok, err = database:commit_pipeline()
    if not ok then 
        error{ERRORINFO.REDIS_ERROR, err} 
    end

end

--- ������е�����policy
--- @return policy��
_M.get = function(self)
    local database  = self.database  --���ݿ����
    local policyLib = self.policyLib --��ǰ׺

    local data, err = database:hgetall(policyLib)
    if not data then 
        error{ERRORINFO.REDIS_ERROR, err} 
    end

    return data
end

--- ���city��Ӧ��upstream
--- @return upstream or nil
_M.getUpstream = function(self, city)
    
    local database	= self.database --���ݿ����
    local policyLib = self.policyLib --��ǰ׺
    
    local upstream, err = database:hget(policyLib , city)
    if not upstream then error{ERRORINFO.REDIS_ERROR, err} end
    
    if upstream == ngx.null then
        return nil
    else
        return upstream
    end

end


return _M
