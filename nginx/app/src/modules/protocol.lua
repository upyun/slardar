-- Copyright (C) 2017 Libo Huang (huangnauh), UPYUN Inc.
local bit           = require "bit"
local cjson         = require "cjson.safe"
local checkups      = require "resty.checkups.api"
local consul        = require "resty.consul.config"
local utils         = require "modules.utils"

local type          = type
local rawget        = rawget
local ipairs        = ipairs
local setmetatable  = setmetatable
local tostring      = tostring
local str_byte      = string.byte
local str_char      = string.char
local str_sub       = string.sub
local upper         = string.upper
local lower         = string.lower
local str_format    = string.format
local tab_concat    = table.concat
local req_sock      = ngx.req.socket
local null          = ngx.null
local ERR           = ngx.ERR
local WARN          = ngx.WARN
local INFO          = ngx.INFO
local log           = ngx.log
local band          = bit.band
local bor           = bit.bor
local lshift        = bit.lshift
local rshift        = bit.rshift



local _M = {
    _VERSION = '0.01',
}

local mt = { __index = _M }

local PROTOCOL_OK      = 0
local PROTOCOL_MESSAGE = 1
local PROTOCOL_ERROR   = 2
local PROTOCOL_CONTINUE= 3

local slardar = slardar

local valid_method = { GET=true, PUT=true, DELETE=true }
local valid_topic = { upstream=true }


local function get_status()
    local result = checkups.get_status()

    if slardar.global.version ~= nil then
        result["slardar_version"] = slardar.global.version
    end
    return result
end


local function get_upstreams()
    return checkups.get_upstream()
end


local valid_info = { status=get_status, upstreams=get_upstreams }


function _M.new(self)
    local sock, err = req_sock()
    if not sock then
        log(ERR, "failed to get the request socket: ", err)
        return nil, err
    end

    return setmetatable({ sock = sock }, mt)
end


function _M.PUT_upstream(name, body)
    local upstream, err = consul.value2upstream(body)
    if not upstream then
        return false, err
    end

    local ok, err = checkups.update_upstream(name, upstream)
    return ok, err
end


function _M.GET_upstream(name, body)
    local func = valid_info[name]
    if type(func) ~= "function" then
        return nil, "only allowed"
    end

    local result, err = func()
    if err then
        return nil, err
    end
    return result
end


function _M.DELETE_upstream(name, body)
    local ok, err = checkups.delete_upstream(name)
    return ok, err
end


local function str_int32(int)
    return str_char(band(rshift(int, 24), 0xff),
                band(rshift(int, 16), 0xff),
                band(rshift(int, 8), 0xff),
                band(int, 0xff))
end


local function to_int32(str, offset)
    local offset = offset or 1
    local a, b, c, d = str_byte(str, offset, offset + 3)
    return bor(lshift(a, 24), lshift(b, 16), lshift(c, 8), d), offset + 4
end


local function handle_command(self)
    local sock = self.sock

    local reader = sock:receiveuntil("\n")
    local data, err = reader()
    if not data then
        if err == "client aborted" then
            log(INFO, "err: ", err)
        else
            log(ERR, "failed to receive: ", err)
        end
        return nil, err
    end

    log(INFO, "read: ", data)
    local commands = utils.str_split(data, " ")
    if #commands ~= 3 then
        return { code=PROTOCOL_ERROR, message="command invalid" }
    end

    local method, topic, name = upper(commands[1]), lower(commands[2]), commands[3]
    if not valid_method[method] then
        return { code=PROTOCOL_ERROR, message="method invalid" }
    end

    if not valid_topic[topic] then
        return { code=PROTOCOL_ERROR, message="topic invalid" }
    end
    return { code=PROTOCOL_CONTINUE, command={method=method, topic=topic, name=name} }
end


local function need_body(command)
    return command.method == "PUT"
end


local function handle_body(self)
    local sock = self.sock
    local data, err = sock:receive(4)
    if not data then
        log(ERR, "failed to receive: ", err)
        return nil, err
    end

    local body_len = to_int32(data)
    log(INFO, "read body len: ", body_len)
    if body_len <= 0 then
        return nil, "body invalid"
    end

    local data, err = sock:receive(body_len)
    if not data then
        return nil, err
    end
    log(INFO, "read body: ", data)

    local body = cjson.decode(data)
    if type(body) ~= "table" then
        return { code=PROTOCOL_ERROR, message="body invalid" }
    end

    return { code=PROTOCOL_CONTINUE, body=body }
end


local function handle_response(self, command)
    local body, err

    if need_body(command) then
        local response, err = handle_body(self)
        if not response then
            return nil, err
        end

        if response.code ~= PROTOCOL_CONTINUE then
            return response
        end

        body = response.body
    end

    local key = command.method .. "_" .. command.topic
    local func = _M[key]
    if type(func) ~= "function" then
        return { code=PROTOCOL_ERROR, message=key .. "not allowed" }
    end

    local res, err = func(command.name, body)
    if not res then
        return { code=PROTOCOL_ERROR, message=err }
    elseif res == true then
        return { code=PROTOCOL_OK, message="OK" }
    else
        return { code=PROTOCOL_MESSAGE, message=cjson.encode(res) }
    end
    return res, err
end


local function handle(self)
    local res, err = handle_command(self)
    if err then
        return nil, err
    end

    if res.code ~= PROTOCOL_CONTINUE then
        return res
    end

    return handle_response(self, res.command)
end


local function format_message(res)
    local res_code = str_int32(res.code)
    local body = str_format("%s%s", res_code, res.message)
    local len_body = #body
    log(INFO, "write: ", str_format("%s%s", str_int32(len_body), body))
    return str_format("%s%s", str_int32(len_body), body)
end


function _M.process(self)
    local res, err = handle(self)
    if err then
        return false
    end

    ngx.print(format_message(res))
    return true
end

return _M
