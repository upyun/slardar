local str_sub     = string.sub
local str_gsub    = string.gsub
local str_find    = string.find
local str_match   = string.match
local str_byte    = string.byte
local str_reverse = string.reverse
local tab_insert  = table.insert
local tab_concat  = table.concat
local tab_sort    = table.sort

local _M = {}


function _M.str_split(str, split_char)
    local sub_str_tab = {}
    local i, j = 0, 0
    local ss
    while true do
        j = str_find(str, split_char, i + 1, true)
        if not j then
            j = #str + 1
        end
        ss = str_sub(str, i + 1, j - 1)
        if #ss > 0 then
            tab_insert(sub_str_tab, ss)
        end
        if j >= #str then
            break
        end
        i = j
    end
    return sub_str_tab
end


function _M.str_join(tab, sep)
    return tab_concat(tab, sep)
end


function _M.basename(path)
    local dir, file = path:match"(.*/)(.*)"
    if #file == 0 then
        return dir
    end
    return dir, file
end


function _M.filename(filename)
    -- no "."
    if not str_find(filename, ".", 1, true) then
        return filename
    end

    -- ends with "."
    if str_byte(filename, -1) == str_byte(".") then
        return str_sub(filename, 1, -2)
    end

    return filename:match"(.*)%.(.+)"
end


function _M.null(e)
    return  e == nil or e == ngx.null
end


function _M.sorted_pairs(t, order)
    local keys = {}
    for k in pairs(t) do
        tab_insert(keys, k)
    end

    if order then
        tab_sort(keys, function(a, b) return order(t, a, b) end)
    else
        tab_sort(keys)
    end

    local i = 0
    return function()
        i = i + 1
        if keys[i] then return keys[i], t[keys[i]] end
    end
end


return _M
