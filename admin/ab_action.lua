--- 多级分流管理端入口
local redisModule   = require('abtesting.utils.redis')
local systemConf    = require('abtesting.utils.init')
local utils         = require('abtesting.utils.utils')
local log			= require('abtesting.utils.log')
local ERRORINFO     = require('abtesting.error.errcode').info
--管理核心模块: 策略相关，运行相关，策略组相关
local policy        = require("admin.policy")
local runtime       = require('admin.runtime')
local policygroup   = require("admin.policygroup")

local ab_action = {}

--[动作指令，策略相关]--
ab_action.policy_check  = policy.check
ab_action.policy_set    = policy.set
ab_action.policy_get    = policy.get
ab_action.policy_del    = policy.del

--[动作指令，运行相关]--
ab_action.runtime_set   = runtime.set
ab_action.runtime_del   = runtime.del
ab_action.runtime_get   = runtime.get

--[动作指令，策略组相关]--
ab_action.policygroup_check  = policygroup.check
ab_action.policygroup_set    = policygroup.set
ab_action.policygroup_get    = policygroup.get
ab_action.policygroup_del    = policygroup.del

--[[连接redis]]--
local red = redisModule:new(systemConf.redisConf)
local ok, err = red:connectdb()
if not ok then
    -- redis连接error
    log:errlog(utils.dolog(ERRORINFO.REDIS_CONNECT_ERROR, err))
    ngx.say(utils.doresp(ERRORINFO.REDIS_CONNECT_ERROR, err))
    return
end

--[[管理平台逻辑解析]]--
local args = ngx.req.get_uri_args()
if args then
    --参数action字段，动作的指令
    local action = args.action
    local do_action = ab_action[action]
    if do_action then
        do_action({['db']=red})
    else
        --action uri不符合，不存在相关的操作
        log:errlog(utils.dolog(ERRORINFO.DOACTION_ERROR, action))
        ngx.say(utils.doresp(ERRORINFO.DOACTION_ERROR, action))
    end
else
    --http没有相关的action uri
    log:errlog(utils.dolog(ERRORINFO.ACTION_BLANK_ERROR, 'user req'))
    ngx.say(utils.doresp(ERRORINFO.ACTION_BLANK_ERROR, 'user req'))
end
