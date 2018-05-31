--
-- Generated from type.lt
--
local ast = require("lua.ast")
local Tag = require("lua.tag")
local TType = Tag.Type
local Subst = {}
local subst = function(node, tvar, texp)
    assert(tvar.tag == TType.Var)
    local rule = Subst[node.tag]
    if rule then
        return rule(node, tvar, texp)
    end
    return node
end
Subst[TType.Var] = function(node, tvar, texp)
    if node.name == tvar.name then
        return texp
    end
    return node
end
Subst[TType.Func] = function(node, tvar, texp)
    local params, returns = {}, {}
    for i, p in ipairs(node.params) do
        params[i] = subst(p, tvar, texp)
    end
    for i, r in ipairs(node.returns) do
        returns[i] = subst(r, tvar, texp)
    end
    return ast.Type.func(params, returns, node.expr)
end
Subst[TType.Tbl] = function(node, tvar, texp)
    local typekeys = {}
    for i, tk in ipairs(node.typekeys) do
        typekeys[i] = {subst(tk[1], tvar, texp), tk[2]}
    end
    return ast.Type.tbl(typekeys, node.expr)
end
Subst[TType.Or] = function(node, tvar, texp)
    local left = subst(node.left, tvar, texp)
    local right = subst(node.right, tvar, texp)
    return ast.Type["or"](left, right, node.expr)
end
Subst[TType.And] = function(node, tvar, texp)
    local left = subst(node.left, tvar, texp)
    local right = subst(node.right, tvar, texp)
    return ast.Type["and"](left, right, node.expr)
end
Subst[TType.Index] = function(node, tvar, texp)
    return node
end
Subst[TType.Custom] = function(node, tvar, texp)
    return node
end
local Apply = {}
local apply = function(ty, subs)
    local rule = Apply[ty.tag]
    if rule then
        return rule(ty, subs)
    end
    return ty
end
Apply[TType.Var] = function(node, subs)
    return subs[node] or node
end
Apply[TType.Func] = function(node, subs)
    local params, returns = {}, {}
    for i, p in ipairs(node.params) do
        params[i] = apply(p, subs)
    end
    for i, r in ipairs(node.returns) do
        returns[i] = apply(r, subs)
    end
    return ast.Type.func(params, returns, node.expr)
end
Apply[TType.Tbl] = function(node, subs)
    local typekeys = {}
    for i, tk in ipairs(node.typekeys) do
        typekeys[i] = {apply(tk[1], subs), tk[2]}
    end
    return ast.Type.tbl(typekeys, node.expr)
end
Apply[TType.Or] = function(node, subs)
    local left = apply(node.left, subs)
    local right = apply(node.right, subs)
    return ast.Type["or"](left, right, node.expr)
end
Apply[TType.And] = function(node, subs)
    local left = apply(node.left, subs)
    local right = apply(node.right, subs)
    return ast.Type["and"](left, right, node.expr)
end
local Occur = {}
local occurs = function(tx, ty)
    local rule = Occur[tx.tag]
    if rule then
        return rule(tx, ty)
    end
    return false
end
Occur[TType.Func] = function(node, ty)
    for _, p in ipairs(node.params) do
        if occurs(p, ty) then
            return true
        end
    end
    for _, r in ipairs(node.returns) do
        if occurs(r, ty) then
            return true
        end
    end
    return false
end
Occur[TType.Tbl] = function(node, ty)
    for _, tk in ipairs(node.typekeys) do
        if occurs(tk[1], ty) then
            return true
        end
    end
    return false
end
Occur[TType.Or] = function(node, ty)
    return occurs(node.left, ty) or occurs(node.right, ty)
end
Occur[TType.And] = function(node, ty)
    return occurs(node.left, ty) or occurs(node.right, ty)
end
local extend = function(subs, tvar, texp)
    assert(tvar.tag == TType.Var)
    if occurs(tvar, texp) then
        print("Cannot infer recursive type ")
        return subs
    end
    for v, _ in pairs(subs) do
        subs[v] = subst(subs[v], tvar, texp)
    end
    subs[tvar] = texp
    return subs
end
local unify
local unify_tuple = function(subs, txs, tys, isparams)
    local taker, giver = " variables", " values"
    if isparams then
        taker, giver = " parameters", " arguments"
    end
    local i, n = 0, #txs
    while i < n do
        i = i + 1
        if tys[i] then
            subs = unify(subs, txs[i], tys[i])
        else
            print(i - 1 .. giver .. " supplied to " .. n .. taker)
            return subs
        end
    end
    n = #tys
    if i > 0 and i < n and not txs[i].varargs then
        print(n .. giver .. " supplied to " .. i - 1 .. taker)
    end
    return subs
end
local unify_func = function(subs, tx, ty)
    subs = unify_tuple(subs, tx.params, ty.params, true)
    return unify_tuple(subs, tx.returns, ty.returns, false)
end
local unify_tbl = function(subs, tx, ty)
    local keys, k = {}, 0
    for _, tkx in ipairs(tx.typekeys) do
        for __, tky in ipairs(ty.typekeys) do
            if tkx[2] == tky[2] then
                k = k + 1
                keys[k] = tkx[2]
                subs = unify(subs, tkx[1], tky[1])
            end
        end
    end
    for _, key in ipairs(keys) do
        for __, tk in ipairs(tx.typekeys) do
            if tk[2] and tk[2] ~= key then
                local tkey2 = ast.Type.new(tk[1])
                ast.nils(tkey2)
                subs = unify(subs, tk[1], tkey2)
            end
        end
        for __, tk in ipairs(ty.typekeys) do
            if tk[2] and tk[2] ~= key then
                local key2 = ast.Type.new(tk[1])
                ast.nils(key2)
                subs = unify(subs, tk[1], key2)
            end
        end
    end
    return subs
end
unify = function(subs, tx, ty)
    tx = apply(tx, subs)
    ty = apply(ty, subs)
    if tx.tag == TType.Var then
        if ty.tag == TType.Var then
            return subs
        end
        return extend(subs, tx, ty)
    end
    if ty.tag == TType.Var then
        return extend(subs, ty, tx)
    end
    if tx.tag == TType.Func and ty.tag == TType.Func then
        return unify_func(subs, tx, ty)
    end
    if tx.tag == TType.Tbl and ty.tag == TType.Tbl then
        return unify_tbl(subs, tx, ty)
    end
    if tx.tag == ty.tag then
        return subs
    end
    if tx.tag == TType.Any or ty.tag == TType.Any then
        return subs
    end
    if tx["nil"] and ty.tag == TType["nil"] then
        return subs
    end
    if ty["nil"] and tx.tag == TType["nil"] then
        return subs
    end
    print("Type mismatch :", tx.tag, ty.tag)
    return subs
end
return {apply = apply, unify = unify}
