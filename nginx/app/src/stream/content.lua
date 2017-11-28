-- Copyright (C) 2017 Libo Huang (huangnauh), UPYUN Inc.
local mload     = require "resty.load"

local skey = "content" .. ngx.var.server_port
local func = mload.load_script("script." .. skey, { global=true })
if func then
    func()
end
