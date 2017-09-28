-- Copyright (C) 2016 Libo Huang (huangnauh), UPYUN Inc.
local api          = require "resty.store.api"
local utils        = require "resty.store.utils"

local setmetatable = setmetatable
local type         = type
local ipairs       = ipairs
local pairs        = pairs

local tab_insert   = table.insert
local str_format   = string.format
local str_sub      = string.sub
local str_len      = string.len


local _M = {}
local mt = { __index = _M }


-- called by lua-resty-load Lua Library in the init_by_lua* context to get code file
function _M.new(self, config)
    local store_config = config.store or {}
    local prefix = store_config.config_key_prefix or ""
    local store_cluster = store_config.cluster or {}
    return setmetatable({store_cluster=store_cluster, store_type=store_config.type, prefix=prefix}, mt)
end

function _M.list(self)
    local opts = { type=self.store_type, block=true, cluster=self.store_cluster,
        operation="list", default={} }
    local list, err = api.get(str_format("%s/lua", self.prefix), opts)
    if err then
        return nil, err
    end

    list["version"] = nil
    return list
end


local function _get(store_cluster, store_type, prefix, key)
    local opts = { type=store_type, block=true, cluster=store_cluster }
    local v, err = api.get(str_format("%s/lua/%s", prefix, key), opts)
    if err then
        return nil, err
    end

    if v == nil then
        return
    end

    if type(v) ~= "string" then
        return nil, "expected to be a string but got " .. type(v)
    end

    return  v
end


function _M.version(self)
    return _get(self.store_cluster, self.store_type, self.prefix, "version")
end


function _M.get(self, key)
    return _get(self.store_cluster, self.store_type, self.prefix, key)
end


return _M
