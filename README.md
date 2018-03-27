
Luaty is like a rudimentary [Moonscript](http://moonscript.org) that comes with a linter.

If [off-side syntax](https://en.wikipedia.org/wiki/Off-side_rule) is your thing, or you are lazy to type `end`, `then`, `do`, or you prefer compile-time to runtime error, then Luaty may suit your taste.

Luaty stands for *[Lua] with less [ty]ping*.


Builtin linter
---

During transpiling, Luaty checks and provides warning for:
  * unused variables
  * unused labels
  * assigning to undeclared (a.k.a global) variable
  * shadowing variables in the parent or same scope
  * duplicate keys in a table
  * number of expressions on the right side of assignment is more than the variables on the left

Lua code is generated regardless.

```
a = 1                     -- undeclared identifier a

var c, d = 1, 2, 4        -- assigning 3 values to 2 variables

var p = print
var p = 'p'               -- shadowing previous var p

var f = \z->
   var z = 10             -- shadowing previous var z

var tbl = {
   x = 1
   , x = 3                -- duplicate key 'x' in table
}
```


Differences from Lua
---

Luaty is skim on features. Aside from being indent based, most syntaxes of Lua are kept.
If you know Lua, you already knew most of Luaty.

Here goes the differences:

- Less or shorter keywords
  * no more `then`, `end`, `do`
  * `local` becomes `var`
  * `elseif` becomes `else if`
  * `[[` and `]]` are replaced with backquote \` which can be repeatable multiple times
  * `self` can be `@`

```
var x = false               -- `var` compiles to `local`
if not x
   print(`"nay"`)           -- `then` and `end` not needed, `"nay"` compiles to [["nay"]]
```

- Consistency preferred over sugar
  * function definition is always a [lambda expression](https://www.lua.org/manual/5.1/manual.html#2.5.9) using  `->` or `\arg1, arg2, ... ->`
  * function call always require parenthesis

```

function f(x)                       -- Error: use '->' instead of 'function'
\x -> print(x)                      -- Error: lambda expression by itself not allowed
(\x -> print(x))(3)                 -- Ok, immediately invoked lambda
var f = -> print(3)                 -- Ok, lambda with assignment statement

print 'a'                           -- Error: '=' expected instead of 'a'. This is valid in Lua
print('a')                          -- Ok, obviously
```

- Explicit prefered over implicit
  * colon `:` is not used. `@` specified as the first lambda parameter to mean `self`

```
var obj = {
   value = 3
   , foo = \@, k ->
      return k * @.value                    -- @ is equivalent to `self`
   , ['long-name'] = \@, n ->
      return n + @.value
}

var ret_o = -> return obj
assert(ret_o()['long-name'](@, 10) == 20)   -- @ *just works*, better than `:`

p(obj:foo(2))                               -- Error: ')' expected instead of ':'
assert(obj.foo(@, 2) == 6)                  -- Ok, compiles to obj:foo(2)
```

- table keys can be keywords

```
var z = {
   var = 7
   , local = 6
   , function = 5
   , if = \...-> return ...
   , goto = {true, false}
}

assert(z.var == 7)                           -- Ok, z.var works as in Lua
assert(11 == z.function + z.local)           -- Becomes z['function'] and z['local']
assert(z.if(z.goto)[2] == false)             -- Ditto
```





Quick start
---

Luaty only requires LuaJIT to run. 

With LuaJIT in your path, clone this repo, and cd into it.

To execute a Luaty source file, use
```
luajit lt.lua /path/to/source.lt
```

To transpile a Luaty *source.lt* file to *dest.lua*, use
```
luajit lt.lua -c /path/to/source.lt dest.lua
```
The output file is optional, and defaults to *source.lua*


To run tests in the [tests folder](https://github.com/gnois/luaty/tree/master/tests), use
```
luajit run-test.lua
```




The detailed indent (offside) rule
---

1. Either tabs or spaces can be used as indent, but not both in a single file.

2. Comments have no indent rule.

3. Blocks such as `if`, `for`, `while`, `do` and lambda expression `->` can have child statement(s).
   - A single child statement may choose to stay at the same line as its parent
   - Multiple child statements must start at an indented newline
```
if true p(1)                    -- Ok, p(1) is the only child statement of `if`
p(2)

if true p(1) p(2)               -- Error, two statements at the same line, `if` and p(2)

do                              -- Ok, multiple child statements are indented
   p(1)
   p(2)

print((-> return 'a', 1)())     -- Ok, immediately invoked one lined lambda expression

if x == nil for y = 1, 10 repeat until true else if x == 0 p(x) else if x p(x) else assert(not x)
                -- Ok, `repeat` is the sole children of `for`, which in turn is the sole children of `if`

```

4. A table constructor or function call can be indented, but the line having its closing brace/parenthesis must realign back to its starting indent level
```
var y = { 1
   ,
   2}                    -- Error: <dedent> expected

var z = { 1
   ,
   2
}                        -- Ok, last line realign back with a dedent

print(
   1,
   2
   , 3,                  -- commas can be anywhere
4, 5)                    -- Ok, last line realign back to `print(`

```

5. The multi-valued return statement in single-lined functions may cause ambiguity in certain cases. A semicolon `;` can be used to terminate single-lined function
```
print(pcall(\x-> return x, 10))                 -- multiple return values. Prints true, nil, 10

print(pcall(\x -> return x;, 10))               -- ok, single lined function ended with `;`. Prints true, 10

print(pcall(\x ->
   return x
, 10))                                          -- ok, function ended with dedent. Prints true, 10


var a, b, c = -> var d, e, f = 2, -> return -> return 9;;, 5;, 7
assert(b == 7)                                  -- `;` used to disambiguate multiple assignment/return values

```


See the [tests folder](https://github.com/gnois/luaty/tree/master/tests) for more code examples.




Acknowledgments
---

Luaty is modified from the excellent [LuaJIT Language Toolkit](https://github.com/franko/luajit-lang-toolkit).

Some of the tests are stolen and modified from official Lua test suit.
