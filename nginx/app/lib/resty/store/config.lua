-- Copyright (C) 2016 Libo Huang (huangnauh), UPYUN Inc.
local cmsgpack     = require "cmsgpack"
local shcache      = require "resty.shcache"
local utils        = require "resty.store.utils"
local api          = require "resty.store.api"
local subsystem    = require "resty.subsystem"

local pairs        = pairs
local next         = next
local type         = type
local setmetatable = setmetatable
local ngx_subsystem= ngx.config.subsystem

local get_shm_key  = subsystem.get_shm_key

local _M = {}


-- get dynamic config from key-value store
local function load_config(config, key)
    local store_config = config.store or {}
    local cache_label = "store_config"

    local _load_config = function()
        local key_prefix = store_config.config_key_prefix or ""
        local key = key_prefix .. key

        ngx.log(ngx.INFO, "get config from key-value store, key: " .. key)

        local opts = { type=store_config.type, operation="key", decode=utils.parse_body }
        local value, err = api.get(key, opts)
        return value
    end

    if store_config.config_cache_enable == false then
        return _load_config()
    end

    local config_cache = shcache:new(
        ngx.shared.cache,
        { external_lookup = _load_config,
          encode = cmsgpack.pack,
          decode = cmsgpack.unpack,
        },
        { positive_ttl = store_config.config_positive_ttl or 30,
          negative_ttl = store_config.config_negative_ttl or 3,
          name = cache_label,
          lock_shdict = get_shm_key("locks"),
        }
    )

    local data, _ = config_cache:load(cache_label .. ":" .. key)

    return data
end


-- get server in the init_by_lua* context for the lua-resty-checkups Lua Library
function _M.init(config)
    local store_config = config.store or {}
    local key_prefix = store_config.config_key_prefix or ""
    local store_cluster = store_config.cluster or {}
    local upstreams_prefix = "upstreams"
    if ngx_subsystem ~= "http" then
        upstreams_prefix = "upstreams_" .. ngx_subsystem
    end

    local opts = { type=store_config.type, block=true, cluster=store_cluster, operation="list", default={} }
    local upstream_list = api.get(key_prefix .. upstreams_prefix, opts)
    if type(upstream_list) ~= "table" then
        return false
    end

    for skey, value in pairs(upstream_list) do repeat
        -- upstream already exists in config.lua
        if config[skey] then
            break
        end

        local servers = utils.parse_body(value)
        if not servers or not next(servers) then
            return false
        end

        config[skey] = {}

        if utils.check_servers(servers["servers"]) then
            local cls = {
                servers = servers["servers"],
            }

            config[skey]["cluster"] = { cls }
        end

        -- fit config.lua format
        for k, v in pairs(servers) do
            -- copy other values
            if k ~= "servers" then
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
