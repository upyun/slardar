-- Copyright (C) 2015-2016, UPYUN Inc.

local checkups = require "resty.checkups.api"
local mload    = require "modules.load"

checkups.prepare_checker(slardar)

mload.create_load_syncer()
