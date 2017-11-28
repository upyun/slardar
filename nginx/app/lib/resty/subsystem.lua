-- Copyright (C) 2017 Libo Huang (huangnauh), UPYUN Inc.

local str_format      = string.format
local ngx_log         = ngx.log
local CRIT            = ngx.CRIT
local ngx_config      = ngx.config
local ngx_subsystem   = ngx_config and ngx_config.subsystem or 0
local ngx_lua_version = ngx_config and ngx_config.ngx_lua_version or 0

local _M = {}

local function get_shm_key(key)
    if ngx_subsystem == "http" then
        return key
    else
        return str_format("%s_%s", ngx_subsystem, key)
    end
end


function _M.get_shm(key)
    local shm_key = get_shm_key(key)
    return ngx.shared[shm_key]
end

_M.get_shm_key = get_shm_key


function _M.check_version(lua_version, stream_lua_version)
    if ngx_subsystem == "http" then
        if ngx_lua_version < lua_version then
            ngx_log(CRIT, "We strongly recommend you to update your ngx_lua module to "
                .. lua_version .. " or above.")
            return false
        else
            return true
        end
    elseif ngx_subsystem == 'stream' then
        if ngx_lua_version < stream_lua_version then
            ngx_log(CRIT, "We strongly recommend you to update your stream_lua_ngx module to "
                .. stream_lua_version .. " or above.")
            return false
        else
            return true
        end
    end
    return false
end

return _M
