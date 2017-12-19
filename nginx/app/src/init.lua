-- Copyright (C) 2015-2016, UPYUN Inc.

local cjson    = require "cjson.safe"
local store    = require "resty.store.config"
local mload    = require "resty.load"
local checkups = require "resty.checkups.api"

local subsystem = ngx.config.subsystem

slardar = require "config" -- global config variable

slardar.global.version = "1.1.2"

if subsystem == 'http' then
    slardar.exit = function(err)
        if ngx.headers_sent then
            return ngx.exit(ngx.status)
        end

        local status, discard_body_err = pcall(ngx.req.discard_body)
        if not status then
            ngx.log(ngx.ERR, "discard_body err:", discard_body_err)
        end

        local code = err.code
        if ngx.var.x_error_code then
            ngx.var.x_error_code = code
        end
        -- standard http code, exit as usual
        if code >= 200 and code < 1000 then
            return ngx.exit(code)
        end

        local httpcode = err.httpcode
        ngx.status = httpcode
        local req_headers = ngx.req.get_headers()
        ngx.header["X-Error-Code"] = code
        ngx.header["Content-Type"] = "application/json"
        local body = cjson.encode({
            code = code,
            msg = err.msg,
        })
        ngx.header["Content-Length"] = #body
        ngx.print(body)
        return ngx.exit(httpcode)
    end
end


local no_store = slardar.global.no_store

-- if init config failed, abort -t or reload.
local ok, init_ok = pcall(store.init, slardar)
if no_store ~= true then
    if not ok then
        error("Init config failed, " .. init_ok .. ", aborting !!!!")
    elseif not init_ok then
        error("Init config failed, aborting !!!!")
    end
end

local ok, init_ok = pcall(mload.init, slardar)
if no_store ~= true then
    if not ok then
        error("Init lua script failed, " .. init_ok .. ", aborting !!!!")
    elseif not init_ok then
        error("Init lua script failed, aborting !!!!")
    end
end

local ok, init_ok = pcall(checkups.init, slardar)
if not ok then
    error("Init checkups failed, " .. init_ok .. ", aborting !!!!")
elseif not init_ok then
    error("Init checkups failed, aborting !!!!")
end
