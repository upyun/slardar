-- Copyright (C) 2015-2016, UPYUN Inc.

local mload     = require "resty.load"
local errno     = require "modules.errno"
local utils     = require "modules.utils"

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
local func = mload.load_script("script." .. skey, {env=env, global=true})
if func then
    func()
end
