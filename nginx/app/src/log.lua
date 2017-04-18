-- Copyright (C) 2017 Libo Huang (huangnauh), UPYUN Inc.

local logger = require "modules.logger"

local slardar = slardar

if slardar.logger.enable ~= false then
    logger.start()
end
