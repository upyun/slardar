-- Copyright (C) 2016 Libo Huang (huangnauh), UPYUN Inc.
local cjson         = require "cjson.safe"
local setmetatable  = setmetatable
local getfenv       = getfenv
local setfenv       = setfenv
local require       = require
local loadfile      = loadfile
local pcall         = pcall
local loadstring    = loadstring
local next          = next
local pairs         = pairs
local ipairs        = ipairs
local type          = type
local str_find      = string.find
local str_format    = string.format
local str_sub       = string.sub
local tab_insert    = table.insert
local localtime     = ngx.localtime
local timer_at      = ngx.timer.at
local md5           = ngx.md5
local log           = ngx.log
local ERR           = ngx.ERR
local INFO          = ngx.INFO
local WARN          = ngx.WARN
local load_dict     = ngx.shared.load

local SKEYS_KEY     = "lua:skeys"
local VERSION_KEY   = "lua:version"
local LOAD_VERSION  = "load:version"
local TIMER_DELAY   = 1
local CODE_PREFIX   = "update:"
local version_dict  = {}
local global_version


local _M = {_VERSION = '0.01'}


local function pre_post(str, pattern)
    local from, to = str_find(str, pattern)
    if not from then
        return str, nil
    end
    local prefix = str_sub(str, 1, from - 1)
    local postfix = str_sub(str, to + 1)
    return prefix, postfix
end


local function set_load_version(version)
    local ok, err = load_dict:safe_set(LOAD_VERSION, version)
    if not ok then
        err = str_format('failed to set key: %s in load, err: %s', LOAD_VERSION, err)
        log(ERR, err)
        return nil, err
    else
        return true
    end
end


function _M.get_load_version()
    local load_version = load_dict:get(LOAD_VERSION)
    return load_version
end


local function lua_loader(module_name)
    local prefix = pre_post(module_name, "%.")
    if prefix ~= "script" then
        return "\n\tnot a script"
    end
    local filename = package.searchpath(module_name, package.path)
    if not filename then
        return "\n\tscript not in the filesystem"
    end

    local file, err = loadfile(filename)
    if not file then
        log(ERR, err)
        return function() return true end
    else
        log(INFO, "load " .. module_name .. " from filesystem")
        return function() return file end
    end
end


local function load_module(module_name, code)
    local f, err = loadstring(code, module_name)
    if not f then
        local err_str = str_format('failed to load %s from code: %s', module_name, err)
        log(ERR, err_str)
        return nil, err_str
    end
    local prefix, _ = pre_post(module_name, "%.")
    if prefix == "script" then
        return {mod=f, version=md5(code)}
    end
    local mod = f()
    if not mod then
        local err_str = str_format('%s lua source does not return the module', module_name)
        log(ERR, err_str)
        return nil, err_str
    end
    return {mod=mod, version=md5(code)}
end


local function get_code_version(skey)
    local code = load_dict:get(CODE_PREFIX .. skey)
    if not code then
        log(INFO, str_format("%s code not found in shdict", skey))
        return nil, "code not found in shdict"
    end
    return md5(code)
end


local function load_syncer(premature)
    if premature then
        return
    end

    local version = load_dict:get(VERSION_KEY)
    if version and version ~= global_version then
        local skeys = load_dict:get(SKEYS_KEY)
        if skeys then
            skeys = cjson.decode(skeys)
        else
            skeys = {}
        end

        for key in pairs(version_dict) do
            if not skeys[key] then
                log(INFO, key, " unload from package")
                version_dict[key] = nil
                package.loaded[key] = nil
            end
        end

        for skey, sh_value in pairs(skeys) do
            local worker_version
            if type(version_dict[skey]) == "table" then
                worker_version = version_dict[skey]["version"]
            end
            if package.loaded[skey] and worker_version ~= sh_value.version then
                log(INFO, skey, " version changed")
                version_dict[skey] = nil
                package.loaded[skey] = nil
            end
        end

        global_version = version
    end

    local ok, err = timer_at(TIMER_DELAY, load_syncer)
    if not ok then
        log(ERR, "failed to create timer: ", err)
    end
end


