-- Copyright (C) 2017 Libo Huang (huangnauh), UPYUN Inc.
local checkups = require "resty.checkups.api"

checkups.prepare_checker(slardar)

-- only one checkups timer is active among all the nginx workers
checkups.create_checker()
