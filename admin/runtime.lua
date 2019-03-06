---
-- @classmod abtesting.adapter.policy
-- @release 0.0.1
local modulename = "abtestingAdminRuntime"
--[动作指令，运行相关]--
local _M = { _VERSION = "0.0.1" }
local mt = { __index = _M }

local ERRORINFO	= require('abtesting.error.errcode').info

local runtimeModule = require('abtesting.adapter.runtime')
local policyModule  = require('abtesting.adapter.policy')
local systemConf    = require('abtesting.utils.init')
local handler       = require('abtesting.error.handler').handler
local utils         = require('abtesting.utils.utils')
local log			= require('abtesting.utils.log')

local runtimeLib    = systemConf.prefixConf.runtimeInfoPrefix
local policyLib     = systemConf.prefixConf.policyLibPrefix
local divtypes      = systemConf.divtypes
local fields        = systemConf.fields

local runtimeGroupModule = require('abtesting.adapter.runtimegroup')


local doresp        = utils.doresp
local dolog         = utils.dolog
local doerror       = utils.doerror

local getPolicyId = function()
    return tonumber(ngx.var.arg_policyid)
end

local getPolicyGroupId = function()
    return tonumber(ngx.var.arg_policygroupid)
end

local getHostName = function()
    return ngx.var.arg_hostname
end

local getDivSteps = function()
    return tonumber(ngx.var.arg_divsteps)
end

_M.get = function(option)
    local db = option.db
    local database = db.redis

    local hostname = getHostName()
    if not hostname or string.len(hostname) < 1 or hostname == ngx.null then
        log:errlog(dolog(ERRORINFO.PARAMETER_TYPE_ERROR , 'arg hostname invalid: '))
        ngx.say(doresp(ERRORINFO.PARAMETER_TYPE_ERROR , 'arg hostname invalid: '))
        return nil 
    end

    local pfunc = function()
        local runtimeGroupMod = runtimeGroupModule:new(database, runtimeLib)
        return runtimeGroupMod:get(hostname)
    end
    local status, info = xpcall(pfunc, handler)
    if not status then
        local response = doerror(info)
        ngx.say(response)
        return false
    end

    local response = doresp(ERRORINFO.SUCCESS, nil, info)
    ngx.say(response)
    return true
end

_M.del = function(option)
    local db = option.db
    local database = db.redis

    local hostname = getHostName()
    if not hostname or string.len(hostname) < 1 or hostname == ngx.null then
        log:errlog(dolog(ERRORINFO.PARAMETER_TYPE_ERROR , 'arg hostname invalid: '))
        ngx.say(doresp(ERRORINFO.PARAMETER_TYPE_ERROR , 'arg hostname invalid: '))
        return nil 
    end

    local pfunc = function()
        local runtimeGroupMod = runtimeGroupModule:new(database, runtimeLib)
        return runtimeGroupMod:del(hostname)
    end
    local status, info = xpcall(pfunc, handler)
    if not status then
        ngx.say(doerror(info))
        return false
    end
    ngx.say(doresp(ERRORINFO.SUCCESS))
    return true
end

--- 根据请求提供的运行数据，设置新的运行时信息
--- 可以使用策略id，也可以使用策略组id
--- 策略id优先
--- 策略id对应runtime，策略组id对应runtimegroup
--- @return true or false
_M.set = function(option)
    --- 提取策略id
    local policyId = getPolicyId()
    --- 提取策略组id
    local policyGroupId = getPolicyGroupId()

    if policyId and policyId >= 0 then
        _M.runtimeset(option, policyId)
    elseif policyGroupId and policyGroupId >= 0 then
        _M.groupset(option, policyGroupId)
    else
        log:errlog(dolog(ERRORINFO.PARAMETER_TYPE_ERROR , 'policyId or policyGroupid invalid'))
        ngx.say(doresp(ERRORINFO.PARAMETER_TYPE_ERROR , 'policyId or policyGroupid invalid'))
        return nil 
    end
end


--- 根据策略组id进行设置相关信息
--- @return true or false
_M.groupset = function(option, policyGroupId)
    local db = option.db
    local database = db.redis

    local hostname = getHostName() --host参数
    local divsteps = getDivSteps() --分级层次

    --校验hostname
    if not hostname or string.len(hostname) < 1 or hostname == ngx.null then
        log:errlog(dolog(ERRORINFO.PARAMETER_TYPE_ERROR , 'arg hostname invalid: '))
        ngx.say(doresp(ERRORINFO.PARAMETER_TYPE_ERROR , 'arg hostname invalid: '))
        return nil 
    end

    --应用策略后，先尝试删除hostname下的相关的策略组策略，并直接更新的的策略组策略
    local pfunc = function()
        local runtimeGroupMod = runtimeGroupModule:new(database, runtimeLib)
        runtimeGroupMod:del(hostname) --键前缀  ab:runtimeInfo:${hostname}
        return runtimeGroupMod:set(hostname, policyGroupId, divsteps)
    end
    local status, info = xpcall(pfunc, handler)
    if not status then
        ngx.say(doerror(info))
        return false
    end
    ngx.say(doresp(ERRORINFO.SUCCESS))
    return true

end


--- 根据策略id进行设置相关信息
--- @return true or false
_M.runtimeset = function(option, policyId)
    local db = option.db
    local database = db.redis

    local hostname = getHostName()

    --校验hostname
    if not hostname or string.len(hostname) < 1 or hostname == ngx.null then
        log:errlog(dolog(ERRORINFO.PARAMETER_TYPE_ERROR, 'arg hostname invalid: '))
        ngx.say(doresp(ERRORINFO.PARAMETER_TYPE_ERROR, 'arg hostname invalid: '))
        return nil
    end

    --应用策略后，先尝试删除hostname下的相关的策略组策略
    local pfunc = function()
        return runtimeGroupModule:new(database, runtimeLib):del(hostname) --键前缀  ab:runtimeInfo:${hostname}
    end
    local status, info = xpcall(pfunc, handler)
    if not status then
        ngx.say(doerror(info))
        return false
    end

    --获得内存中的策略信息
    local pfunc = function()
        local policy = policyModule:new(database, policyLib):get(policyId) --键前缀  ab:policies:${policyId}

        local divtype = policy.divtype --策略类型
        local divdata = policy.divdata --策略内容

        if divtype == ngx.null or divdata == ngx.null then
            error{ERRORINFO.POLICY_BLANK_ERROR, 'policy NO '..policyId}
        end

        local divModulename      = table.concat({'abtesting.diversion', divtype}, '.') --对应的策略模块名字
        local divDataKey         = table.concat({policyLib, policyId, fields.divdata}, ':') --对应的策略内容键
        local userInfoModulename = table.concat({'abtesting.userinfo', divtypes[divtype]}, '.') --对应的用户模块名字
        --为专属的hostname构建三要素，这个是单级分流，因为是单个策略
        runtimeModule:new(database, runtimeLib..':'..hostname):set(':first', divModulename, divDataKey, userInfoModulename) --键前缀  ab:runtimeInfo:${hostname}:first

        --设置分流等级，单级分流
        local divSteps           = runtimeLib..':'..hostname .. ':' .. fields.divsteps
        local ok, err = database:set(divSteps, 1)
        if not ok then error{ERRORINFO.REDIS_ERROR, err} end
    end

    -- 执行
    local status, info = xpcall(pfunc, handler)
    if not status then
        ngx.say(doerror(info))
        return false
    end

    ngx.say(doresp(ERRORINFO.SUCCESS))
    return true
end



return _M