function _M.create_load_syncer()
    global_version = load_dict:get(VERSION_KEY)
    local ok, err = timer_at(TIMER_DELAY, load_syncer)
    if not ok then
        log(ERR, "failed to create load_lua timer: ", err)
        return nil, err
    else
        return true
    end
end


local function module_loader(module_name)
    local skeys = load_dict:get(SKEYS_KEY)
    local sh_version
    if skeys then
        skeys = cjson.decode(skeys)
        local sh_value = skeys[module_name]
        if sh_value then
            sh_version = sh_value.version
        end
    end

    if sh_version then
        local code = load_dict:get(CODE_PREFIX .. module_name)
        local code_version
        if code then
            code_version = md5(code)
        end
        if sh_version ~= code_version then
            return str_format("\n\tcode version in confusion, sh_version: %s, code_version: %s",
                sh_version, code_version)
        else
            local mod_tab, err = load_module(module_name, code)
            if mod_tab then
                local mod = mod_tab.mod
                version_dict[module_name] = { version=mod_tab.version }
                log(INFO, module_name, " loaded from shdict, md5:", mod_tab.version)
                return function() return mod end
            else
                return "\n\t" .. err
            end
        end
    else
        local prefix = pre_post(module_name, "%.")
        if prefix == "script" then
            return function() return true end
        else
            return "\n\tcode not in shdict"
        end
    end
end


local function pre_load(config)
    if not config then
        return true
    end

    if type(config) ~= "table" then
        return nil, "load config invalid"
    end

    local load_init = config.load_init or {}
    local config_module = load_init.module_name
    if type(config_module) ~= "string" then
        return nil, "load_init invalid"
    end


    local ok, module = pcall(require, config_module)
    if not ok then
        log(ERR, module)
        return nil, str_format("module_name %s not find", config_module)
    end

    local mod = module:new(config)

    local load_version, err
    if type(mod.lversion) == "function" then
        load_version, err = mod:lversion()
        if err then
            return nil, err
        end

        load_version = load_version or "0"
        if type(load_version) ~= "string" or #load_version < 1 then
            return nil, "load_version invalid"
        end
    end

    load_version = load_version or "0"
    local ok, err = set_load_version(load_version)
    if not ok then
        return nil, err
    end

    local script_keys, err = mod:lkeys()
    if err then
        return nil, err
    end

    if not script_keys then
        log(WARN, "no code to load")
        return true
    end

    if type(script_keys) ~= "table" then
        return nil, "script_keys invalid"
    end

    if not next(script_keys) then
        log(WARN, "no code to load")
        return true
    end

    local skeys = {}
    for _, skey in ipairs(script_keys) do
        local ok = pcall(require, skey)
        if not ok then
            local code = mod:lget(skey)
            if not code then
                return nil, "fail to get code from consul"
            end
            local ok, err = load_dict:safe_set(CODE_PREFIX .. skey, code)
            if not ok then
                return nil, err
            end
            skeys[skey] = { version = md5(code), time = localtime() }
        end
    end

    if next(skeys) then
        local ok, err = load_dict:safe_set(SKEYS_KEY, cjson.encode(skeys))
        if not ok then
            err = str_format('failed to set key: %s in load, err: %s', SKEYS_KEY, err)
            log(ERR, err)
            return nil, err
        end
    end

    return true
end


function _M.init(config)
    tab_insert(package.loaders, 1, lua_loader)
    load_dict:flush_all()

    -- try load code from somewhere
    local ok, err = pre_load(config)
    if not ok then
        return nil, err
    end

    local ok, err = load_dict:safe_set(VERSION_KEY, 0)
    if not ok then
        err = str_format('failed to set key: %s in load, err: %s', VERSION_KEY, err)
        log(ERR, err)
        return nil, err
    end

    log(INFO, "load shdict finished")
    tab_insert(package.loaders, module_loader)
    return true
end


