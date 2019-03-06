---
-- @classmod abtesting.adapter.policy
-- @release 0.0.1
local modulename = "abtestingAdminPolicyGroup"
--[动作指令，策略组相关]--
local _M = { _VERSION = "0.0.1" }
local mt = { __index = _M }

local ERRORINFO	= require('abtesting.error.errcode').info

local systemConf    = require('abtesting.utils.init')
local handler       = require('abtesting.error.handler').handler
local utils         = require('abtesting.utils.utils')
local log			= require('abtesting.utils.log')

local cjson         = require('cjson.safe')
local doresp        = utils.doresp
local dolog         = utils.dolog
local doerror       = utils.doerror

local divtypes      = systemConf.divtypes
local policyLib     = systemConf.prefixConf.policyLibPrefix

local policyGroupModule  = require('abtesting.adapter.policygroup')
local policyGroupLib     = systemConf.prefixConf.policyGroupPrefix

--- 根据请求获得策略组id
--- 读取nginx内置的变量
--- @return 策略id
local getPolicyGroupId = function()
    local policyGroupId      = tonumber(ngx.var.arg_policygroupid)
    if not policyGroupId or policyGroupId < 0 then
        log:errlog(dolog( ERRORINFO.PARAMETER_TYPE_ERROR, 'policyGroupId invalid'))
        ngx.say(doresp( ERRORINFO.PARAMETER_TYPE_ERROR, 'policyGroupId invalid'))
        return nil 
    end
    return policyGroupId
end

--- 根据请求获得策略组数据
--- {
---    "1": {
---        "divtype": "uidappoint",
---        "divdata": [
---            {"uidset": [1234,5124,653],"upstream": "beta1"},
---            {"uidset": [3214,652,145],"upstream": "beta2"}]},
---    "2": {
---        "divtype": "iprange",
---        "divdata": [{"range": {"start": 1111,"end": 2222},"upstream": "beta1"},
---            {"range": {"start": 3333,"end": 4444},"upstream": "beta2"},
---            {"range": {"start": 7777,"end": 8888},"upstream": "beta3"}]}
---}
--- @return 策略组数据
local getPolicyGroup = function()

    local request_body  = ngx.var.request_body
    local postData      = cjson.decode(request_body)

    -- 请求body的校验
    if not request_body then
        log:errlog(dolog(ERRORINFO.PARAMETER_NONE, 'request_body or post data'))
        ngx.say(doresp(ERRORINFO.PARAMETER_NONE, 'request_body or post data'))
        return nil
    end

    -- body的json校验
    if not postData then
        log:errlog(dolog(ERRORINFO.PARAMETER_ERROR , 'postData is not a json string'))
        ngx.say(doresp(ERRORINFO.PARAMETER_ERROR , 'postData is not a json string'))
        return nil
    end

    -- 策略组包含策略数量
    local policy_cnt = 0
    local policyGroup = {}
    for k, v in pairs(postData) do
        policy_cnt = policy_cnt + 1

        local idx = tonumber(k)
        if not idx or type(v) ~= 'table' then
            log:errlog(dolog(ERRORINFO.PARAMETER_ERROR, 'policyGroup error'))
            ngx.say(doresp(ERRORINFO.PARAMETER_ERROR, 'policyGroup error'))
            return nil
        end

        local policy = v
        local divtype = policy.divtype
        local divdata = policy.divdata

        -- 数据格式合法性校验
        if not divtype or not divdata then
            log:errlog(dolog(ERRORINFO.PARAMETER_NONE, 'policy divtype or policy divdata'))
            ngx.say(doresp(ERRORINFO.PARAMETER_NONE, 'policy divtype or policy divdata'))
            return nil
        end

        -- 数据格式合法性校验，分流类型必须系统支持
        if not divtypes[divtype] then
            log:errlog(dolog( ERRORINFO.PARAMETER_TYPE_ERROR , 'unsupported divtype'))
            ngx.say(doresp( ERRORINFO.PARAMETER_TYPE_ERROR , 'unsupported divtype'))
            return nil
        end

        if policyGroup[idx] then
            --不能混淆，优先级不能重复
            log:errlog(dolog(ERRORINFO.PARAMETER_TYPE_ERROR, 'policy in policy group should not overlap'))
            ngx.say(doresp(ERRORINFO.PARAMETER_TYPE_ERROR, 'policy in policy group should not overlap'))
            return nil
        end

        policyGroup[idx] = policy
    end

    -- 合法性校验
    if policy_cnt ~= #policyGroup then
        log:errlog(dolog(ERRORINFO.PARAMETER_TYPE_ERROR, 'index of policy in policy_group should be one by one'))
        ngx.say(doresp(ERRORINFO.PARAMETER_TYPE_ERROR, 'index of policy in policy_group should be one by one'))
        return nil
    end

    return policyGroup
