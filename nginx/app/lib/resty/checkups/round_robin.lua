-- Copyright (C) 2014-2016 UPYUN, Inc.

local cjson      = require "cjson.safe"

local str_format = string.format
local floor      = math.floor
local sqrt       = math.sqrt

local state      = ngx.shared.state
local now        = ngx.now


local _M = {
    _VERSION = "0.11"
}


local function _gcd(a, b)
    while b ~= 0 do
        a, b = b, a % b
    end

    return a
end


local function select_round_robin_server(ckey, cls, verify_server_status, bad_servers)
    -- The algo below may look messy, but is actually very simple it calculates
    -- the GCD  and subtracts it on every iteration, what interleaves endpoints
    -- and allows us not to build an iterator every time we readjust weights.
    -- https://github.com/mailgun/vulcan/blob/master/loadbalance/roundrobin/roundrobin.go
    local err_msg = "round robin: no servers available"
    local servers = cls.servers

    if type(servers) ~= "table" or not next(servers) then
        return nil, nil, "round robin: no servers in this cluster"
    end

    if type(bad_servers) ~= "table" then
        bad_servers = {}
    end

    local srvs_len = #servers
    if srvs_len == 1 then
        local srv = servers[1]
        if not verify_server_status or verify_server_status(srv, ckey) then
            if not bad_servers[1] then
                return srv, 1
            end
        end

        return nil, nil, err_msg
    end

    local rr = cls.rr
    local index, current_weight = rr.index, rr.current_weight
    local gcd, max_weight, weight_sum = rr.gcd, rr.max_weight, rr.weight_sum
    local failed_count = 1

    repeat
        index = index % srvs_len + 1
        if index == 1 then
            current_weight = current_weight - gcd
            if current_weight <= 0 then
                current_weight = max_weight
            end
        end

        local srv = servers[index]
        if srv.effective_weight >= current_weight then
            cls.rr.index, cls.rr.current_weight = index, current_weight
            if not bad_servers[index] then
                if verify_server_status then
                    if verify_server_status(srv, ckey) then
                        return srv, index
                    else
                        if srv.effective_weight > 1 then
                            srv.effective_weight = 1
                            _M.reset_round_robin_state(cls)
                            local rr = cls.rr
                            gcd, max_weight, weight_sum = rr.gcd, rr.max_weight, rr.weight_sum
                            index, current_weight, failed_count = 0, 0, 0
                        end
                        failed_count = failed_count + 1
                    end
                else
                    return srv, index
                end
            else
                failed_count = failed_count + 1
            end
        end
    until failed_count > weight_sum

    return nil, nil, err_msg
end


local try_servers_round_robin = function(ckey, cls, verify_server_status, callback, opts)
    local base = require "resty.checkups.base"

    local try, check_res, check_opts, srv_flag, skey =
        opts.try, opts.check_res, opts.check_opts, opts.srv_flag, opts.skey
    local args = opts.args or {}

    if not check_res then
        check_res = function(res)
            if res then
                return true
            end
            return false
        end
    end

    local bad_servers = {}
    local err
    for i = 1, #cls.servers, 1 do
        local srv, index, _err = select_round_robin_server(ckey, cls, verify_server_status, bad_servers)
        if not srv then
            return nil, try, _err
        else
            local res, _err
            if srv_flag then
                res, _err = callback(srv.host, srv.port, unpack(args))
            else
                res, _err = callback(srv, ckey)
            end

            if check_res(res, check_opts) then
                if srv.effective_weight ~= srv.weight then
                    srv.effective_weight = srv.weight
                    _M.reset_round_robin_state(cls)
                end
                return res
            elseif skey then
                base.set_srv_status(skey, srv, true)
            end

            if srv.effective_weight > 1 then
                srv.effective_weight = floor(sqrt(srv.effective_weight))
                _M.reset_round_robin_state(cls)
            end

            try = try - 1
            if try < 1 then
                return nil, nil, _err
            end

            bad_servers[index] = true
            err = _err
        end
    end

    return nil, try, err
end


local function calc_gcd_weight(servers)
    -- calculate the GCD, maximum weight and weight sum value from a set of servers
    local gcd, max_weight, weight_sum = 0, 0, 0

    for _, srv in ipairs(servers) do
        if not srv.weight or type(srv.weight) ~= "number" or srv.weight < 1 then
            srv.weight = 1
        end

        if not srv.effective_weight then
            srv.effective_weight = srv.weight
        end

        if srv.effective_weight > max_weight then
            max_weight = srv.effective_weight
        end

        weight_sum = weight_sum + srv.effective_weight
        gcd = _gcd(srv.effective_weight, gcd)
    end

    return gcd, max_weight, weight_sum
end


function _M.try_cluster_round_robin_(skey, ups, cls, callback, args, try_again)
    local base = require "resty.checkups.base"

    local srvs_len = #cls.servers

    local try
    if try_again then
        try = try_again
    else
        try = cls.try or srvs_len
    end

    local verify_server_status = function(srv)
        local peer_key = base._gen_key(skey, srv)
        local peer_status = cjson.decode(state:get(base.PEER_STATUS_PREFIX .. peer_key))
        if (peer_status == nil or peer_status.status ~= base.STATUS_ERR)
            and base.get_srv_status(skey, srv) == base.STATUS_OK then
            return true
        end
        return
    end

    local opts = {
        try = try,
        check_res = base.check_res,
        check_opts = ups,
        srv_flag = true,
        args = args,
        skey = skey,
    }
    local res, try, err = try_servers_round_robin(nil, cls, verify_server_status, callback, opts)
    if res then
        return res
    end

    -- continue to next level
    if try and try > 0 then
        return nil, try, err
    end

    return nil, nil, err
end


function _M.try_cluster_round_robin(clusters, verify_server_status, callback, opts)
    local cluster_key = opts.cluster_key

    local err
    for _, ckey in ipairs(cluster_key) do
        local cls = clusters[ckey]
        if type(cls) == "table" and type(cls.servers) == "table" and next(cls.servers) then
            local res, _try, _err = try_servers_round_robin(ckey, cls, verify_server_status, callback, opts)
            if res then
                return res
            end

            if not _try or _try < 1 then
                return nil, _err
            end

            opts.try = _try
            err = _err
        end
    end

    return nil, err or "no servers available"
end


function _M.reset_round_robin_state(cls)
    local rr = { index = 0, current_weight = 0 }
    rr.gcd, rr.max_weight, rr.weight_sum = calc_gcd_weight(cls.servers)
    cls.rr = rr
end


return _M
