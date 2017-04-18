-- Copyright (C) 2016 Libo Huang (huangnauh), UPYUN Inc.
local http         = require "socket.http"
local httpipe      = require "resty.httpipe"
local checkups     = require "resty.checkups"

local pairs        = pairs
local type         = type
local str_format   = string.format

local _M = {}


function _M.get_kv_blocking(cluster, key, opts)
    local opts = opts or {}
    -- try all the consul servers
    for _, cls in pairs(cluster) do
        for _, srv in pairs(cls.servers) do
            local url = str_format("http://%s:%s/v1/kv/%s", srv.host, srv.port, key)
            local body, code = http.request(url)
            if code == 404 then
                return opts.default
            elseif code == 200 and body then
                local decode = opts.decode
                if type(decode) == "function" then
                    return decode(body)
                else
                    return body
                end
            else
                ngx.log(ngx.ERR, str_format("get config from %s failed", url))
            end
        end
    end

    return nil, "get config failed"
end


function _M.get_kv(key, opts)
    local opts = opts or {}
    local hp, err = httpipe:new()
    if not hp then
        ngx.log(ngx.ERR, "failed to new httpipe: ", err)
        return
    end

    hp:set_timeout(5 * 1000)
    local req = {
        method = "GET",
        path = "/v1/kv/" .. key,
    }

    local callback = function(host, port)
        return hp:request(host, port, req)
    end

    local res, err = checkups.ready_ok("consul", callback)
    if not res then
        ngx.log(ngx.ERR, "failed to get config from consul, err:", err)
        hp:close()
        return
    end

    if res.status == 404 then
        return opts.default
    elseif res.status ~= 200 then
        ngx.log(ngx.ERR, "failed to get config from consul: ", res.status)
        hp:close()
        return
    end

    hp:set_keepalive()
    local body = res.body

    if type(opts.decode) == "function" then
        return opts.decode(body)
    else
        return body
    end
end


return _M
