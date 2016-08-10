local cjson         = require "cjson.safe"

local round_robin   = require "resty.checkups.round_robin"
local base          = require "resty.checkups.base"

local worker_id     = ngx.worker.id
local update_time   = ngx.update_time
local mutex         = ngx.shared.mutex
local state         = ngx.shared.state
local shd_config    = ngx.shared.config
local log           = ngx.log
local ERR           = ngx.ERR
local WARN          = ngx.WARN
local INFO          = ngx.INFO

local str_format    = string.format

local _M = {
    _VERSION = "0.11",
    STATUS_OK = base.STATUS_OK, STATUS_UNSTABLE = base.STATUS_UNSTABLE, STATUS_ERR = base.STATUS_ERR
}

local function _gen_shd_key(skey)
    return str_format("%s:%s", base.SHD_CONFIG_PREFIX, skey)
end
_M._gen_shd_key = _gen_shd_key


local function shd_config_syncer(premature)
    local ckey = base.CHECKUP_TIMER_KEY .. ":shd_config:" .. worker_id()
    update_time()

    if premature then
        local ok, err = mutex:set(ckey, nil)
        if not ok then
            log(WARN, "failed to update shm: ", err)
        end
        return
    end

    local lock, err = base.get_lock(base.SKEYS_KEY)
    if not lock then
        log(WARN, "failed to acquire the lock: ", err)
        return
    end

    local config_version, err = shd_config:get(base.SHD_CONFIG_VERSION_KEY)

    if config_version and config_version ~= base.upstream.shd_config_version then
        local skeys = shd_config:get(base.SKEYS_KEY)
        if skeys then
            skeys = cjson.decode(skeys)

            -- delete skey from upstream
            for skey, _ in pairs(base.upstream.checkups) do
                if not skeys[skey] then
                    base.upstream.checkups[skey] = nil
                end
            end

            local success = true
            for skey, _ in pairs(skeys) do
                local shd_servers, err = shd_config:get(_gen_shd_key(skey))
                log(INFO, "get ", skey, " from shm: ", shd_servers)
                if shd_servers then
                    shd_servers = cjson.decode(shd_servers)
                    -- add new skey
                    if not base.upstream.checkups[skey] then
                        base.upstream.checkups[skey] = {}
                    end

                    base.upstream.checkups[skey].cluster = base.table_dup(shd_servers)

                    local ups = base.upstream.checkups[skey].cluster
                    -- only reset for rr cluster
                    for level, cls in ipairs(ups) do
                        round_robin.reset_round_robin_state(cls)
                    end
                elseif err then
                    success = false
                    log(WARN, "failed to get from shm: ", err)
                end
            end

            if success then
                base.upstream.shd_config_version = config_version
            end
        end
    elseif err then
        log(WARN, "failed to get config version from shm")
    end

    base.release_lock(lock)

    local interval = base.upstream.shd_config_timer_interval

    local overtime = base.upstream.checkup_timer_overtime
    local ok, err = mutex:set(ckey, 1, overtime)
    if not ok then
        log(WARN, "failed to update shm: ", err)
    end

    local ok, err = ngx.timer.at(interval, shd_config_syncer)
    if not ok then
        log(WARN, "failed to create timer: ", err)
        local ok, err = mutex:set(ckey, nil)
        if not ok then
            log(WARN, "failed to update shm: ", err)
        end
        return
    end
end

_M.shd_config_syncer = shd_config_syncer


function _M.check_update_server_args(skey, level, server)
    if type(skey) ~= "string" then
        return false, "skey must be a string"
    end
    if type(level) ~= "number" and type(level) ~= "string" then
        return false, "level must be string or number"
    end
    if type(server) ~= "table" then
        return false, "server must be a table"
    end
    if not server.host or not server.port then
        return false, "no server.host nor server.port found"
    end

    return true
end


function _M.do_update_upstream(skey, upstream)
    local skeys = shd_config:get(base.SKEYS_KEY)
    if not skeys then
        return false, "no skeys found from shm"
	end

    skeys = cjson.decode(skeys)

    local new_ver, ok, err

    new_ver, err = shd_config:incr(base.SHD_CONFIG_VERSION_KEY, 1)

    if err then
        log(WARN, "failed to set new version to shm")
        return false, err
    end

    local key = _gen_shd_key(skey)
    ok, err = shd_config:set(key, cjson.encode(upstream))

    if err then
        log(WARN, "failed to set new upstream to shm")
        return false, err
    end

    -- new skey
    if not skeys[skey] then
        skeys[skey] = 1
        local _, err = shd_config:set(base.SKEYS_KEY, cjson.encode(skeys))
        if err then
            log(WARN, "failed to set new skeys to shm")
            return false, err
        end
        log(INFO, "add new skey to upstreams, ", skey)
    end

    return true
end


function _M.do_delete_upstream(skey)
    local skeys = shd_config:get(base.SKEYS_KEY)
    if skeys then
        skeys = cjson.decode(skeys)
    else
        return false, "upstream " .. skey .. " not found"
    end

    local key = _gen_shd_key(skey)
    local shd_servers, err = shd_config:get(key)
    if shd_servers then
        local new_ver, ok, err
        new_ver, err = shd_config:incr(base.SHD_CONFIG_VERSION_KEY, 1)
        if err then
            log(WARN, "failed to set new version to shm")
            return false, err
        end

        ok, err = shd_config:delete(key)
        if err then
            log(WARN, "failed to set new servers to shm")
            return false, err
        end

        skeys[skey] = nil

        local _, err = shd_config:set(base.SKEYS_KEY, cjson.encode(skeys))
        if err then
            log(WARN, "failed to set new skeys to shm")
            return false, err
        end

        log(INFO, "delete skey from upstreams, ", skey)

    elseif err then
        return false, err
    else
        return false, "upstream " .. skey .. " not found"
    end

    return true
end


function _M.create_shd_config_syncer()
    local ckey = base.CHECKUP_TIMER_KEY .. ":shd_config:" .. worker_id()
    local val, err = mutex:get(ckey)
    if val then
        return
    end

    if err then
        log(WARN, "failed to get key from shm: ", err)
        return
    end

    local ok, err = ngx.timer.at(0, shd_config_syncer)
    if not ok then
        log(WARN, "failed to create shd_config timer: ", err)
        return
    end

    local overtime = base.upstream.checkup_timer_overtime
    local ok, err = mutex:set(ckey, 1, overtime)
    if not ok then
        log(WARN, "failed to update shm: ", err)
    end
end


return _M
