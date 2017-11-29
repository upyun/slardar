-- Copyright (C) 2017 Libo Huang (huangnauh), UPYUN Inc.
local mload     = require "resty.load"
local log       = ngx.log
local INFO      = ngx.INFO

local skey = "preread" .. ngx.var.server_port
local func = mload.load_script("script." .. skey, { global=true })
if func then
    func()
else
    log(INFO, "script not exist, " .. skey)
end
