--
-- Generated from parse.lt
--

local tree = require("lt.ast")
local scope = require("lt.scope")
local operator = require("lt.operator")
local Keyword = require("lt.reserved")
local LJ_52 = false
local EndOfChunk = {TK_dedent = true, TK_else = true, TK_until = true, TK_eof = true}
local EndOfFunction = {["}"] = true, [")"] = true, [";"] = true, [","] = true}
local NewLine = {TK_newline = true}
local Kind = {Expr = 1, Self = 2, Var = 3, Field = 4, Index = 5, Call = 6}
local stmted
local is_keyword = function(ls)
    local str = ls.tostr(ls.token)
    if Keyword[str] then
        return str
    end
end
local err_syntax = function(ls, em)
    ls.error(ls, "%s", em)
end
local as_val = function(ls)
    if ls.value then
        return "'" .. ls.value .. "'"
    end
end
local err_instead = function(ls, em, ...)
    local msg = string.format(em, ...)
    ls.error(ls, "%s instead of %s", msg, as_val(ls) or ls.astext(ls.token))
end
local err_expect = function(ls, token)
    err_instead(ls, "%s expected", ls.astext(token))
end
local err_symbol = function(ls)
    local sym = ls.tostr(ls.token)
    local replace = {["end"] = "<dedent>", ["local"] = "`var`", ["function"] = "\\...->", ["elseif"] = "`else if`", ["repeat"] = "`do`"}
    local rep = replace[sym]
    if rep then
        ls.error(ls, "use %s instead of '%s'", rep, sym)
    else
        ls.error(ls, "unexpected %s", as_val(ls) or ls.astext(ls.token))
    end
end
local lex_opt = function(ls, tok)
    if ls.token == tok then
        ls.step()
        return true
    end
    return false
end
local lex_check = function(ls, tok)
    if ls.token ~= tok then
        err_expect(ls, tok)
    end
    ls.step()
end
local lex_match = function(ls, what, who, line)
    if not lex_opt(ls, what) then
        if line == ls.line then
            err_expect(ls, what)
        else
            err_instead(ls, "%s expected to match %s at line %d", ls.astext(what), ls.astext(who), line)
        end
    end
end
local lex_str = function(ls)
    local s
    if ls.token ~= "TK_name" and (LJ_52 or ls.token ~= "TK_goto") then
        err_expect(ls, "TK_name")
        s = ls.tostr(ls.token)
    else
        s = ls.value
    end
    ls.step()
    return s
end
local lex_indent = function(ls)
    if NewLine[ls.token] and ls.next() == "TK_indent" then
        lex_opt(ls, "TK_newline")
        ls.step()
        return true
    end
    return false
end
local lex_dedent = function(ls)
    if ls.token == "TK_dedent" or NewLine[ls.token] and ls.next() == "TK_dedent" then
        lex_opt(ls, "TK_newline")
        ls.step()
        return true
    end
    return false
end
local lex_opt_dent = function(ls, dented)
    if not dented then
        dented = lex_indent(ls)
    else
        dented = not lex_dedent(ls)
    end
    lex_opt(ls, "TK_newline")
    return dented
end
local expr_primary, expr, expr_unop, expr_binop, expr_simple, expr_list, expr_table
local parse_body, parse_args, parse_block, parse_opt_chunk
local var_name = function(ast, ls)
    local name = lex_str(ls)
    local vk = Kind.Var
    if name == "self" or name == "@" then
        vk = Kind.Self
    end
    return ast:identifier(name), vk
end
local expr_field = function(ast, ls, v)
    ls.step()
    local key = is_keyword(ls)
    if key then
        ls.step()
        return ast:expr_index(v, ast:literal(key))
    end
    key = lex_str(ls)
    return ast:expr_property(v, key), v, key
end
local expr_bracket = function(ast, ls)
    ls.step()
    local v = expr(ast, ls)
    lex_check(ls, "]")
    return v
