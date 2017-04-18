-- Copyright (C) 2017 Libo Huang (huangnauh), UPYUN Inc.
local consul = require "resty.consul.config"

slardar = require "config" -- global config variable

slardar.global.version = "0.3.7"

-- if init config failed, abort -t or reload.
local ok, init_ok = pcall(consul.init, slardar)
if not ok then
    error("Init config failed, " .. init_ok .. ", aborting !!!!")
elseif not init_ok then
    error("Init config failed, aborting !!!!")
end
