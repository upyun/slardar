-- Copyright (C) 2016 Libo Huang (huangnauh), UPYUN Inc.
local api          = require "resty.consul.api"
local utils        = require "resty.consul.utils"

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
    local consul_config = config.consul or {}
    local prefix = consul_config.config_key_prefix or ""
    local consul_cluster = consul_config.cluster or {}
    return setmetatable({consul_cluster=consul_cluster, prefix=prefix}, mt)
end


function _M.lkeys(self)
    local opts = {decode=utils.parse_body, default={}}
    local raw_keys, err = api.get_kv_blocking(self.consul_cluster, self.prefix .. "lua/?keys", opts)
    if err then
        return nil, err
    end

    if not raw_keys then
        return {}
    end

    if type(raw_keys) ~= "table" then
        return nil, "expected to be a table but got " .. type(raw_keys)
    end

    local script_keys = {}
    local version
    for _, key in ipairs(raw_keys) do
        local skey = str_sub(key, #self.prefix +  str_len("/lua/"))
        if skey ~= "" and skey ~= "version" then
            tab_insert(script_keys, skey)
        end
    end
    return script_keys
end


local function _lget(consul_cluster, prefix, key)
    local v, err = api.get_kv_blocking(consul_cluster, str_format("%s/lua/%s?raw", prefix, key))
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


function _M.lversion(self)
    return _lget(self.consul_cluster, self.prefix, "version")
end


function _M.lget(self, key)
    return _lget(self.consul_cluster, self.prefix, key)
end


return _M
