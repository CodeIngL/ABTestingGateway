--- 多级分流入口
local runtimeModule = require('abtesting.adapter.runtimegroup')
local redisModule   = require('abtesting.utils.redis')
local systemConf    = require('abtesting.utils.init')
local utils         = require('abtesting.utils.utils')
local logmod	   	= require("abtesting.utils.log")
local cache         = require('abtesting.utils.cache')
local handler	    = require('abtesting.error.handler').handler
local ERRORINFO	    = require('abtesting.error.errcode').info
local cjson         = require('cjson.safe')
local semaphore     = require("abtesting.utils.sema")

local redisConf	     = systemConf.redisConf
local indices       = systemConf.indices
local fields        = systemConf.fields
local runtimeLib    = systemConf.prefixConf.runtimeInfoPrefix
--前缀的信息
local redirectInfo  = 'proxypass to upstream http://'

local sema          = semaphore.sema
local upsSema       = semaphore.upsSema

local upstream      = nil

--[[
    获得rewrite结果
]]--
local getRewriteInfo = function()
    return redirectInfo..ngx.var.backend
end

local doredirect = function(info) 
    return utils.dolog(ERRORINFO.SUCCESS, redirectInfo..ngx.var.backend, info)
end

local setKeepalive = function(red)
    local ok, err = red:keepalivedb()
    if ok then return end
    utils.dolog(ERRORINFO.REDIS_KEEPALIVE_ERROR, err)
end

--[[获得用户的host]]--
local getHost = function()
    local host = ngx.req.get_headers()['Host']
    if not host then return nil end
    local hostkey = ngx.var.hostkey
    if hostkey then
        return hostkey
    else
        return host --location 中不配置hostkey时
    end
end

--[[获得Runtime信息]]--
local getRuntime = function(database, hostname)
    return runtimeModule:new(database, runtimeLib):get(hostname) -- 键前缀: ab:runtimeInfo:${hostname}
end

--[[获得用户策略信息]]--
local getUserInfo = function(runtime)
    local userInfoModname = runtime[fields.userInfoModulename] --得到模块名
    local userInfoMod     = require(userInfoModname) -- 加载
    return userInfoMod:get()
end

--[[获得upstream策略信息]]--
local getUpstream = function(runtime, database, userInfo)
    local divModname = runtime[fields.divModulename] -- 得到模块名
    local policy     = runtime[fields.divDataKey] -- 得到策略
    local divMod     = require(divModname) -- 加载
    return divMod:new(database, policy):getUpstream(userInfo)
end

--[[连接redis数据库]]--
local connectdb = function(red, redisConf)
    if not red then
        red = redisModule:new(redisConf)
    end
    local ok, err = red:connectdb()
    if ok then return ok, red end
    utils.dolog(ERRORINFO.REDIS_CONNECT_ERROR, err)
    return false, err
end

-- host内容
local hostname = getHost()
-- host不存在直接返回
if not hostname then
    logmod.errlog(utils.dolog(ERRORINFO.ARG_BLANK_ERROR, 'cannot get [Host] from req headers', getRewriteInfo()))
    return nil
end

-- 日志对象
local log = logmod:new(hostname)

-- redis实例
local red = redisModule:new(redisConf)


