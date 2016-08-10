-- Copyright (C) 2014-2016 UPYUN, Inc.

local cjson = require "cjson.safe"

local floor = math.floor
local lower = string.lower

local state = ngx.shared.state

local _M = {
    _VERSION = "0.11",
}


local function hash_value(data)
    local key = 0
    local c

    data = lower(data)
    for i = 1, #data do
        c = data:byte(i)
        key = key * 31 + c
        key = key % 2^32
    end

    return key
end


function _M.try_cluster_consistent_hash(skey, ups, cls, callback, args, hash_key)
    local base = require "resty.checkups.base"

    local server_len = #cls.servers
    if server_len == 0 then
        return nil, true, "no server available"
    end

    local hash = hash_value(hash_key)
    local p = floor((hash % 1024) / floor(1024 / server_len)) % server_len + 1

    -- try hashed node
    local res, err = base.try_server(skey, ups, cls.servers[p], callback, args)
    if res then
        return res
    end

    -- try backup node
    local hash_backup_node = cls.hash_backup_node or 1
    local q = (p + hash % hash_backup_node + 1) % server_len + 1
    if p ~= q then
        local try = cls.try or #cls.servers
        res, err = base.try_server(skey, ups, cls.servers[q], callback, args, try - 1)
        if res then
            return res
        end
    end

    -- continue to next level
    return nil, true, err
end


return _M
