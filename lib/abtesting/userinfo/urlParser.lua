--[[
	基于uri来表征用户
]]--
local _M = {
    _VERSION = '0.01'
}
_M.get = function()
	local u = ngx.var.uri
	return u
end
return _M
