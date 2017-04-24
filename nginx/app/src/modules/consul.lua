local cjson     = require "cjson.safe"
local cmsgpack  = require "cmsgpack"
local http      = require "socket.http"
local httpipe   = require "resty.httpipe"
local checkups  = require "resty.checkups.api"
local shcache   = require "resty.shcache"

local tab_insert = table.insert
local tab_concat = table.concat
local str_format = string.format
local str_sub    = string.sub


local _M = {}


local function parse_body(body)
    local data = cjson.decode(body)
    if not data then
        ngx.log(ngx.ERR, "json decode body failed, ", body)
        return
    end

    return data
end


local function get_servers(cluster, key)
    -- try all the consul servers
    for _, cls in pairs(cluster) do
        for _, srv in pairs(cls.servers) do
            local url = str_format("http://%s:%s/v1/kv/%s", srv.host, srv.port, key)
            local body, code = http.request(url)
            if code == 404 then
                return {}
            elseif code == 200 and body then
                return parse_body(body)
            end
            ngx.log(ngx.WARN, str_format("get config from %s failed", url))
        end
    end
end


function _M.get_script_blocking(cluster, key, need_raw)
    -- try all the consul servers
    for _, cls in pairs(cluster) do
        for _, srv in pairs(cls.servers) do
            local url = str_format("http://%s:%s/v1/kv/%s", srv.host, srv.port, key)
            local body, code = http.request(url)
            if code == 404 then
                return nil
            elseif code == 200 and body then
                if need_raw then
                    return body
                else
                    return parse_body(body)
                end
            else
                ngx.log(ngx.ERR, str_format("get config from %s failed", url))
            end
        end
    end
end


local function get_value(cluster, key)
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
    if not res or res.status ~= 200 then
        ngx.log(ngx.ERR, "failed to get config from consul: ", err or res.status)
        hp:close()
        return
    end
    hp:set_keepalive()

    return parse_body(res.body)
end


local function check_servers(servers)
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


function _M.init(config)
    local consul = config.consul or {}
    local key_prefix = consul.config_key_prefix or ""
    local consul_cluster = consul.cluster or {}

    local upstream_keys = get_servers(consul_cluster, key_prefix .. "upstreams?keys")
    if not upstream_keys then
        return false
    end

    for _, key in ipairs(upstream_keys) do repeat
        local skey = str_sub(key, #key_prefix + 11)
        if #skey == 0 then
            break
        end
        -- upstream already exists in config.lua
        if config[skey] then
            break
        end

        local servers = get_servers(consul_cluster, key .. "?raw")
        if not servers or not next(servers) then
            return false
        end

        config[skey] = {}

        if check_servers(servers["servers"]) then
            local cls = {
                servers = servers["servers"],
                keepalive = tonumber(servers["keepalive"]),
                try =  tonumber(servers["try"]),
            }
            config[skey]["cluster"] = { cls }
        end

        -- fit config.lua format
        for k, v in pairs(servers) do
            -- copy other values
            if k ~= "servers" and k ~= "keepalive" and k ~= "try" then
                config[skey][k] = v
            end
        end
    until true end

    return true
end


function _M.load_config(config, key)
    local consul = config.consul or {}
    local cache_label = "consul_config"

    local _load_config = function()
        local consul_cluster = consul.cluster or {}
        local key_prefix = consul.config_key_prefix or ""
        local key = key_prefix .. key .. "?raw"

        ngx.log(ngx.INFO, "get config from consul, key: " .. key)

        return  get_value(consul_cluster, key)
    end

    if consul.config_cache_enable == false then
        return _load_config()
    end

    local config_cache = shcache:new(
        ngx.shared.cache,
        { external_lookup = _load_config,
          encode = cmsgpack.pack,
          decode = cmsgpack.unpack,
        },
        { positive_ttl = consul.config_positive_ttl or 30,
          negative_ttl = consul.config_negative_ttl or 3,
          name = cache_label,
        }
    )

    local data, _ = config_cache:load(cache_label .. ":" .. key)

    return data
end


return _M
