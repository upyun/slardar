-- Copyright (C) 2017 Libo Huang (huangnauh), UPYUN Inc.
local store    = require "resty.store.config"
local checkups = require "resty.checkups.api"

slardar = require "config" -- global config variable

slardar.global.version = "0.3.7"

local no_store = slardar.global.no_store

-- if init config failed, abort -t or reload.
local ok, init_ok = pcall(store.init, slardar)
if no_store ~= true then
    if not ok then
        error("Init config failed, " .. init_ok .. ", aborting !!!!")
    elseif not init_ok then
        error("Init config failed, aborting !!!!")
    end
end

local ok, init_ok = pcall(checkups.init, slardar)
if not ok then
    error("Init checkups failed, " .. init_ok .. ", aborting !!!!")
elseif not init_ok then
    error("Init checkups failed, aborting !!!!")
end
