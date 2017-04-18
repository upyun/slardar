-- Copyright (C) 2016 Libo Huang (huangnauh), UPYUN Inc.
local cmsgpack     = require "cmsgpack"
local shcache      = require "resty.shcache"
local utils        = require "resty.consul.utils"
local api          = require "resty.consul.api"

local ipairs       = ipairs
local pairs        = pairs
local next         = next
local tonumber     = tonumber
local setmetatable = setmetatable
local str_sub      = string.sub

local _M = {}


-- get dynamic config from consul
local function load_config(config, key)
    local consul = config.consul or {}
    local cache_label = "consul_config"

    local _load_config = function()
        local key_prefix = consul.config_key_prefix or ""
        local key = key_prefix .. key .. "?raw"

        ngx.log(ngx.INFO, "get config from consul, key: " .. key)

        return  api.get_kv(key, {decode=utils.parse_body})
    end

    if consul.config_cache_enable == false then
        return _load_config()
    end

    local config_cache = shcache:new(
        ngx.shared.cache,
        { external_lookup = _load_config,
          encode = cmsgpack.pack,
          decode = cmsgpack.unpack,
        },
        { positive_ttl = consul.config_positive_ttl or 30,
          negative_ttl = consul.config_negative_ttl or 3,
          name = cache_label,
        }
    )

    local data, _ = config_cache:load(cache_label .. ":" .. key)

    return data
end

-- get server in the init_by_lua* context for the lua-resty-checkups Lua Library
function _M.init(config)
    local consul = config.consul or {}
    local key_prefix = consul.config_key_prefix or ""
    local consul_cluster = consul.cluster or {}
    local opts = {decode=utils.parse_body, default={}}
    local upstream_keys = api.get_kv_blocking(consul_cluster, key_prefix .. "upstreams?keys", opts)
    if not upstream_keys then
        return false
    end

    for _, key in ipairs(upstream_keys) do repeat
        local skey = str_sub(key, #key_prefix + 11)
        if #skey == 0 then
            break
        end

        -- upstream already exists in config.lua
        if config[skey] then
            break
        end

        local servers = api.get_kv_blocking(consul_cluster, key .. "?raw", opts)
        if not servers or not next(servers) then
            return false
        end

        config[skey] = {}

        if utils.check_servers(servers["servers"]) then
            local cls = {
                servers = servers["servers"],
                keepalive = tonumber(servers["keepalive"]),
                try =  tonumber(servers["try"]),
            }

            config[skey]["cluster"] = { cls }
        end

        -- fit config.lua format
        for k, v in pairs(servers) do
            -- copy other values
            if k ~= "servers" and k ~= "keepalive" and k ~= "try" then
                config[skey][k] = v
            end
        end
    until true end

    setmetatable(config, {
        __index = load_config,
    })

    return true
end


return _M
