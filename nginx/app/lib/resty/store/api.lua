-- Copyright (C) 2016 Libo Huang (huangnauh), UPYUN Inc.
local http         = require "socket.http"
local cjson        = require "cjson.safe"
local httpipe      = require "resty.httpipe"
local checkups     = require "resty.checkups.api"

local pairs         = pairs
local ipairs        = ipairs
local type          = type
local str_format    = string.format
local str_match     = string.match
local decode_base64 = ngx.decode_base64
local log           = ngx.log
local ERR           = ngx.ERR
local INFO          = ngx.INFO

local _M = {}

local valid_store = {
    etcd = {
        api_prefix = "/v2/keys/",
        key = {
            postfix = "",
            extract = function(body)
                local data = cjson.decode(body)
                if type(data) ~= "table" then
                    return nil, "body invalid"
                end

                local node = data.node
                if type(node) ~= "table" then
                    return nil, "node invalid"
                end

                local value = node.value
                if type(value) ~= "string" then
                    return nil, "value invalid"
                end
                return value
            end
        },
        list = {
            postfix = "",
            extract = function(body)
                local data = cjson.decode(body)
                if type(data) ~= "table" then
                    return nil, "body invalid"
                end

                local node = data.node
                if type(node) ~= "table" then
                    return nil, "node invalid"
                end
                if not node.dir then
                    return nil, "dir invalid"
                end

                local nodes = node.nodes
                if not nodes then
                    return {}
                end

                if type(nodes) ~= "table" then
                    return nil, "nodes invalid"
                end

                local res = {}
                for _, node in ipairs(nodes) do
                    local key = node.key
                    if type(key) ~= "string" then
                        return nil, "key invalid"
                    end

                    key = str_match(key, "([^/]+)$")
                    local value = node.value
                    if key and value then
                        if type(value) ~= "string" then
                            return nil, "value invalid"
                        end
                        res[key] = value
                    end
                end
                return res
            end,

        },
    },
    consul = {
        api_prefix = "/v1/kv/",
        key = {
            postfix = "?raw",
            extract = function(body)
                return body
            end,
        },
        list = {
            postfix = "?recurse=true",
            extract = function(body)
                local nodes = cjson.decode(body)
                if type(nodes) ~= "table" then
                    return nil, "body invalid"
                end

                local res = {}
                for _, node in ipairs(nodes) do
                    local key = node.Key
                    if type(key) ~= "string" then
                        return nil, "Key invalid"
                    end

                    key = str_match(key, "([^/]+)$")
                    local value = node.Value
                    if key and value then
                        if type(value) ~= "string" then
                            return nil, "Value invalid"
                        end
                        value = decode_base64(value)
                        if value == nil then
                            return nil, "value not well formed"
                        end
                        res[key] = value
                    end
                end

                return res
            end,

        }
    }
}


local function get_store_blocking(path, opts)
    local opts = opts or {}
    local cluster = opts.cluster or {}
    -- try all the store servers
    for _, cls in pairs(cluster) do
        for _, srv in pairs(cls.servers) do
            local url = str_format("http://%s:%s%s", srv.host, srv.port, path)
            log(INFO, "get url: ", url)
            local resp, code = http.request(url)
            if code == 404 then
                return opts.default
            elseif code == 200 and resp then
                local body, err = opts.extract(resp)
                if err then
                    log(ERR, "extract body failed:", err)
                    return nil, err
                end

                local decode = opts.decode
                if type(decode) == "function" then
                    return decode(body)
                else
                    return body
                end
            else
                log(ERR, str_format("get config from %s failed", url))
            end
        end
    end

    return nil, "get config failed"
end


local function get_store(path, opts)
    local opts = opts or {}
    local hp, err = httpipe:new()
    if not hp then
        log(ERR, "failed to new httpipe: ", err)
        return nil, "new http failed"
    end

    log(INFO, "get path: ", path)

    hp:set_timeout(5 * 1000)
    local req = {
        method = "GET",
        path = path,
    }

    local callback = function(host, port)
        return hp:request(host, port, req)
    end

    local res, err = checkups.ready_ok("store", callback)
    if not res then
        ngx.log(ngx.ERR, "failed to get config from store, err:", err)
        hp:close()
        return nil, "store connection failed"
    end

    if res.status == 404 then
        return opts.default
    elseif res.status ~= 200 then
        ngx.log(ngx.ERR, "failed to get config from store: ", res.status)
        hp:close()
        return nil, "get store failed"
    end

    local body, err = opts.extract(res.body)
    if err then
        ngx.log(ngx.ERR, "extract body failed:", err)
        return nil, err
    end

    if type(opts.decode) == "function" then
        return opts.decode(body)
    else
        return body
    end
end


function _M.get(key, opts)
    local store_type = opts.type or "consul"
    local store = valid_store[store_type]
    if not store then
        log(ERR, "invalid store type ", store_type)
        return nil, "invalid store type"
    end

    local operation = opts.operation or "key"

    local operation_store = store[operation]
    if not operation_store then
        log(ERR, "invalid store operation ", operation)
        return nil, "invalid store operation"
    end
    local uri = str_format("%s%s%s", store.api_prefix, key, operation_store.postfix)
    opts.extract = operation_store.extract
    if opts.block then
        return get_store_blocking(uri, opts)
    else
        return get_store(uri, opts)
    end
end

return _M
