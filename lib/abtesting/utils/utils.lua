local modulename = "abtestingUtils"
--[[
    实用的字符串操作
]]--
local _M = {}
_M._VERSION = '0.0.1'

local cjson = require('cjson.safe')
local log	= require("abtesting.utils.log")
--将doresp和dolog，与handler统一起来。
--handler将返回一个table，结构为：
--[[
handler———errinfo————errcode————code
    |           |               |
    |           |               |————info
    |           |
    |           |————errdesc
    |
    |
    |
    |———errstack				 
]]--		

--- 构建日志信息
--- @return string
_M.dolog = function(info, desc, data, errstack)
    local errlog = ''
    local code, err = info[1], info[2]
    local errcode = code
    local errinfo = desc and err..desc or err 
    
    if data then
        return errlog..'code : '..errcode..', desc : '..errinfo..', extrainfo : '..data
    end
    if errstack then
        return errlog..'code : '..errcode..', desc : '..errinfo..', errstack : '..errstack
    end
	return errlog
end

--- 构建响应信息
--- @return string
_M.doresp = function(info, desc, data)
    local response = {}
    
    local code = info[1]
    local err  = info[2]
    response.code = code
    response.desc = desc and err..desc or err 
    if data then 
        response.data = data 
    end
    return cjson.encode(response)
end


--- 构建错误响应信息，记入日志
--- @return string 响应信息
_M.doerror = function(info, extrainfo)
    local errinfo   = info[1]
    local errstack  = info[2] 
    local err, desc = errinfo[1], errinfo[2]

    local dolog, doresp = _M.dolog, _M.doresp
    local errlog = dolog(err, desc, extrainfo, errstack)
	log:errlog(errlog)

    local response  = doresp(err, desc)
    return response
end

return _M