end
expr_table = function(ast, ls)
    local line = ls.line
    local kvs = {}
    local dented = false
    lex_check(ls, "{")
    while ls.token ~= "}" do
        dented = lex_opt_dent(ls, dented)
        if not dented and ls.token == "TK_dedent" then
            err_symbol(ls)
            ls.step()
        end
        if ls.token == "}" then
            break
        end
        local key
        if ls.token == "[" then
            key = expr_bracket(ast, ls)
            lex_check(ls, "=")
        elseif ls.next() == "=" then
            if ls.token == "TK_name" then
                local name = lex_str(ls)
                key = ast:literal(name)
            elseif ls.token == "TK_string" then
                key = ast:literal(ls.value)
                ls.step()
            else
                local name = is_keyword(ls)
                if name then
                    key = ast:literal(name)
                    ls.step()
                end
            end
            lex_check(ls, "=")
        end
        local val = expr(ast, ls)
        if key then
            for i = 1, #kvs do
                local arr = kvs[i]
                if ast.same(arr[2], key) then
                    err_syntax(ls, "duplicate key at position " .. i .. " and " .. #kvs + 1 .. " in table")
                end
            end
        end
        kvs[#kvs + 1] = {val, key}
        dented = lex_opt_dent(ls, dented)
        if ls.token == ";" then
            err_instead(ls, "use %s", ls.astext(","))
        end
        if not lex_opt(ls, ",") and not lex_opt(ls, ";") then
            break
        end
    end
    if dented and not lex_dedent(ls) then
        err_instead(ls, "%s expected to match %s at line %d", ls.astext("TK_dedent"), ls.astext("TK_indent"), line)
    end
    lex_match(ls, "}", "{", line)
    return ast:expr_table(kvs, line)
end
local expr_function = function(ast, ls)
    local line = ls.line
    if ls.token == "\\" then
        ls.step()
    end
    local curry, args, body = parse_body(ast, ls, line)
    local lambda = ast:expr_function(args, body)
    if curry then
        curry = ast:identifier("curry")
        local identifier = ast:in_scope(curry)
        if identifier ~= true then
            err_syntax(ls, "`" .. identifier .. "()` is required for `~>`")
        end
        local cargs = {ast:literal(#args), lambda}
        return ast:expr_function_call(curry, cargs, line)
    end
    return lambda
end
expr_simple = function(ast, ls)
    local tk, val = ls.token, ls.value
    local e
    if tk == "TK_number" then
        e = ast:numberliteral(val)
    elseif tk == "TK_string" then
        e = ast:literal(val)
    elseif tk == "TK_longstring" then
        e = ast:longstrliteral(val)
    elseif tk == "TK_nil" then
        e = ast:literal(nil)
    elseif tk == "TK_true" then
        e = ast:literal(true)
    elseif tk == "TK_false" then
        e = ast:literal(false)
    elseif tk == "..." then
        if not ast.scope.varargs then
            err_syntax(ls, "cannot use `...` in a function without variable arguments")
        end
        e = ast:expr_vararg()
    elseif tk == "{" then
        return expr_table(ast, ls)
    elseif tk == "\\" or tk == "->" or tk == "~>" then
        return expr_function(ast, ls)
    else
        return expr_primary(ast, ls)
    end
    ls.step()
    return e
end
expr_list = function(ast, ls, nmax)
    local exps = {}
    exps[1] = expr(ast, ls)
    while ls.token == "," do
        ls.step()
        exps[#exps + 1] = expr(ast, ls)
    end
    local n = #exps
    if nmax and n > nmax then
        err_syntax(ls, "assigning " .. n .. " values to " .. nmax .. " variable(s)")
    end
    return exps
end
expr_unop = function(ast, ls)
    local tk = ls.token
    if tk == "TK_not" or tk == "-" or tk == "#" then
        local line = ls.line
        ls.step()
        local v = expr_binop(ast, ls, operator.unary_priority)
        return ast:expr_unop(ls.tostr(tk), v, line)
    else
        return expr_simple(ast, ls)
    end
end
expr_binop = function(ast, ls, limit)
    local v, vk = expr_unop(ast, ls)
    local op = ls.tostr(ls.token)
    while operator.is_binop(op) and operator.left_priority(op) > limit do
        local line = ls.line
        ls.step()
        local v2, nextop = expr_binop(ast, ls, operator.right_priority(op))
        v = ast:expr_binop(op, v, v2, line)
        op = nextop
        vk = nil
    end
    return v, op, vk
end
expr = function(ast, ls)
    return expr_binop(ast, ls, 0)
end
expr_primary = function(ast, ls)
    local v, vk
    if ls.token == "(" then
        local line = ls.line
        ls.step()
        vk, v = Kind.Expr, ast:expr_brackets(expr(ast, ls))
        lex_match(ls, ")", "(", line)
    else
        v, vk = var_name(ast, ls)
    end
    local val, key
    while true do
        local line = ls.line
        if ls.token == "." then
            vk, v, val, key = Kind.Field, expr_field(ast, ls, v)
        elseif ls.token == "[" then
            key = expr_bracket(ast, ls)
            val = v
            vk, v = Kind.Index, ast:expr_index(val, key)
        elseif ls.token == "(" then
            local args, self1 = parse_args(ast, ls)
            if self1 and (vk == Kind.Field or vk == Kind.Index) then
                table.remove(args, 1)
                if vk == Kind.Field then
                    vk, v = Kind.Call, ast:expr_method_call(val, key, args, line)
                elseif vk == Kind.Index then
                    local nm = "_0"
                    local obj = ast:identifier(nm)
                    table.insert(args, 1, obj)
                    local body = {ast:local_decl({ast:var_declare(nm)}, {val}, line), ast:return_stmt({ast:expr_function_call(ast:expr_index(obj, key), args, line)}, line)}
                    local lambda = ast:expr_function({}, body, {varargs = false})
                    vk, v = Kind.Call, ast:expr_function_call(lambda, {}, line)
                end
            else
                vk, v = Kind.Call, ast:expr_function_call(v, args, line)
            end
        else
            break
        end
    end
    return v, vk
end
local parse_return = function(ast, ls, line)
    ls.step()
    ast.has_return = true
    local exps
    if EndOfChunk[ls.token] or NewLine[ls.token] or EndOfFunction[ls.token] then
        exps = {}
    else
        exps = expr_list(ast, ls)
    end
    return ast:return_stmt(exps, line)
end
local parse_for_num = function(ast, ls, varname, line)
    lex_check(ls, "=")
    local init = expr(ast, ls)
    lex_check(ls, ",")
    local last = expr(ast, ls)
    local step
    if lex_opt(ls, ",") then
        step = expr(ast, ls)
    else
        step = ast:literal(1)
    end
    scope.enter_block(ast.scope)
    local v = ast:var_declare(varname)
    local body = parse_block(ast, ls, line, "TK_for")
    scope.leave_block(ast.scope)
    return ast:for_stmt(v, init, last, step, body, line, ls.line)
end
local parse_for_iter = function(ast, ls, indexname)
    scope.enter_block(ast.scope)
    local vars = {ast:var_declare(indexname)}
    while lex_opt(ls, ",") do
        indexname = lex_str(ls)
        vars[#vars + 1] = ast:var_declare(indexname)
    end
    lex_check(ls, "TK_in")
    local line = ls.line
    local exps = expr_list(ast, ls)
    local body = parse_block(ast, ls, line, "TK_for")
    scope.leave_block(ast.scope)
    return ast:for_iter_stmt(vars, exps, body, line, ls.line)
end
local parse_for = function(ast, ls, line)
    ls.step()
    scope.enter_block(ast.scope, true)
    local varname = lex_str(ls)
    local stmt
    if ls.token == "=" then
        stmt = parse_for_num(ast, ls, varname, line)
    elseif ls.token == "," or ls.token == "TK_in" then
        stmt = parse_for_iter(ast, ls, varname)
    else
        err_instead(ls, "%s expected", "`=` or `in`")
    end
    scope.leave_block(ast.scope)
    return stmt
end
parse_args = function(ast, ls)
    local line = ls.line
    lex_check(ls, "(")
    if not LJ_52 and line ~= ls.prevline then
        err_syntax(ls, "ambiguous syntax (function call x new statement)")
    end
    local dented = false
    local self1, vk = false
    local args, n = {}, 0
    while ls.token ~= ")" do
        dented = lex_opt_dent(ls, dented)
        if not dented and ls.token == "TK_dedent" then
            err_symbol(ls)
            ls.step()
        end
        if ls.token == ")" then
            break
        end
        n = n + 1
        args[n], _, vk = expr(ast, ls)
        if n == 1 and vk == Kind.Self then
            self1 = true
        end
        dented = lex_opt_dent(ls, dented)
        if not lex_opt(ls, ",") then
            break
        end
    end
    if dented and not lex_dedent(ls) then
        err_instead(ls, "%s expected to match %s at line %d", ls.astext("TK_dedent"), ls.astext("TK_indent"), line)
    end
    lex_match(ls, ")", "(", line)
    return args, self1
end
local parse_assignment
parse_assignment = function(ast, ls, vlist, v, vk)
    local line = ls.line
    if vk ~= Kind.Var and vk ~= Kind.Self and vk ~= Kind.Field and vk ~= Kind.Index then
        err_symbol(ls)
    end
    vlist[#vlist + 1] = v
    if lex_opt(ls, ",") then
        local n_var, n_vk = expr_primary(ast, ls)
        return parse_assignment(ast, ls, vlist, n_var, n_vk)
    else
        lex_check(ls, "=")
        if vk == Kind.Var or vk == Kind.Self then
            local identifier = ast:in_scope(v)
            if identifier ~= true then
                err_syntax(ls, "undeclared identifier `" .. identifier .. "`")
            end
        end
        local exps = expr_list(ast, ls, #vlist)
        return ast:assignment_expr(vlist, exps, line)
    end
end
local parse_call_assign = function(ast, ls)
    local v, vk = expr_primary(ast, ls)
    if vk == Kind.Call then
        return ast:new_statement_expr(v, ls.line)
    else
        local vlist = {}
        return parse_assignment(ast, ls, vlist, v, vk)
    end
end
local parse_var = function(ast, ls)
    local line = ls.line
    local lhs = {}
    repeat
        local name = lex_str(ls)
        local v = ast:var_declare(name)
        lhs[#lhs + 1] = v
    until not lex_opt(ls, ",")
    local rhs
    if lex_opt(ls, "=") then
        rhs = expr_list(ast, ls, #lhs)
    else
        rhs = {}
    end
    return ast:local_decl(lhs, rhs, line)
end
local parse_while = function(ast, ls, line)
    ls.step()
    local cond = expr(ast, ls)
    scope.enter_block(ast.scope, true)
    local body = parse_block(ast, ls, line, "TK_while")
    scope.leave_block(ast.scope)
    local lastline = ls.line
    return ast:while_stmt(cond, body, line, lastline)
end
local parse_then = function(ast, ls, tests, line)
    ls.step()
    tests[#tests + 1] = expr(ast, ls)
    if ls.token == "TK_then" then
        err_syntax(ls, "`then` is not needed")
        ls.step()
    end
    return parse_block(ast, ls, line, "TK_if")
end
local parse_if = function(ast, ls, line)
    local tests, blocks = {}, {}
    blocks[#blocks + 1] = parse_then(ast, ls, tests, line)
    local else_branch
    while ls.token == "TK_else" or NewLine[ls.token] and ls.next() == "TK_else" do
        lex_opt(ls, "TK_newline")
        ls.step()
        if ls.token == "TK_if" then
            blocks[#blocks + 1] = parse_then(ast, ls, tests, line)
        else
            else_branch = parse_block(ast, ls, ls.line, "TK_else")
            break
        end
    end
    return ast:if_stmt(tests, blocks, else_branch, line)
end
local parse_do = function(ast, ls, line)
    ls.step()
    local body = parse_block(ast, ls, line, "TK_do")
    local lastline = ls.line
    return ast:do_stmt(body, line, lastline)
end
local parse_repeat = function(ast, ls, line)
    ls.step()
    scope.enter_block(ast.scope, true)
    scope.enter_block(ast.scope)
    local body, _, lastline = parse_opt_chunk(ast, ls, line, "TK_repeat")
    lex_match(ls, "TK_until", "TK_repeat", line)
    local cond = expr(ast, ls)
    scope.leave_block(ast.scope)
    scope.leave_block(ast.scope)
    return ast:repeat_stmt(cond, body, line, lastline)
end
local parse_label
parse_label = function(ast, ls)
    ls.step()
    local name = lex_str(ls)
    lex_check(ls, "::")
    return ast:label_stmt(name, ls.line)
end
local parse_goto = function(ast, ls)
    local line = ls.line
    local name = lex_str(ls)
    return ast:goto_stmt(name, line)
end
local parse_stmt
parse_stmt = function(ast, ls)
    local line = ls.line
    local stmt
    if ls.token == "TK_if" then
        stmt = parse_if(ast, ls, line)
    elseif ls.token == "TK_for" then
        stmt = parse_for(ast, ls, line)
    elseif ls.token == "TK_while" then
        stmt = parse_while(ast, ls, line)
    elseif ls.token == "TK_do" then
        stmt = parse_do(ast, ls, line)
    elseif ls.token == "TK_repeat" then
        stmt = parse_repeat(ast, ls, line)
    elseif ls.token == "->" or ls.token == "~>" then
        err_syntax(ls, "lambda must either be assigned or invoked")
    elseif ls.token == "TK_name" and ls.value == "var" then
        ls.step()
        stmt = parse_var(ast, ls, line)
    elseif ls.token == "TK_local" then
        err_symbol(ls)
        ls.step()
        stmt = parse_var(ast, ls, line)
    elseif ls.token == "TK_return" then
        stmt = parse_return(ast, ls, line)
        return stmt, true
    elseif ls.token == "TK_break" then
        ls.step()
        stmt = ast:break_stmt(line)
        return stmt, not LJ_52
    elseif ls.token == "::" then
        stmt = parse_label(ast, ls)
    elseif ls.token == "TK_goto" then
        if LJ_52 or ls.next() == "TK_name" then
            ls.step()
            stmt = parse_goto(ast, ls)
        end
    end
    if not stmt then
        stmt = parse_call_assign(ast, ls)
    end
    return stmt, false
end
local parse_chunk = function(ast, ls)
    local skip_ends = function(ls)
        while ls.token == ";" or ls.token == "TK_end" do
            err_symbol(ls)
            ls.step()
        end
        lex_opt(ls, "TK_newline")
    end
    local firstline = ls.line
    local stmt, islast = nil, false
    local body = {}
    while not islast and not EndOfChunk[ls.token] do
        stmted = ls.line
        skip_ends(ls)
        stmt, islast = parse_stmt(ast, ls)
        body[#body + 1] = stmt
        skip_ends(ls)
        if stmted == ls.line then
            if ls.token ~= "TK_eof" and ls.token ~= "TK_dedent" and ls.next() ~= "TK_eof" then
                err_instead(ls, "only one statement allowed per line. %s expected", ls.astext("TK_newline"))
            end
        end
    end
    return body, firstline, ls.line
end
parse_opt_chunk = function(ast, ls, line, match_token)
    local body = {}
    if lex_indent(ls) then
        body = parse_chunk(ast, ls)
        if not lex_dedent(ls) then
            err_instead(ls, "%s expected to end %s at line %d", ls.astext("TK_dedent"), ls.astext(match_token), line)
        end
    else
        if not EndOfChunk[ls.token] and not NewLine[ls.token] and not EndOfFunction[ls.token] then
            body[1] = parse_stmt(ast, ls)
        end
        if not EndOfChunk[ls.token] and not NewLine[ls.token] and not EndOfFunction[ls.token] then
            err_instead(ls, "only one statement may stay near %s. %s expected", ls.astext(match_token), ls.astext("TK_newline"))
        elseif EndOfFunction[ls.token] then
            lex_opt(ls, ";")
        end
    end
    return body
end
parse_block = function(ast, ls, line, match)
    scope.enter_block(ast.scope)
    local chunk = parse_opt_chunk(ast, ls, line, match)
    scope.leave_block(ast.scope)
    return chunk
end
local parse_params = function(ast, ls)
    local args = {}
    if ls.token ~= "->" and ls.token ~= "~>" then
        repeat
            if ls.token == "TK_name" or not LJ_52 and ls.token == "TK_goto" then
                local name = lex_str(ls)
                args[#args + 1] = ast:var_declare(name)
            elseif ls.token == "..." then
                ls.step()
                ast.scope.varargs = true
                args[#args + 1] = ast:expr_vararg()
                break
            else
                err_instead(ls, "parameter expected for %s", ls.astext("->"))
            end
        until not lex_opt(ls, ",")
    end
    if ls.token == "->" then
        ls.step()
        return false, args
    elseif ls.token == "~>" then
        if ast.scope.varargs then
            err_syntax(ls, "cannot curry variadic parameters with `~>`")
        end
        if #args < 2 then
            err_syntax(ls, "at least 2 parameters needed with `~>`")
        end
        ls.step()
        return true, args
    end
    err_expect(ls, "->")
end
parse_body = function(ast, ls, line)
    ast.scope = scope.begin_func(ast.scope)
    local curry, args = parse_params(ast, ls)
    local body = parse_opt_chunk(ast, ls, line, "->")
    ast.scope = scope.end_func(ast.scope)
    return curry, args, body, ast.scope.varargs
end
local parse = function(ls)
    ls.step()
    lex_opt(ls, "TK_newline")
    local ast = tree.New()
    ast.scope = scope.begin_func(nil)
    ast.scope.varargs = true
    local chunk, _, lastline = parse_chunk(ast, ls)
    ast.scope = scope.end_func(ast.scope)
    assert(ast.scope == nil)
    if ls.token ~= "TK_eof" then
        err_syntax(ls, "code should end. unexpected extra " .. ls.astext(ls.token))
    end
    return ast:chunk(chunk, ls.chunkname, 0, lastline)
end
return parse