local function set_version(skey)
    local new_version, err = get_code_version(skey)
    if not new_version then
        return nil, err
    end

    local skeys = load_dict:get(SKEYS_KEY)
    if skeys then
        skeys = cjson.decode(skeys)
    else
        skeys = {}
    end

    local sh_value = skeys[skey]
    local sh_version
    if sh_value then
        sh_version = sh_value.version
    end

    if new_version ~= sh_version then
        skeys[skey] = {version=new_version, time=localtime()}
        local ok, err = load_dict:safe_set(SKEYS_KEY, cjson.encode(skeys))
        if not ok then
            return nil, str_format('failed to set key: %s in load, err: %s', SKEYS_KEY, err)
        end
    else
        return false, "code already loaded"
    end

    log(INFO, skey, " new version setted")
    return true
end


function _M.uninstall_code(skey)
    local skeys = load_dict:get(SKEYS_KEY)
    if skeys then
        skeys = cjson.decode(skeys)
        local sh_value = skeys[skey]
        if sh_value then
            skeys[skey] = nil
            if next(skeys) then
                local ok, err = load_dict:safe_set(SKEYS_KEY, cjson.encode(skeys))
                if not ok then
                    return false, str_format('failed to set key: %s in load, err: %s', skey, err)
                end
            else
                load_dict:delete(SKEYS_KEY)
            end
        end
    end

    load_dict:delete(CODE_PREFIX .. skey)

    local _, err = load_dict:incr(VERSION_KEY, 1)
    if err then
        return false, err
    end

    log(INFO, skey, " deleted from shdict")
    return true
end

function _M.set_code(skey, body, load_version)
    if not body then
        return nil, "need code to set"
    end

    local load_version = load_version or "0"

    if type(load_version) ~= "string" or load_version == "" or #load_version > 32 then
        return nil, "load version invalid"
    end

    local old_body = load_dict:get(CODE_PREFIX .. skey)
    if old_body then
        local old_md5 = md5(old_body)
        local new_md5 = md5(body)
        if new_md5 == old_md5 then
            return nil, "code already in shdict"
        end
    end

    local ok, err = load_dict:safe_set(CODE_PREFIX .. skey, body)
    if not ok then
        return nil, str_format('failed to set key: %s in load, err: %s', skey, err)
    end

    local ok, err = set_load_version(load_version)
    if not ok then
        return nil, err
    end

    log(INFO, skey, " new code setted")
    return true
end


function _M.install_code(skey)
    if not skey then
        local keys = load_dict:get_keys()
        local srcipt_keys = {}

        -- first set module
        for _, key in ipairs(keys) do
            local prefix, postfix = pre_post(key, ":")
            if prefix == "update" and postfix then
                local pre = pre_post(postfix, "%.")
                if pre == "srcipt" then
                    tab_insert(srcipt_keys, key)
                else
                    local ok, err = set_version(postfix)
                    if not ok and err ~= "code already loaded" then
                        return nil, err
                    end
                end
            end
        end

        -- then set script
        for _, key in ipairs(srcipt_keys) do
            local ok, err = set_version(key)
            if not ok and err ~= "code already loaded" then
                return nil, err
            end
        end
    else
        local ok, err = set_version(skey)
        if not ok then
            return nil, err
        end
    end

    local _, err = load_dict:incr(VERSION_KEY, 1)
    if err then
        return nil, err
    end
    return true
end


function _M.get_version(skey)
    local skeys = load_dict:get(SKEYS_KEY)
    if skeys then
        skeys = cjson.decode(skeys)
    else
        skeys = {}
    end

    if not skey then
        local ver = load_dict:get(VERSION_KEY)
        local load_ver = load_dict:get(LOAD_VERSION)
        local data = {global_version=ver, commit_version=load_ver, modules={}}
        for key, value in pairs(skeys) do
            tab_insert(data.modules, {version=value.version, time=value.time, name=key})
        end
        return data
    else
        local mod_name = skey
        local sh_value = skeys[skey]
        if sh_value then
            return {version=sh_value.version, time=sh_value.time, name=mod_name }
        else
            return {}
        end
    end
end


function _M.load_script(script_name, opts)
    local opts = opts or {}
    local ok, mode = pcall(require, script_name)
    if not ok then
        log(ERR, mode)
        return nil
    end

    if mode and type(mode) == "function" then
        local env = opts.env or {}
        if opts.global then
            env = setmetatable(env, { __index = getfenv(0) })
        end
        setfenv(mode, env)
        return mode
    end
    return nil
end


return _M
