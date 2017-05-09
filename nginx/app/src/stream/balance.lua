-- Copyright (C) 2017 Libo Huang (huangnauh), UPYUN Inc.
local checkups  = require "resty.checkups.api"
local balancer  = require "ngx.stream_balancer"

local set_current_peer = balancer.set_current_peer
local set_more_tries = balancer.set_more_tries

local peer, ok, err
peer, err = checkups.select_peer(ngx.var.server_port)
if not peer then
    ngx.log(ngx.ERR, "select peer failed, ", err)
    return
end

ngx.ctx.last_peer = peer

ok, err = set_current_peer(peer.host, peer.port)
if not ok then
    ngx.log(ngx.ERR, "set_current_peer failed, ", err)
    return
end

ok, err = set_more_tries(1)
if not ok then
    ngx.log(ngx.ERR, "set_more_tries failed, ", err)
    return
end
