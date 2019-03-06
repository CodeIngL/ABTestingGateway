---
--- @classmod abtesting.adapter.policy
--- @release 0.0.1
local modulename = "abtestingAdapterPolicy"

local _M = { _VERSION = "0.0.1" }
local mt = { __index = _M }

local ERRORINFO = require('abtesting.error.errcode').info
local fields    = require('abtesting.utils.init').fields

local separator = ':'

---
---  策略对象，向下构建对不同策略的封装
--- policyIO new function
--- @param database opened redis.
--- @param baseLibrary a library(prefix of redis key) of policies.
--- @return runtimeInfoIO object
_M.new = function(self, database, baseLibrary)
    if not database then
        error{ERRORINFO.PARAMETER_NONE, 'need avaliable redis db'}
    end
    if not baseLibrary then
        error{ERRORINFO.PARAMETER_NONE, 'need avaliable policy baselib'}
    end
    
    self.database     = database -- 数据库对象
    self.baseLibrary  = baseLibrary -- 键前缀 ab:policies
    self.idCountKey = table.concat({baseLibrary, fields.idCount}, separator) --id索引键 ab:policies:idCount
    
    local ok, err = database:exists(self.idCountKey)
    if not ok then error{ERRORINFO.REDIS_ERROR,  err} end
    
    if 0 == ok then
        local ok, err = database:set(self.idCountKey, '-1')
        if not ok then error{ERRORINFO.REDIS_ERROR, err} end
    end
    return setmetatable(self, mt)
end

---
--- get id for current policy
--- 获取当前策略的ID，通过对redis键值加获得下一个seq
--- @return the id
_M.getIdCount = function(self)
    local database = self.database
    local key = self.idCountKey --id索引键 ab:policies:idCount
    local idCount, err = database:incr(key)
    if not idCount then error{ERRORINFO.REDIS_ERROR, err} end
    
    return idCount
end

---
--- private function, set diversion type
--- @param id identify a policy
--- @param divtype diversion type (ipange/uid/...)
--- @return allways returned SUCCESS
_M._setDivtype = function(self, id, divtype)
    local database = self.database
    local key = table.concat({self.baseLibrary, id, fields.divtype}, separator) --前缀：ab:policies:${id}:divtype
    local ok, err = database:set(key, divtype)
    if not ok then error{ERRORINFO.REDIS_ERROR, err} end
end

---
--- private function, set diversion data
--- @param id identify a policy
--- @param divdata diversion data
--- @param modulename module name of diversion data (decision by diversion type)
--- @return allways returned SUCCESS
_M._setDivdata = function(self, id, divdata, modulename)
    local divModule = require(modulename)
    local key = table.concat({self.baseLibrary, id, fields.divdata}, separator) --前缀：ab:policies:${id}:divdata
    divModule:new(self.database, key):set(divdata)
end

---
--- addtion a policy to specified redis lib
--- 为指定的redis lib添加策略
--- first: 获得seq，seq的key为
--- next: 向redis中写入key为ab:policies:${id}:divtype，value为${policy.divtype}
--- last: 使用${divModulename},构建出对于的分类模块，调用模块进行处理相关的数据key为ab:policies:${id}:divdata，value为${policy.divdata}的数据
--- @param policy policy of addtion
--- @return allways returned SUCCESS
_M.set = function(self, policy)
    local id = self:getIdCount()
    local divModulename = table.concat({'abtesting.diversion', policy.divtype}, '.') --模块名：abtesting.diversion.${divtype}

    self:_setDivtype(id, policy.divtype)
    self:_setDivdata(id, policy.divdata, divModulename)
    
    return id
end

---
--- 根据策略数据定位相应的策略模块进行检查
--- @param policy 策略数据
--- @return allways returned SUCCESS
_M.check = function(self, policy)
    local divModulename = table.concat({'abtesting.diversion', policy.divtype}, '.') --模块名：abtesting.diversion.${divtype}
    local divModule = require(divModulename)
    return divModule:new(self.database, ''):check(policy.divdata)
end

---
--- delete a policy from specified redis lib
--- @param id the policy identify
--- @return allways returned SUCCESS
_M.del = function(self, id)
    local database      = self.database

    local keys, err = database:keys(self.baseLibrary..':'..id..':*')
    if not keys then
        error{ERRORINFO.REDIS_ERROR, err}
    end

    database:init_pipeline()
    for _i, key in pairs(keys) do
        database:del(key)
    end
    local ok, err = database:commit_pipeline()
    if not ok then error{ERRORINFO.REDIS_ERROR, err} end
	
end

_M.get = function(self, id)
    local divTypeKey    = table.concat({self.baseLibrary, id, fields.divtype}, separator)
    local divDataKey    = table.concat({self.baseLibrary, id, fields.divdata}, separator)
    local database      = self.database
    local policy        = {}
    policy.divtype      = ngx.null
    policy.divdata      = ngx.null

    local divtype, err  = database:get(divTypeKey)
    if not divtype then
        error{ERRORINFO.REDIS_ERROR, err} 
    elseif divtype == ngx.null then
        return policy
    end

    local divModulename = table.concat({'abtesting.diversion', divtype}, '.') --模块名：abtesting.diversion.${divtype}
    local divdata       = require(divModulename):new(database, divDataKey):get()
    policy.divtype      = divtype
    policy.divdata      = divdata
    return policy
end

return _M
