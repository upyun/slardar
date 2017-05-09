-- Copyright (C) 2017 Libo Huang (huangnauh), UPYUN Inc.
local stream_protocol = require "modules.protocol"

local protocol, err = stream_protocol:new()
if err then
    return
end

while true do
    local ok = protocol:process()
    if not ok then
        return
    end
end
