 -- Copyright (C) 2015-2016, UPYUN Inc. 

local cjson     = require "cjson.safe"
local checkups  = require "resty.checkups.api"

local type          = type
local read_body     = ngx.req.read_body
local get_body_data = ngx.req.get_body_data


local _M = { _VERSION = "0.0.1" }


function _M.update_upstream(skey)
    read_body()
    local body = get_body_data()
    if not body then
        return ngx.HTTP_BAD_REQUEST, "body too big"
    end

    body = cjson.decode(body)
    if not body then
        return ngx.HTTP_BAD_REQUEST, "decode body error"
    end

    if type(body.servers) ~= "table" and type(body.cluster) ~= "table" then
        return ngx.HTTP_BAD_REQUEST, "body invalid"
    end

    local ok, err = checkups.update_upstream(skey, body)
    if not ok then
        return ngx.HTTP_BAD_REQUEST, err
    end

    return ngx.HTTP_OK
end


function _M.delete_upstream(skey)
    local ok, err = checkups.delete_upstream(skey)
    if not ok then
        return ngx.HTTP_BAD_REQUEST, err
    end

    return ngx.HTTP_OK
end


return _M
