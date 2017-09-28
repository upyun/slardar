local _M = {}


_M.global = {
    -- checkups send heartbeats to backend servers every 5s.
    checkup_timer_interval = 5,

    -- checkups timer key will expire in every 60s.
    -- In most cases, you don't need to change this value.
    checkup_timer_overtime = 60,

    -- checkups will sent heartbeat to servers by default.
    default_heartbeat_enable = true,

    -- create upstream syncer for each worker.
    -- If set to false, dynamic upstream will not work properly.
    -- This switch is used for compatibility purpose only in checkups,
    -- don't change this in slardar.
    checkup_shd_sync_enable = true,

    -- sync upstream list from shared memory every 1s
    shd_config_timer_interval = 1,

    -- If no_store is set to true, Slardar will continue start or reload
    -- even if getting data from key-value store failed.
    -- Remember to set this value to false when you need to read persisted
    -- upstreams or lua codes from key-value store.
    no_store = true,
}


_M.store = {
    -- key-value store type
    type = "etcd",

    -- connect to key-value store will timeout in 5s.
    timeout = 5,

    -- disable checkups heartbeat to key-value store.
    enable = false,

    -- key-value store prefix.
    -- Slardar will read upstream list from {config_key_prefix}/upstreams/.
    config_key_prefix = "config/slardar",

    -- positive cache ttl(in seconds) for dynamic configurations from key-value store.
    config_positive_ttl = 10,

    -- negative cache ttl(in seconds) for dynamic configurations from key-value store.
    config_negative_ttl = 5,

    -- enable or disable dynamic configurations cache from key-value store.
    config_cache_enable = true,

    cluster = {
        {
            servers = {
                -- change these to your own key-value store http addresses
                { host = "127.0.0.1", port = 2379 },
            },
        },
    },
}

_M.load_init = {
    -- load_init module name for lua-resty-load
    module_name = "resty.store.load"
}


_M.logger = {

    timeout = 2,

    -- enable logger.
    enable = true,

    -- node info in the log message
    node_type = "slardar_access",
    node_host = "127.0.0.1",

    config = {

        -- config for lua-resty-logger-socket
        flush_limit = 4096,
        drop_limit = 1024 * 1024, -- 1MB
        pool_size = 10,
        retry_interval = 100,
        max_retry_times = 3,

        -- upstream name for lua-resty-checkups
        ups_name = "logger",
    },

    cluster = {
        {
            servers = {
                -- change these to your own log server addresses
                { host = "127.0.0.1", port = 3100 },
            },
        },
    },
}


return _M
