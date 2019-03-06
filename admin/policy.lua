---
-- @classmod abtesting.adapter.policy
-- @release 0.0.1
local modulename = "abtestingAdminPolicy"
--[动作指令，策略相关]--
local _M = { _VERSION = "0.0.1" }
local mt = { __index = _M }

local policyModule  = require('abtesting.adapter.policy')
local systemConf    = require('abtesting.utils.init')
local handler       = require('abtesting.error.handler').handler
local utils         = require('abtesting.utils.utils')
local log			= require('abtesting.utils.log')
local ERRORINFO     = require('abtesting.error.errcode').info

local cjson         = require('cjson.safe')
local doresp        = utils.doresp
local dolog         = utils.dolog
local doerror       = utils.doerror

local divtypes      = systemConf.divtypes
local policyLib     = systemConf.prefixConf.policyLibPrefix

--- 根据请求获得策略id
--- 读取nginx内置的变量
--- @return 策略id
local getPolicyId = function()
    local policyID = tonumber(ngx.var.arg_policyid)

    if not policyID or policyID < 0 then
        log:errlog(dolog(ERRORINFO.PARAMETER_TYPE_ERROR , 'policyID invalid'))
        ngx.say(doresp(ERRORINFO.PARAMETER_TYPE_ERROR , 'policyID invalid'))
        return nil 
    end
    return policyID
end

--- 根据请求获得策略数据
--- {"divtype": "分流类型","divdata": 分流数据}
--- @return 策略数据
local getPolicy = function()

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

    -- 分流类型
    local divtype = postData.divtype
    -- 分流内容数据
    local divdata = postData.divdata

    -- 数据格式合法性校验
    if not divtype or not divdata then
        log:errlog(dolog(ERRORINFO.PARAMETER_NONE , 'policy divtype or policy divdata'))
        ngx.say(doresp(ERRORINFO.PARAMETER_NONE , 'policy divtype or policy divdata'))
        return nil
    end

    -- 数据格式合法性校验，分流类型必须系统支持
    if not divtypes[divtype] then
        log:errlog(dolog(ERRORINFO.PARAMETER_TYPE_ERROR , 'unsupported divtype'))
        ngx.say(doresp(ERRORINFO.PARAMETER_TYPE_ERROR , 'unsupported divtype'))
        return nil
    end

    -- 策略数据
    return postData
end


--- 校验策略
--- @return true or false
_M.check = function(option)
    local db = option.db

    --获得请求中的策略数据对象
    local policy = getPolicy()
    if not policy then return false end

    --委托分流策略模块进行请求数据对应的策略进行校验
    local pfunc = function() 
        return policyModule:new(db.redis, policyLib):check(policy)
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
        log:errlog(dolog(err, desc))
        ngx.say(doresp(err, desc))
    else
        ngx.say(doresp(ERRORINFO.SUCCESS))
    end
    return true

end

--- 根据请求提供的策略数据，设置新的分流策略
--- {"divtype": "分流类型","divdata": 分流数据}
--- 成功输出策略id
--- @return true or false
_M.set = function(option)
    -- redis对象
    local db = option.db

    -- 获得当前请求会应用的策略
    local policy = getPolicy()
    if not policy then return false end

    -- 通过策略模块分析policy.divtype寻找对应的模块，检查policy.divdata的合法性
    local pfunc = function() 
        return policyModule:new(db.redis, policyLib):check(policy) --前缀键  ab:policies
    end

    local status, info = xpcall(pfunc, handler)
    if not status then
        ngx.say(doerror(info))
        return false
    end

    -- 合法性结果分析
    local chkout    = info
    local valid     = chkout[1]
    local err       = chkout[2]
    local desc      = chkout[3]

    if not valid then
        log:errlog(dolog(err, desc))
        ngx.say(doresp(err, desc))
        return false
    end

    -- 通过策略模块将policy设置进数据库中
    -- policy将得到一个数据库seq，
    local pfunc = function()
        return policyModule:new(db.redis, policyLib):set(policy) --前缀键  ab:policies
    end

    local status, info = xpcall(pfunc, handler)
    if not status then
        ngx.say(doerror(info))
        return false
    end
    local data
    if info then
        data = ' the id of new policy is '..info
    end

    ngx.say(doresp(ERRORINFO.SUCCESS, data))
    return true

end

--- 根据请求提供的策略数据，删除对应的分流策略
--- 关键的policyid参数
--- @return true or false
_M.del = function(option)
    local db = option.db

    local policyId = getPolicyId()
    if not policyId then return false end

    local pfunc = function()
        return policyModule:new(db.redis, policyLib):del(policyId)
    end

    local status, info = xpcall(pfunc, handler)
    if not status then
        local response = doerror(info)
        ngx.say(response)
        return false
    end
    ngx.say(doresp(ERRORINFO.SUCCESS))
    return true
end

--- 根据请求提供的策略数据，获得对应的分流策略
--- 关键的policyid参数
--- @return true or false
_M.get = function(option)
    local db = option.db

    local policyId = getPolicyId()
    if not policyId then return false end

    local pfunc = function()
        return policyModule:new(db.redis, policyLib) :get(policyId)
    end

    local status, info = xpcall(pfunc, handler)
    if not status then
        ngx.say(doerror(info))
        return false
    else
        log:errlog(dolog(ERRORINFO.SUCCESS, nil))
        ngx.say(doresp(ERRORINFO.SUCCESS, nil, info))
        return true
    end

end

return _M
