---
--- Generated by EmmyLua(https://github.com/EmmyLua)
--- Created by laihj.
--- DateTime: 2019/3/5 17:22
---
--[[
	基于版本的表征用户
]]--
local _M = {
    _VERSION = '0.01'
}

---
--- 从请求头部中获取，这个不是稳定的。
--- @return string or nil
_M.get = function()
    return ngx.req.get_headers()["X-Version"]
end
return _M