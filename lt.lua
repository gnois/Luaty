--
-- Generated from lt.lt
--
local term = require("term")
local compiler = require("lt.compile")
local color = term.color
local write = term.write
local usage = function(err)
    term.usage(err or "", "\n", [=[
Usage: 
  luajit lt.lua [-f] [-t] [-d xvar] path/src [dst]
  
    if src does not end with .lt, .lt is appended

    if dst is omitted, path/src.lt will be run
    else if dst ends with .lua, path/src.lt will be transpiled to dst
    else dst is assumed to be a folder, path/src.lt will be transpiled to dst/path/src.lua, and its dependencies to dst/path/*.lua
  
    -f        Force overwrite if output file already exists. Ignored if dst is omitted.
    -t        Enable type checking
    -d xvar   Declares `xvar` to silent undeclared identifier warning
  
  Running without parameters enters Read-Generate-Eval-Print loop
]=])
end
local force = false
local typecheck = false
local single = false
local paths = {}
local decls = {}
for s, p in term.scan({...}) do
    if s == "f" then
        if s == "f" then
            force = true
        end
        if p then
            table.insert(paths, p)
        end
    elseif s == "d" then
        if p then
            decls[p] = true
        else
            usage("Error: -d requires identifier")
        end
    else
        if s == "t" then
            typecheck = true
        elseif s ~= "" then
            usage("Error: unknown switch -" .. s)
        end
        if p then
            table.insert(paths, p)
        end
    end
end
local src, dst
if #paths > 2 then
    usage("Error: only one file with an optional output accepted")
else
    src = paths[1]
    dst = paths[2]
    if src then
        if string.sub(src, 2, 2) == ":" then
            src = string.sub(src, 3)
        end
    end
    if dst then
        if string.sub(dst, -string.len(".lua")) == ".lua" then
            single = true
        else
            dst = string.gsub(dst, term.slash .. "*$", "")
        end
    end
end
local compile = compiler({declares = decls, typecheck = typecheck, single = single}, color)
if src then
    local warns, imports, main = compile.file(src)
    if not dst then
        if force then
            write(color.red, "-f is ignored", color.reset, "\n")
        end
        if warns then
            write(warns, "\n")
        end
        local file = imports[main]
        if file.code then
            local fn = assert(loadstring(file.code))
            fn()
            write("\n")
        end
    else
        local created = {}
        local existed = {}
        local skips = {}
        for __, file in pairs(imports) do
            local dest = dst
            if not single then
                dest = string.gsub(file.path, "%.lt", ".lua")
                dest = dst .. term.slash .. string.gsub(dest, "^" .. term.slash .. "*", "")
            end
            write(dest, ":")
            if file.warns then
                write("\n", file.warns, "\n")
            elseif file.code then
                write(" Ok\n")
            end
            if file.code then
                local name = dest
                local dir
                string.gsub(dest, "(.*[/\\])(.*)", function(d, n)
                    dir = d
                    name = n
                end)
                if not force and not created[dir or ""] then
                    local f = io.open(dest, "r")
                    if f then
                        skips[dest] = 1
                        f:close()
                    end
                end
                if not skips[dest] then
                    if dir and not created[dir] and not existed[dir] then
                        if term.exist_dir(dir) then
                            existed[dir] = true
                        else
                            local x, err = term.mkdir(dir)
                            if not x then
                                error(err)
                            end
                            created[dir] = true
                        end
                    end
                    local f, err = io.open(dest, "wb")
                    if not f then
                        error(err)
                    end
                    local srcname = string.gsub(file.path, "(.*[/\\])(.*)", "%2")
                    f:write("--\n-- Generated from ", srcname, "\n--")
                    f:write(file.code)
                    f:close()
                end
            else
                skips[dest] = -1
            end
        end
        local fails, f = {}, 1
        for k, v in pairs(skips) do
            if v == 1 then
                fails[f] = k .. " already exists. Use -f to overwrite"
            else
                fails[f] = "Fail to generate " .. k
            end
            f = f + 1
        end
        if f > 1 then
            write(color.red, table.concat(fails, "\n"), color.reset, "\n")
        end
    end
else
    local show_results = function(...)
        if select("#", ...) > 1 then
            write(select(2, ...))
        end
    end
    local flush = function()
        io.stdout:flush()
    end
    local read = function()
        return io.stdin:read()
    end
    write([[-- empty line to transpile, \q to quit --]], "\n")
    local list = {}
    repeat
        write("> ")
        flush()
        local s = read()
        if s == [[\q]] then
            break
        elseif s and #s > 0 then
            list[#list + 1] = s
        else
            local str = table.concat(list, "\n")
            list = {}
            local _, code, warns = compile.string(str)
            if warns then
                write(warns)
            end
            if code then
                write(color.cyan, code, color.reset)
                local fn, err = loadstring(code)
                if err then
                    fn = load("return (" .. fn .. ")", "stdin")
                end
                if fn then
                    show_results(pcall(fn))
                else
                    write(err)
                end
            end
            write("\n")
        end
    until false
end
