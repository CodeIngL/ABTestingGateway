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

    self.database     = database -- 数据库对象
    self.groupLibrary = groupLibrary -- 键前缀 ab:policygroups
    self.baseLibrary  = baseLibrary -- 键前缀 ab:policies
    self.idCountKey = table.concat({groupLibrary, fields.idCount}, separator) --id索引键 ab:policygroups:idCount

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
--- 获取当前策略组的ID，通过对redis键值加获得下一个seq
--- @return the id
_M.getIdCount = function(self)
    local database = self.database
    local key = self.idCountKey --id索引键 ab:policygroups:idCount
    local idCount, err = database:incr(key)
    if not idCount then error{ERRORINFO.REDIS_ERROR, err} end
    return idCount
end

---
--- 向redis保存相关的策略组
--- @param policyGroup 策略组
--- @return allways returned SUCCESS
_M.set = function(self, policyGroup)

    local database = self.database
    local baseLibrary = self.baseLibrary -- 键前缀 ab:policies

    -- 调用策略模块进行逐个写策略组的策略
    local policyMod = policyModule:new(database, baseLibrary)
    local steps = #policyGroup
    local group = {}
    for idx = 1, steps do
        local policy = policyGroup[idx]
        local id = policyMod:set(policy)
        group[idx] = id
    end

    -- 策略组本身写入信息到redis中
    local groupLibrary  = self.groupLibrary -- 键前缀 ab:policygroups
    local groupid       = self:getIdCount()
    local groupKey      = table.concat({groupLibrary, groupid}, separator) -- 键前缀 ab:policygroups:${groupid}
    database:init_pipeline()
    for idx = 1, steps do
        database:rpush(groupKey, group[idx])
    end
    local ok, err = database:commit_pipeline()
    if not ok then error{ERRORINFO.REDIS_ERROR, err} end

    local ret = {}
    ret.groupid = groupid
    ret.group = group
    -- 返回策略组的id，和其内部的策略各个id
    return ret
end

---
--- 根据策略组数据定位相应的策略模块进行检查
--- @param policy 策略组数据
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
