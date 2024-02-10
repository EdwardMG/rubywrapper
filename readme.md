# Ruby Wrapper

## Requirements

Your vim must be compiled with `+ruby`

You can check by running `vim --version` at the terminal command line or `:version` from the ex command line.

## Abstract

A simple wrapper that provides `Ev` (evaluate) and `Ex` (Ex Command) modules
which forward method calls to built-in vim functions. `Var` is also provided
for accessing global variables, settings and registers.

### Ev examples

`ruby puts Ev.getline(1, 10)`

calls the vim function getline with arguments 1 and 10

`ruby puts Ev.getpos("'<")`

calls the vim function getpos with "'<".

`ruby Ev.input("Hello? ")`

It shouldn't be common you would want to do this, but for the sake of example if you need to pass something literally:

`echo map([1,2,3], { i, v -> v*2})` <- what it looks like in vimscript
`ruby puts Ev.map([1,2,3], Ev.lit('{ i, v -> v*2}'))` <- in ruby

Hashes will be converted to Dictionaries via `.to_json`, which should in most
cases be what you want. Ruby lamdas don't have a json representation, so they
won't convert to vimscript lamdas so don't try.

``` ruby
ruby << EOF
# note, popup_create is a vim8 function, not available in neovim
Ev.popup_create(
  'the text',
  {
    pos: 'botleft',
    border: [],
    padding: [0,1,0,1],
    close: 'click',
  }
)
EOF
```

It is possible to do something like

`ruby Ex.echo Var.quote(Var.a)`

but if you find yourself doing that, fall back to Vim.evaluate or Vim.command
(provided by +ruby) or just write vimscript, as you're not leveraging ruby much.

`ruby Vim.command "echo a"`


### Ex examples

`ruby Ex.edit("Hello.txt")`

would call the ex command "edit Hello.txt" (as though you had typed `:edit Hello.txt<CR>`

`ruby Ex.write`

and so on... Ex commands don't generally use spaces, so it would only ever be appropriate to pass a single string to an Ex.* method

### Var examples

Getting a global variable from vimscript

only globals

`let a=5` in vimscript

`ruby puts Var.a` in ruby

a global
`ruby puts Var["a"]`

a buffer local varialbe
`ruby puts Var["b:a"]`

a register
`ruby puts Var['@"']`

a setting
`ruby puts Var['&filetype']`

Or for assignment:

a global
`ruby Var.a="blah"`
`ruby Var["a"]="blah"`

a buffer local varialbe
`ruby puts Var["b:a"]='blah'`

a register
`ruby Var['@"']="blah"`

a setting
`ruby Var['&filetype']="blah"`

## Escaping Single Quotes

A helper is provided to make moving strings between ruby and vim less painful,
as vim differs from ruby in how single quoted and double quoted strings are interpretted.

``` ruby
'Bob\'s string'.sq
# "Bob''s string"
```

This is particularly useful when making use of vim's regular expressions, which
have many useful features not available in ruby.

## Purpose

Just make it slightly easier to make one off hacks in your vim configuration, or if you want to build a plugin with it, you should probably vendor it (copy and paste it into your project and change the module names) so people don't have to download this repo in addition to your plugin.


Read `:help ruby` for more information or try this template in a vimscript file.


``` vim
vim9script

def Setup()
ruby << EOF
  module MyNamespace
    def self.hello
      puts Ev.getline(1, 10).inspect
    end
  end
EOF
enddef

Setup()

nno <silent><nowait> ,d :ruby MyNamespace.hello<CR>
```

or in older vimscript

``` vim
fu! s:setup()
ruby << EOF
  module MyNamespace
    def self.hello
      puts Ev.getline(1, 10).inspect
    end
  end
EOF
endfu

call s:setup()

nno <silent><nowait> ,d :ruby MyNamespace.hello<CR>
```
