--[[
	基于请求参数包含的city字段的解析
]]--
local _M = {
    _VERSION = '0.01'
}
_M.get = function()
	local u = ngx.var.arg_city
	return u
end
return _M
