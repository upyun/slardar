-- Copyright (C) 2015-2016, UPYUN Inc.

local checkups  = require "resty.checkups.api"
local errno     = require "modules.errno"
local utils     = require "modules.utils"
local mload     = require "modules.load"

local slardar = slardar

local env = {
    ngx=ngx,
    errno=errno,
    utils=utils,
    slardar={
        exit=slardar.exit,
    },
}

local skey = ngx.var.host
local func = mload.load_script("script." .. skey, env)
if func then
    func()
end
