-- Copyright (C) 2015-2016, UPYUN Inc.

local cjson     = require "cjson.safe"
local checkups  = require "resty.checkups.api"
local mload     = require "modules.load"

local get_method    = ngx.req.get_method
local read_body     = ngx.req.read_body
local get_body_data = ngx.req.get_body_data
local ngx_match     = ngx.re.match

local slardar = slardar

checkups.create_checker()

local result = {}


local function update_upstream(skey)
    read_body()
    local body = get_body_data()
    if not body then
        return ngx.HTTP_BAD_REQUEST, "body to big"
    end

    body = cjson.decode(body)
    if not body then
        return ngx.HTTP_BAD_REQUEST, "decode body error"
    end

    local ok, err = checkups.update_upstream(skey, {{ servers = body.servers}})
    if not ok then
        return ngx.HTTP_BAD_REQUEST, err
    end

    return ngx.HTTP_OK
end


local function delete_upstream(skey)
    local ok, err = checkups.delete_upstream(skey)
    if not ok then
        return ngx.HTTP_BAD_REQUEST, err
    end

    return ngx.HTTP_OK
end


local request_uri = ngx.var.request_uri
if request_uri == "/status" then
    result = checkups.get_status()

    if slardar.global.version ~= nil then
        result["slardar_version"] = slardar.global.version
    end
else
    local m = ngx_match(request_uri, "^/upstream/([-_a-zA-Z0-9\\.]+)$", "jo")
    if m then
        local skey = m[1]

        local status, err
        local method = get_method()
        if method == "PUT" or method == "POST" then
            status, err = update_upstream(skey)
        elseif method == "DELETE" then
            status, err = delete_upstream(skey)
        else
            status, err =  ngx.HTTP_NOT_ALLOWED, "method not allowed"
        end

        result = { status = status, msg = err }
        ngx.status = status
    else
        m = ngx_match(request_uri, "^/lua(/(?<name>[-_a-zA-Z0-9\\.]+)?)?$", "jo")
        if m then
            local method = get_method()
            local skey = m.name
            if method == "POST" then
                read_body()
                local body = get_body_data()
                if not body then
                    result = "need body to upload"
                else
                    local _, err = mload.set_code(skey, body)
                    result = err or "ok"
                end
            elseif method == "PUT" then
                local _, err = mload.install_code(skey)
                result = err or "ok"
            elseif method == "DELETE" then
                local _, err = mload.uninstall_code(skey)
                result = err or "ok"
            elseif method == "GET" then
                result = mload.get_version(skey)
            end
        else
            ngx.status = ngx.HTTP_BAD_REQUEST
        end
    end
end

-- print to downstream

local content = cjson.encode(result) or ""

ngx.header.content_type = "application/json"
ngx.print(content)

return ngx.exit(ngx.HTTP_OK)
