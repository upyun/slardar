-- Copyright (C) 2016 Libo Huang (huangnauh), UPYUN Inc.
local cjson        = require "cjson.safe"
local type         = type
local next         = next
local pairs        = pairs

local _M = {  _VERSION = '0.01' }


function _M.parse_body(body)
    local data = cjson.decode(body)
    if not data then
        ngx.log(ngx.ERR, "json decode body failed, ", body)
        return
    end

    return data
end


function _M.check_servers(servers)
    if not servers or type(servers) ~= "table" or not next(servers) then
        return false
    end

    for _, srv in pairs(servers) do
        if not srv.host or not srv.port then
            return false
        end

        if srv.weight and type(srv.weight) ~= "number" or
            srv.max_fails and type(srv.max_fails) ~= "number" or
            srv.fail_timeout and type(srv.fail_timeout) ~= "number" then
            return false
        end
    end

    return true
end


return _M
