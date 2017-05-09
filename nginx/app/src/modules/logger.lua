-- Copyright (C) 2017 Libo Huang (huangnauh), UPYUN Inc.

local logger = require "resty.logger.socket"
local mload  = require "resty.load"
local cjson  = require "cjson.safe"

local tonumber  = tonumber

local slardar = slardar
local ups = slardar.logger

local version = slardar.global.version or ''
local conf_hash = slardar.global.conf_hash or ''


local _M = {}


function _M.start()
    if not logger.initted() then
        local config  = ups.config
        local timeout = ups.timeout

        if timeout and not config.timeout then
            config.timeout =  timeout * 1000 -- ms
        end

        local ok, err = logger.init(config)
        if not ok then
            ngx.log(ngx.ERR, err)
            return
        end
    end

    local content_type = (ngx.var.content_type == "") and '-' or ngx.var.content_type
    local upstream_response_time = tonumber(ngx.var.upstream_response_time) or -1

    local load_version = mload.get_load_version() or "0"
    local new_version = version .. '.' .. load_version
    local node_version = conf_hash .. '-' .. new_version

    local log_msg_tab = {
        node_type                  = ups.node_type                             ,
        node_host                  = ups.node_host                             ,
        node_name                  = ngx.var.hostname                          ,
        node_version               = node_version                       or '-' ,
        remote_addr                = ngx.var.remote_addr                or '-' ,
        remote_user                = ngx.var.remote_user                or '-' ,
        timestamp                  = ngx.var.time_local                 or '-' ,
        method                     = ngx.var.request_method             or '-' ,
        scheme                     = ngx.var.scheme                     or '-' ,
        http_host                  = ngx.var.host                       or '-' ,
        request_uri                = ngx.var.request_uri                or '-' ,
        protocol                   = ngx.var.server_protocol            or '-' ,
        status                     = ngx.var.status                     or '-' ,
        body_bytes_sent            = tonumber(ngx.var.body_bytes_sent)  or -1  ,
        referer                    = ngx.var.http_referer               or '-' ,
        user_agent                 = ngx.var.http_user_agent            or '-' ,
        content_type               = content_type                       or '-' ,
        content_length             = tonumber(ngx.var.content_length)   or -1  ,
        x_raw_uri                  = ngx.var.http_x_raw_uri             or '-' ,
        x_forwarded_for            = ngx.var.http_x_forwarded_for       or '-' ,
        x_request_id               = ngx.var.http_x_request_id          or '-' ,
        upstream_addr              = ngx.var.upstream_addr              or '-' ,
        upstream_status            = ngx.var.upstream_status            or '-' ,
        upstream_response_time     = upstream_response_time                    ,
        request_time               = tonumber(ngx.var.request_time)     or -1  ,
        x_error_code               = tonumber(ngx.var.x_error_code)     or -1  ,
    }

    local log_msg = cjson.encode(log_msg_tab) .. "\n"
    local bytes, err = logger.log(log_msg)
    if err then
        ngx.log(ngx.WARN, err)
        return
    end
end


return _M
