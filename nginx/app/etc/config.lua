local _M = {}


_M.global = {
    checkup_timer_interval = 5,
    checkup_timer_overtime = 60,
    default_heartbeat_enable = true,

    checkup_shd_sync_enable = true,
    shd_config_timer_interval = 1,
    shd_config_prefix = "shd_v1",
}


_M.consul = {
    timeout = 5,

    enable = false,

    config_key_prefix = "config/slardar/",
    config_positive_ttl = 10,
    config_negative_ttl = 5,
    config_cache_enable = true,

    cluster = {
        {
            servers = {
                -- change these to your own consul http addresses
                { host = "10.0.5.108", port = 8500 },
            },
        },
    },
}


return _M