-- getRuntimeInfo from cache or db
-- 来自缓存或db的getRuntimeInfo
local pfunc = function()
    --[[获得缓存的信息:runtimeInfo]]
    local runtimeCache  = cache:new(ngx.var.sysConfig)

    --step 1: read frome cache, but error 从缓存中读取 --读取开关
    local divsteps = runtimeCache:getSteps(hostname)
    if not divsteps then
        -- continue, then fetch from db -- 不存在 需要从redis中读取
    elseif divsteps < 1 then
        -- divsteps = 0, div switch off, goto default upstream -- divsteps = 0，div 关闭，转到默认upstream
        return false, 'divsteps < 1, div switchoff'
    else
     -- divsteps fetched from cache, then get Runtime From Cache -- 从缓存中获取到了divsteps，然后从缓存中获取RuntimeInfo组
        local ok, runtimegroup = runtimeCache:getRuntime(hostname, divsteps)
        if ok then
            return true, divsteps, runtimegroup
        -- else fetch from db
        end
    end

    --step 2: acquire the lock 获得锁
    local sem, err = sema:wait(0.01)
    if not sem then
        -- lock failed acquired
        -- but go on. This action just sets a fence -- 锁定失败，但继续。 这个动作只是设置了一个围栏
    end

    -- setp 3: read from cache again  -- 再次从缓存中读取
    local divsteps = runtimeCache:getSteps(hostname)
    if not divsteps then
        -- continue, then fetch from db -- 不存在 需要从redis中读取
    elseif divsteps < 1 then
        -- divsteps = 0, div switch off, goto default upstream -- divsteps = 0，div 关闭，转到默认upstream
        if sem then sema:post(1) end
        return false, 'divsteps < 1, div switchoff'
    else
     -- divsteps fetched from cache, then get Runtime From Cache -- 从缓存中获取到了divsteps，然后从缓存中获取RuntimeInfo组
        local ok, runtimegroup = runtimeCache:getRuntime(hostname, divsteps)
        if ok then
            if sem then sema:post(1) end
            return true, divsteps, runtimegroup
        -- else fetch from db
        end
    end

    -- step 4: fetch from redis -- 缓存中没有,我们从二级缓存也就是我们的redis中获取
    local ok, db = connectdb(red, redisConf)
    if not ok then
        if sem then sema:post(1) end
		return ok, db
    end

    -- 通过redis获取我们的相关的runtimeInfo信息（获取相关的信息)
    local database      = db.redis
    local runtimeInfo   = getRuntime(database, hostname)

    local divsteps		= runtimeInfo.divsteps
    local runtimegroup	= runtimeInfo.runtimegroup

    -- 设置到一级缓存中
    runtimeCache:setRuntime(hostname, divsteps, runtimegroup)
    if red then setKeepalive(red) end

    if sem then sema:post(1) end
    return true, divsteps, runtimegroup
end

--[[执行处理runtime信息]]--
local ok, status, steps, runtimeInfo = xpcall(pfunc, handler)
if not ok then
    -- execute error, the type of status is table now
    log:errlog("getruntime\t", "error\t")
    return utils.doerror(status, getRewriteInfo())
else
	local info = 'getRuntimeInfo error: '
	if not status or not steps or steps < 1 then
		if not status then
			local reason = steps
			if reason then
				info = info .. reason
			end
		elseif not steps then
			info = info .. 'no divsteps, div switch OFF'
		elseif steps < 1 then
			info = info .. 'divsteps < 1, div switch OFF'
		end
		return log:info(doredirect(info))
	else
		log:debug('divstep = ', steps,
					'\truntimeinfo = ', cjson.encode(runtimeInfo))
	end
end

-- 开关以及分流层级
local divsteps      = steps
-- 运行策略组
local runtimegroup  = runtimeInfo

