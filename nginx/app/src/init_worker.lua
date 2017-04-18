-- Copyright (C) 2015-2016, UPYUN Inc.

local checkups = require "resty.checkups.api"
local mload    = require "resty.load"

checkups.prepare_checker(slardar)

-- only one checkups timer is active among all the nginx workers
checkups.create_checker()

mload.create_load_syncer()
