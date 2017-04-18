-- Copyright (C) 2017 Libo Huang (huangnauh), UPYUN Inc.
local ffi   = require "ffi"
local base  = require "resty.core.base"


local C         = ffi.C
local ffi_str   = ffi.string
local errmsg    = base.get_errmsg_ptr()
local FFI_OK    = base.FFI_OK
local getfenv   = getfenv
local error     = error
local type      = type
local tonumber  = tonumber


ffi.cdef[[
    struct ngx_stream_session_s;
    typedef struct ngx_stream_session_s  ngx_stream_session_t;
]]


ffi.cdef[[
int ngx_stream_lua_ffi_balancer_set_current_peer(ngx_stream_session_t *r,
    const unsigned char *addr, size_t addr_len, int port, char **err);

int ngx_stream_lua_ffi_balancer_set_more_tries(ngx_stream_session_t *r,
    int count, char **err);
]]


local _M = { version = base.version }


function _M.set_current_peer(addr, port)
    local s = getfenv(0).__ngx_sess
    if not s then
        return error("no session found")
    end

    if not port then
        port = 0
    elseif type(port) ~= "number" then
        port = tonumber(port)
    end

    local rc = C.ngx_stream_lua_ffi_balancer_set_current_peer(s, addr, #addr,
                                                            port, errmsg)
    if rc == FFI_OK then
        return true
    end

    return nil, ffi_str(errmsg[0])
end


function _M.set_more_tries(count)
    local s = getfenv(0).__ngx_sess
    if not s then
        return error("no session found")
    end

    local rc = C.ngx_stream_lua_ffi_balancer_set_more_tries(s, count, errmsg)
    if rc == FFI_OK then
        if errmsg[0] == nil then
            return true
        end
        return true, ffi_str(errmsg[0])
    end

    return nil, ffi_str(errmsg[0])
end


return _M