-- 来自缓存或db的userInfo
local pfunc = function()
    --[[获得缓存的信息:upstream]]--
    local upstreamCache = cache:new(ngx.var.kv_upstream)

    --[[构建用户模块，获得用户的策略：基于city，基于ip，基于uid，基于url]]--
    local usertable = {}
    for i = 1, divsteps do
        local idx = indices[i]
        local runtime = runtimegroup[idx]
        local info = getUserInfo(runtime)

        if info and info ~= '' then
            usertable[idx] = info
        end
    end

	log:errlog('userinfo\t', cjson.encode(usertable))

    --step 1: read frome cache, but error 从缓存中读取 --读取upstream信息
    local upstable = upstreamCache:getUpstream(divsteps, usertable)
	log:debug('first fetch: upstable in cache\t', cjson.encode(upstable))
    -- 遍历upstream的table 缓存中可能有值，或者可能是nil
    for i = 1, divsteps do
        local idx = indices[i]
        local ups = upstable[idx]
        if ups == -1 then
			if i == divsteps then
				local info = "usertable has no upstream in cache 1, proxypass to default upstream"
				log:info(info)
				return nil, info
			end
            -- continue
        elseif ups == nil then
			-- why to break
			-- the reason is that maybe some userinfo is empty
			-- 举例子,用户请求
			-- location/div -H 'X-Log-Uid:39' -H 'X-Real-IP:192.168.1.1'
			-- 分流后缓存中 39->-1, 192.168.1.1-> beta2
			-- 下一请求：
			-- location/div?city=BJ -H 'X-Log-Uid:39' -H 'X-Real-IP:192.168.1.1'
			-- 该请求应该是  39-> -1, BJ->beta1, 192.168.1.1->beta2，
			-- 然而cache中是 39->-1, 192.168.1.1->beta2，
			-- 如果此分支不break的话，将会分流到beta2上，这是错误的。

            break
        else
			local info = "get upstream ["..ups.."] according to ["..idx.."] userinfo ["..usertable[idx].."] in cache 1"
			log:info(info)
            return ups, info
        end
    end

    --step 2: acquire the lock 获得锁
    local sem, err = upsSema:wait(0.01)
    if not sem then
        -- lock failed acquired
        -- but go on. This action just set a fence for all but this request -- 锁定失败，但继续。 这个动作只是设置了一个围栏
    end

    -- setp 3: read from cache again -- 再次从缓存中读取
    local upstable = upstreamCache:getUpstream(divsteps, usertable)
	log:debug('second fetch: upstable in cache\t', cjson.encode(upstable))
    for i = 1, divsteps do
        local idx = indices[i]
        local ups = upstable[idx]
        if ups == -1 then
            -- continue
			if i == divsteps then
				local info = "usertable has no upstream in cache 2, proxypass to default upstream"
				return nil, info
			end

        elseif ups == nil then
			-- do not break, may be the next one will be okay  -- 不用break，可能是下一个会okay
             break
        else
            if sem then upsSema:post(1) end
			local info = "get upstream ["..ups.."] according to ["..idx.."] userinfo ["..usertable[idx].."] in cache 2"
            return ups, info
        end
    end

    -- step 4: fetch from redis -- 缓存中没有,我们从二级缓存也就是我们的redis中获取
    local ok, db = connectdb(red, redisConf)
    if not ok then
        if sem then upsSema:post(1) end
		return nil, db
    end
    local database = db.redis

    for i = 1, divsteps do
        local idx = indices[i]
        local runtime = runtimegroup[idx]
        local info = usertable[idx]

        if info then
            local upstream = getUpstream(runtime, database, info)
            if not upstream then -- 不存在，我们使用设置特殊的值进行设置，设置为-1
                upstreamCache:setUpstream(info, -1)
				log:debug('fetch userinfo [', info, '] from db, get [nil]')
            else
                -- 存在我们设置到缓存中去
                if sem then upsSema:post(1) end
                if red then setKeepalive(red) end

                upstreamCache:setUpstream(info, upstream)
				log:debug('fetch userinfo [', info, '] from db, get [', upstream, ']')

				local info = "get upstream ["..upstream.."] according to ["..idx.."] userinfo ["..usertable[idx].."] in db"
                return upstream, info
            end
        end
    end

    if sem then upsSema:post(1) end
    if red then setKeepalive(red) end
    return nil, 'the req has no target upstream'
end


--[[执行获得upstream信息]]--
local status, info, desc = xpcall(pfunc, handler)
if not status then
    utils.doerror(info)
else
    upstream = info
end

--[[存在upstrem,进行替换]]--
if upstream then
    ngx.var.backend = upstream
end

local info = doredirect(desc)
log:errlog(info)