end

--- 校验策略
--- @return true or false
local checkPolicy = function(option)
    local db = option.db

    --获得请求中的策略组数据对象
    local policyGroup = getPolicyGroup()
    if not policyGroup then
        return false
    end

    -- 策略组数据项校验，非空校验
    local steps = #policyGroup
    if steps < 1 then 
        log:errlog(dolog(ERRORINFO.PARAMETER_NONE, 'blank policy group'))
        ngx.say(doresp(ERRORINFO.PARAMETER_NONE, 'blank policy group'))
        return false
    end

    --委托分流策略组模块进行请求数据对应的策略进行校验
    local pfunc = function()
        return policyGroupModule:new(db.redis, policyGroupLib, policyLib):check(policyGroup)
    end
    local status, info = xpcall(pfunc, handler)
    if not status then
        ngx.say(doerror(info))
        return false
    end

    local chkout    = info
    local valid     = chkout[1]
    local err       = chkout[2]
    local desc      = chkout[3]

    if not valid then
        ngx.say(doresp(err, desc))
        log:errlog(dolog(err, desc))
        return false
    end

    return true
end

--- 校验策略
--- @return true or false
_M.check = function(option)
    local status = checkPolicy(option)
    if not status then return end
    ngx.say(doresp(ERRORINFO.SUCCESS))
    return true
end

--- 根据请求提供的策略组数据，设置新的分流策略
--- 成功界面上输出策略id和策略组id
--- @return true or false
_M.set = function(option)

    local status = checkPolicy(option)
    if not status then return end

    local db = option.db

    local policyGroup = getPolicyGroup()
    if not policyGroup then
        return false
    end

    local pfunc = function()
        local policyGroupMod = policyGroupModule:new(db.redis, policyGroupLib, policyLib)
        return policyGroupMod:set(policyGroup)
    end
    local status, info = xpcall(pfunc, handler)
    if not status then
        ngx.say(doerror(info))
        return false
    end

    ngx.say(doresp(ERRORINFO.SUCCESS, _, info))
    return true
end

--- 根据请求提供的策略数据，获得对应的分流策略
--- 关键的policyid参数和policygroupid参数
--- @return true or false
_M.get = function(option)
    local db = option.db

    local policyGroupId = getPolicyGroupId()
    if not policyGroupId then
        return false
    end

    local pfunc = function()
        local policyGroupMod = policyGroupModule:new(db.redis,
                                        policyGroupLib, policyLib)
        return policyGroupMod:get(policyGroupId)
    end
    local status, info = xpcall(pfunc, handler)
    if not status then
        ngx.say(doerror(info))
        return false
    end
    ngx.say(doresp(ERRORINFO.SUCCESS, _, info))
    return true
end

--- 根据请求提供的策略数据，删除对应的分流策略
--- 关键的policyid参数和policygroupid参数
--- @return true or false
_M.del = function(option)
    local db = option.db

    local policyGroupId = getPolicyGroupId()
    if not policyGroupId then
        return false
    end

    local pfunc = function()
        local policyGroupMod = policyGroupModule:new(db.redis, policyGroupLib, policyLib)
        return policyGroupMod:del(policyGroupId)
    end
    local status, info = xpcall(pfunc, handler)
    if not status then
        ngx.say(doerror(info))
        return false
    end
    ngx.say(doresp(ERRORINFO.SUCCESS))
    return true
end

return _M
