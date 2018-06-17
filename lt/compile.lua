--
-- Generated from compile.lt
--
local read = require("lt.read")
local lex = require("lt.lex")
local scope = require("lt.scope")
local parse = require("lt.parse")
local check = require("lt.check")
local transform = require("lt.transform")
local generate = require("lt.generate")
local Slash = package.config:sub(1, 1)
local Circular = {}
local report = function(color)
    local Severe_Color = {color.yellow, color.magenta, color.red}
    local warnings = {}
    return {warn = function(line, col, severity, msg)
        local w = {line = line, col = col, severity = severity, msg = msg}
        for i, m in ipairs(warnings) do
            if line == m.line and severity < m.severity then
                return 
            end
            if line < m.line or line == m.line and col < m.col then
                table.insert(warnings, i, w)
                return 
            end
        end
        table.insert(warnings, w)
    end, as_text = function()
        local warns = {}
        for i, m in ipairs(warnings) do
            local clr = Severe_Color[m.severity] or color.white
            warns[i] = string.format(" %d,%d:" .. clr .. "  %s" .. color.reset, m.line, m.col, m.msg)
        end
        if #warns > 0 then
            return table.concat(warns, "\n")
        end
    end, continue = function()
        for _, w in ipairs(warnings) do
            if w.severity > 2 then
                return false
            end
        end
        return true
    end}
end
return function(options, color)
    local imports = {}
    local compile, import
    compile = function(reader)
        local ast, typ, luacode
        local r = report(color)
        local lexer = lex(reader, r.warn)
        if r.continue() then
            ast = parse(lexer, r.warn)
            if ast[1] then
                if r.continue() then
                    ast = transform(ast)
                    if r.continue() then
                        local sc = scope(options.declares, r.warn)
                        typ = check(sc, ast, r.warn, import)
                        if r.continue() then
                            luacode = generate(ast)
                        end
                    end
                end
            else
                r.warn(0, 0, 1, "No such file or file is empty")
            end
        end
        return typ, luacode, r.as_text()
    end
    import = function(name)
        local mod = imports[name]
        if mod then
            if mod == Circular then
                return false, "Circular import of '" .. name .. "'"
            end
            return mod.type, mod.code, mod.warns
        end
        imports[name] = Circular
        local path = string.gsub(name, "[.]", Slash) .. ".lt"
        local typ, code, warns = compile(read.file(path))
        imports[name] = {path = path, type = typ, code = code, warns = warns}
        return typ, code, warns, imports
    end
    return {file = function(src)
        local f = string.gsub(src, "%.lt", "")
        return import(f)
    end, string = function(src)
        return compile(read.string(src))
    end}
end