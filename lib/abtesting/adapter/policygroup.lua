---
-- @classmod abtesting.adapter.policy
-- @release 0.0.1
local modulename = "abtestingAdapterPolicyGroup"

local _M = { _VERSION = "0.0.1" }
local mt = { __index = _M }

local ERRORINFO     = require('abtesting.error.errcode').info
local policyModule  = require('abtesting.adapter.policy')
local fields        = require('abtesting.utils.init').fields

local separator = ':'

---
-- policyIO new function
-- @param database opened redis.
-- @param baseLibrary a library(prefix of redis key) of policies.
_M.new = function(self, database, groupLibrary, baseLibrary)
    if not database then
        error{ERRORINFO.PARAMETER_NONE, 'need avaliable redis db'}
    end
    if not baseLibrary then
        error{ERRORINFO.PARAMETER_NONE, 'need avaliable policy baselib'}
    end

    self.database     = database -- ���ݿ����
    self.groupLibrary = groupLibrary -- ��ǰ׺ ab:policygroups
    self.baseLibrary  = baseLibrary -- ��ǰ׺ ab:policies
    self.idCountKey = table.concat({groupLibrary, fields.idCount}, separator) --id������ ab:policygroups:idCount

    local ok, err = database:exists(self.idCountKey)
    if not ok then error{ERRORINFO.REDIS_ERROR,  err} end

    if 0 == ok then
        local ok, err = database:set(self.idCountKey, '-1')
        if not ok then error{ERRORINFO.REDIS_ERROR, err} end
    end
    return setmetatable(self, mt)
end

---
--- get id for current policy
--- ��ȡ��ǰ�������ID��ͨ����redis��ֵ�ӻ����һ��seq
--- @return the id
_M.getIdCount = function(self)
    local database = self.database
    local key = self.idCountKey --id������ ab:policygroups:idCount
    local idCount, err = database:incr(key)
    if not idCount then error{ERRORINFO.REDIS_ERROR, err} end
    return idCount
end

---
--- ��redis������صĲ�����
--- @param policyGroup ������
--- @return allways returned SUCCESS
_M.set = function(self, policyGroup)

    local database = self.database
    local baseLibrary = self.baseLibrary -- ��ǰ׺ ab:policies

    -- ���ò���ģ��������д������Ĳ���
    local policyMod = policyModule:new(database, baseLibrary)
    local steps = #policyGroup
    local group = {}
    for idx = 1, steps do
        local policy = policyGroup[idx]
        local id = policyMod:set(policy)
        group[idx] = id
    end

    -- �����鱾��д����Ϣ��redis��
    local groupLibrary  = self.groupLibrary -- ��ǰ׺ ab:policygroups
    local groupid       = self:getIdCount()
    local groupKey      = table.concat({groupLibrary, groupid}, separator) -- ��ǰ׺ ab:policygroups:${groupid}
    database:init_pipeline()
    for idx = 1, steps do
        database:rpush(groupKey, group[idx])
    end
    local ok, err = database:commit_pipeline()
    if not ok then error{ERRORINFO.REDIS_ERROR, err} end

    local ret = {}
    ret.groupid = groupid
    ret.group = group
    -- ���ز������id�������ڲ��Ĳ��Ը���id
    return ret
end

---
--- ���ݲ��������ݶ�λ��Ӧ�Ĳ���ģ����м��
--- @param policy ����������
--- @return allways returned SUCCESS
_M.check = function(self, policyGroup)
    local steps = #policyGroup
    local policyMod = policyModule:new(self.database, self.baseLibrary)
    for idx = 1, steps do
        local policy    = policyGroup[idx]
        local chkinfo   = policyMod:check(policy)
        local valid = chkinfo[1]
        local info  = chkinfo[2]
        local desc  = chkinfo[3]
        if not valid then
            if not desc then
                return {valid, info, 'policy NO.'..idx..' not valid'}
            else
                return {valid, info, 'policy NO.'..idx..desc}
            end
        end
    end
    return {true}
end

---
--- delete a policy from specified redis lib
--- @param id the policy identify
--- @return allways returned SUCCESS
_M.del = function(self, id)
    local database      = self.database
    local groupLibrary  = self.groupLibrary

    local groupKey      = table.concat({groupLibrary, id}, separator)

    local group, err = database:lrange(groupKey, 0, -1)
    if not group or type(group) ~= 'table' then 
        error{ERRORINFO.REDIS_ERROR, err} 
    end

    local tmpkeys  = {}
    local idx   = 0
    for _, policyid in pairs(group) do
        idx = idx + 1

        local policyLib = table.concat({self.baseLibrary, policyid}, separator)
        local keys, err = database:keys(policyLib..'*')
        if not keys then error{ERRORINFO.REDIS_ERROR, err} end

        tmpkeys[idx] = keys
    end

    database:init_pipeline()
    for _, v in pairs(tmpkeys) do
        for _, vv in pairs(v) do
            database:del(vv)
        end
    end
    database:del(groupKey)

    local ok, err = database:commit_pipeline()
    if not ok then error{ERRORINFO.REDIS_ERROR, err} end
end

_M.get = function(self, id)

    local database = self.database
    local groupLibrary  = self.groupLibrary
    local groupKey      = table.concat({groupLibrary, id}, separator)

    local group, err = database:lrange(groupKey, 0, -1)
    if not group or type(group) ~= 'table' then 
        error{ERRORINFO.REDIS_ERROR, err} 
    end

    local ret = {}
    ret.groupid = id
    ret.group = group

    return ret
end
return _M
