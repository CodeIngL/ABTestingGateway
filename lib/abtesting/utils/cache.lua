local modulename = "abtestingCache"
--[[
缓存模块
 进程一级缓存概念
]]--
local _M = {}
_M._VERSION = '0.0.1'

local ERRORINFO     = require('abtesting.error.errcode').info
local systemConf    = require('abtesting.utils.init')

local runtimeLib    = systemConf.prefixConf.runtimeInfoPrefix

local indices       = systemConf.indices
local fields        = systemConf.fields

local divConf       = systemConf.divConf
local shdict_expire = divConf.shdict_expire or 60

_M.new = function(self, sharedDict)
    if not sharedDict then
        error{ERRORINFO.ARG_BLANK_ERROR, 'cache name valid from nginx.conf'}
    end

    self.cache = ngx.shared[sharedDict]
    if not self.cache then
        error{ERRORINFO.PARAMETER_ERROR, 'cache name [' .. sharedDict .. '] valid from nginx.conf'}
    end

    return setmetatable(self, { __index = _M } )
end

--- 判空
--- @param v
--- @return true or false
local isNULL = function(v)
    return not v or v == ngx.null
end

--- 多判空: 任何一个参数为空，返回true，否则false
--- @param v1
--- @param v1
--- @param v2
--- @return true or false
local areNULL = function(v1, v2, v3)
    if isNULL(v1) or isNULL(v2) or isNULL(v3) then
        return true
    end
    return false 
end

--- 获得指定的hostname下的分级层次
--- @param hostname
--- @return number
_M.getSteps = function(self, hostname)
    local cache = self.cache
    local k_divsteps    = runtimeLib..':'..hostname..':'..fields.divsteps --键:  ab:runtimeInfo:${hostname}:divsteps
    local divsteps      = cache:get(k_divsteps)
    return tonumber(divsteps)
end

--- 获得指定的hostname下的获得runtimeInfo
--- @param hostname
--- @param divsteps 分流层级
--- @return table {true,runtimeInfo}
_M.getRuntime = function(self, hostname, divsteps)
    local cache = self.cache
    local runtimegroup = {}
    local prefix = runtimeLib .. ':' .. hostname --前缀:  ab:runtimeInfo:${hostname}
    --缓存三要素 --
    for i = 1, divsteps do
        local idx = indices[i]
        local k_divModname      = prefix .. ':'..idx..':'..fields.divModulename --键:  ab:runtimeInfo:${hostname}:${idx}:divModulename
        local k_divDataKey      = prefix .. ':'..idx..':'..fields.divDataKey --键:  ab:runtimeInfo:${hostname}:${idx}:divDataKey
        local k_userInfoModname = prefix .. ':'..idx..':'..fields.userInfoModulename --键:  ab:runtimeInfo:${hostname}:${idx}:userInfoModulename

        -- 获得缓存中对应的值 --
        local divMod, err1        = cache:get(k_divModname)
        local divPolicy, err2     = cache:get(k_divDataKey)
        local userInfoMod, err3   = cache:get(k_userInfoModname)

        -- 校验: 三要素都必须存在 --
        if areNULL(divMod, divPolicy, userInfoMod) then
            return false
        end

        -- 构建runtime组信息，三要素组成 --
        local runtime = {}
        runtime[fields.divModulename  ] = divMod
        runtime[fields.divDataKey     ] = divPolicy
        runtime[fields.userInfoModulename] = userInfoMod
        runtimegroup[idx] = runtime
    end

    -- 返回 --
    return true, runtimegroup

end

--- 设置缓存指定下的hostname下runtimeInfo
--- @param hostname
--- @param divsteps 分流层级
--- @param runtimegroup 运行组信息，多个runtimeInfo
--- @return true or false
_M.setRuntime = function(self, hostname, divsteps, runtimegroup)
    local cache = self.cache
    local prefix = runtimeLib .. ':' .. hostname --前缀:  ab:runtimeInfo:${hostname}
    local expire = shdict_expire -- 缓存过期时间

    for i = 1, divsteps do
        local idx = indices[i]

        local k_divModname      = prefix .. ':'..idx..':'..fields.divModulename --键:  ab:runtimeInfo:${hostname}:${idx}:divModulename
        local k_divDataKey      = prefix .. ':'..idx..':'..fields.divDataKey --键:  ab:runtimeInfo:${hostname}:${idx}:divDataKey
        local k_userInfoModname = prefix .. ':'..idx..':'..fields.userInfoModulename --键:  ab:runtimeInfo:${hostname}:${idx}:userInfoModulename

        -- 设置runtimeInfo缓存
        local runtime = runtimegroup[idx]
        local ok1, err = cache:set(k_divModname, runtime[fields.divModulename], expire)
        local ok2, err = cache:set(k_divDataKey, runtime[fields.divDataKey], expire)
        local ok3, err = cache:set(k_userInfoModname, runtime[fields.userInfoModulename], expire)
        if areNULL(ok1, ok2, ok3) then return false end
    end

    -- 设置分级层次缓存
    local k_divsteps = prefix ..':'..fields.divsteps --键:  ab:runtimeInfo:${hostname}:divsteps
    local ok, err = cache:set(k_divsteps, divsteps, shdict_expire)
    if not ok then return false end
    return true
end


--- 获得用户对应的Upstream信息
--- @param divsteps 分流层级
--- @param usertable 用户信息
--- @return table upstable
_M.getUpstream = function(self, divsteps, usertable)
    local upstable = {}
    local cache = self.cache
    for i = 1, divsteps do
        local idx   = indices[i]
        local info  = usertable[idx]
        -- ups will be an actually value or nil -- ups有值或者是nil
        if info then
            local ups   = cache:get(info) -- 从我们的一级缓存中获取相关的upstream信息
            upstable[idx] = ups
        end
    end
    return upstable
end

--- 设置upstream信息
--- @param info  用户信息
--- @param upstream 对应的upstream
_M.setUpstream = function(self, info, upstream)
    local cache  = self.cache
    local expire = shdict_expire
    cache:set(info, upstream, expire)
end

return _M
