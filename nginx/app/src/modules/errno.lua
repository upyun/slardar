local str_sub = string.sub

local _M = {
    OK                  = {0, "ok"},

    HTTP_OK             = {200, "ok"},
    HTTP_NOT_MODIFIED   = {304, "not modified"},
    HTTP_UNAUTHORIZED   = {401, "unauthorized"},
    HTTP_BAD_REQUEST    = {400, "bad request"},
    HTTP_NOT_FOUND      = {404, "not found"},
    HTTP_FORBIDDEN      = {403, "forbidden"},
    HTTP_NOT_ALLOWED    = {405, "method not allowed"},
    HTTP_PRECONDITION   = {412, "precondition failed"},
    HTTP_MEDIA_TYPE_ERR = {415, "media type error"},
    HTTP_TOO_MANY_REQS  = {429, "to many requests"},
    HTTP_SERVICE_UNAVAILABLE = {503, "service unavailable"},

    EXIT_TRY_CODE       = {40099999, "exit try code"},
    UNKNOWN_ERR         = {50300000, "unknown error"},
}


local _mt = {
    __index = function(t, k)
        if k == "code" then
            return t[1]
        elseif k == "httpcode" then
            return tonumber(str_sub(t[1], 1, 3))
        elseif k == "msg" then
            return t[2]
        end
    end,

    __tostring = function(t)
        return t[1]
    end,

    __eq = function(a, b)
        return a[1] == b[1]
    end,
}

local code2key = {}

for k, v in pairs(_M) do
    setmetatable(v, _mt)
    code2key[v[1]] = k
end
setmetatable(_M, {
    __index = function(t, v)
        ngx.log(ngx.ERR, "unknown err: ", v)
        return _M.UNKNOWN_ERR
    end
})


function _M.from_code(code)
    if not code or not tonumber(code) then
        return _M.UNKNOWN_ERR
    end
    local key = code2key[tonumber(code)]
    return _M[key]
end


return _M
