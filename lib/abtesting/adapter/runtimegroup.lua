---
--- @classmod abtesting.adapter.runtime
--- @release 0.0.1
local modulename = "abtestingAdapterRuntimeGroup"

local _M = {}
local metatable = {__index = _M}

_M._VERSION = "0.0.1"

local ERRORINFO         = require('abtesting.error.errcode').info
local runtimeModule     = require('abtesting.adapter.runtime')
local systemConf        = require('abtesting.utils.init')
local policyModule      = require('abtesting.adapter.policy')
local policyGroupModule = require('abtesting.adapter.policygroup')
local divtypes          = systemConf.divtypes
local policyLib         = systemConf.prefixConf.policyLibPrefix
local policyGroupLib    = systemConf.prefixConf.policyGroupPrefix
local indices           = systemConf.indices 
local fields            = systemConf.fields

---
--- runtimeInfoIO new function
--- @param database  opened redis -- 数据库打开redis
--- @param baseLibrary a library(prefix of redis key) of runtime info -- baseLibrary运行时信息的库（redis键的前缀）
--- @return runtimeInfoIO object -- runtimeInfo对象
_M.new = function(self, database, baseLibrary)
	if not database then
		error{ERRORINFO.PARAMETER_NONE, 'need a object of redis'}
	end if not baseLibrary then
	    error{ERRORINFO.PARAMETER_NONE, 'need a library of runtime info'}
    end

    self.database     = database --数据库对象
    self.baseLibrary  = baseLibrary --键前缀  ab:runtimeInfo

    return setmetatable(self, metatable)
end

---
--- set runtime info(diversion modulename and diversion metadata key) -- 设置运行时信息（分流模块名称和分流元数据键）
--- @param domain is a domain name to search runtime info -- domain是搜索runtime info信息的域名
--- @param ... now is diversion modulename and diversion data key -- 现在是分流模块名称和分流数据的关键
--- @return if returned, the return value always SUCCESS
_M.set = function(self, domain, policyGroupId, divsteps)
    local database = self.database --数据库对象
    local baseLibrary = self.baseLibrary  --键前缀  ab:runtimeInfo
    local prefix = baseLibrary .. ':' .. domain --键前缀  ab:runtimeInfo:${hostname}

    local policyGroup = policyGroupModule:new(database, policyGroupLib, policyLib):get(policyGroupId) --获得策略组
    local group = policyGroup.group

    --group的空校验
    if #group < 1 then
        error{ERRORINFO.PARAMETER_TYPE_ERROR, 'blank policyGroupId'}
    end

    --指定的分流层次存在出入
    if divsteps and divsteps > #group then  
        error{ERRORINFO.PARAMETER_TYPE_ERROR, 'divsteps is deeper than policyGroupID'}
    end

    if not divsteps then divsteps = #group end

    --遍历处理
    for i = 1, divsteps do
        local idx = indices[i]
        local policyId = group[i]

        local policy = policyModule:new(database, policyLib):get(policyId) --获得策略

        local divtype = policy.divtype --策略类型
        local divdata = policy.divdata --策略内容
        if divtype == ngx.null or divdata == ngx.null then
            error{ERRORINFO.POLICY_BLANK_ERROR, 'policy NO.'..policyId}
        end

        --构建三要素
        local divModulename     = table.concat({'abtesting.diversion', divtype}, '.') --策略模块名
        local divDataKey        = table.concat({policyLib, policyId, fields.divdata}, ':') --内容键前缀
        local userInfoModulename= table.concat({'abtesting.userinfo', divtypes[divtype]}, '.') --用户模块名

        runtimeModule:new(database, prefix):set(idx, divModulename, divDataKey, userInfoModulename) --键前缀  ab:runtimeInfo:${hostname}
    end

    --设置分流等级，n级分流
    local divStep = prefix ..':'.. fields.divsteps --键前缀  ab:runtimeInfo:${hostname}:divsteps
    database:set(divStep, divsteps)

    return ERRORINFO.SUCCESS
end

---
--- get runtime info(diversion modulename and diversion metadata key)
--- @param domain is a domain name to search runtime info
--- @return a table of diversion modulename and diversion metadata key
_M.get = function(self, domain)
    local database = self.database
    local baseLibrary = self.baseLibrary
    local prefix = baseLibrary .. ':' .. domain --键前缀：  ab:runtimeInfo:${hostname}

    local ret = {}

    local divStep = prefix .. ':' .. fields.divsteps --键前缀：  ab:runtimeInfo:${hostname}:divsteps
    local ok, err = database:get(divStep)
    if not ok then error{ERRORINFO.REDIS_ERROR, err} end

    local divsteps = tonumber(ok)
    if not divsteps then
        ret.divsteps = 0
        ret.runtimegroup = {}
        return ret
    end

    local runtimeGroup = {}
    -- 构建三要素
    for i = 1, divsteps do
        local idx = indices[i]
        local runtimeMod    =  runtimeModule:new(database, prefix)
        local runtimeInfo   =  runtimeMod:get(idx)
        local rtInfo   = {}
        rtInfo[fields.divModulename]      = runtimeInfo[1]
        rtInfo[fields.divDataKey]         = runtimeInfo[2]
        rtInfo[fields.userInfoModulename] = runtimeInfo[3]

        runtimeGroup[idx] = rtInfo
    end

    -- 构建runtimeInfo
    ret.divsteps = divsteps
    ret.runtimegroup = runtimeGroup
    return ret

end

---
--- delete runtime info(diversion modulename and diversion metadata key)
--- @param domain a domain of delete
--- @return if returned, the return value always SUCCESS
_M.del = function(self, domain)
    local database = self.database
    local baseLibrary = self.baseLibrary
    local prefix = baseLibrary .. ':' .. domain

    local divStep = prefix .. ':' .. fields.divsteps
    local ok, err = database:get(divStep)
    if not ok then error{ERRORINFO.REDIS_ERROR, err} end

    local divsteps = tonumber(ok)
    if not divsteps or divsteps == ngx.null or divsteps == null then
        local ok, err = database:del(divStep)
        if not ok then error{ERRORINFO.REDIS_ERROR, err} end
        return nil
    end

    for i = 1, divsteps do
        local idx = indices[i]
        local runtimeMod =  runtimeModule:new(database, prefix)
        local ok, err = runtimeMod:del(idx)
        if not ok then error{ERRORINFO.REDIS_ERROR, err} end
    end

    local ok, err = database:del(divStep)
    if not ok then error{ERRORINFO.REDIS_ERROR, err} end
end

return _M
