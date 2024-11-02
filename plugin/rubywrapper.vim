fu! s:setup()
ruby << EOF
$VERBOSE = nil
require 'json'

class String
  # this monkey patch helps us create a string
  # that will behave similarly to vim's single quote string
  def sq
    self.gsub!(/'/, '\'\'')
    @sq = true
    self
  end

  # useful when passing stuff to U
  def uq
    "$'"+self+"'"
  end

  def single_quote? = !!@sq
  def lit           = RubyWrapperUtil::Literal.new(self)
end

class Array
  def fzf
    io = IO.popen('fzf -m', 'r+')
    begin
      stdout, $stdout = $stdout, io
      each { puts _1 } rescue nil
    ensure
      $stdout = stdout
    end
    io.close_write
    r = io.readlines.map(&:chomp)
    Ex.redraw!
    r
  end

  # sink is a string that when evaluated is a vim lambda
  def fzf2 sink
    Ev.send(
      "fzf#run",
      {
        'source': self,
        'sink': sink.lit,
        'options': '--with-nth=3.. --delimiter="\\:" --preview="bat --color=always --style=numbers --line-range={2}: {1}"'
      }
    )
  end

  def dump
    Ev.append('.', self.map { _1.gsub(/./,'') })
    Ex.redraw!
  end
end

module RubyWrapperUtil
  class Literal
    attr_accessor :val
    def initialize(val) = @val = val
    def inspect         = "--LITERAL--#{val}--LITERAL--"
  end

  def quote(s) = s.single_quote? ? "'#{s}'" : "\"#{s}\""
  def lit(s)   = Literal.new(s)

  def recur_to_vim v, count=0
    raise if count > 1000
    if v.is_a? Hash
      count+=1
      v.transform_values {|v| recur_to_vim v, count }
    elsif v.is_a? TrueClass  ; "--LITERAL_TRUE--"
    elsif v.is_a? FalseClass ; "--LITERAL_FALSE--"
    elsif v.is_a? NilClass   ; "--LITERAL_NULL--"
    elsif v.is_a? Array      ; v.map {|e| recur_to_vim e, count}
    elsif v.is_a? Literal    ; v.inspect
    else                     ; v
    end
  end

  # this whole stupid thing should just be replaced with rubyeval (a vimscript
  # function that parses strings of ruby data), except that we lose some
  # flexibility with Literal, which allows a ruby string in the shape of a vim
  # lambda to be allowed through. but that likely will never be useful
  def to_vim v
    if v.is_a? Hash
      v = recur_to_vim v
      v.to_json
        .gsub(/"--LITERAL_TRUE--"/, " v:true")
        .gsub(/"--LITERAL_FALSE--"/, " v:false")
        .gsub(/"--LITERAL_NULL--"/, " v:null")
        .gsub(/"--LITERAL--/, "")
        .gsub(/--LITERAL--"/, "")
    elsif v.is_a? String     ; quote v
    elsif v.is_a? TrueClass  ; "v:true"
    elsif v.is_a? FalseClass ; "v:false"
    elsif v.is_a? NilClass   ; "v:null"
    elsif v.is_a? Array      ; v.to_s
    elsif v.is_a? Literal    ; v.val
    else                     ; v
    end
  end
end

module U
  def self.method_missing(method, *args, &block) = `#{method} #{args.join(' ')}`.split("\n")
  def self.[](expr) = `#{expr}`.split("\n")
end

module Ev
  include RubyWrapperUtil
  extend RubyWrapperUtil

  def self.method_missing(method, *args, &block)
    raise "called method_missing with to_vim" if method == :to_vim
    Vim.evaluate "#{method}(#{args.map {|a| to_vim a }.join(', ')})"
  end
  def self.[](expr) = Vim.evaluate expr
end

module Rex
  include RubyWrapperUtil
  extend RubyWrapperUtil

  # first two args are presumed to be addr1 and addr2. if arguments are needed
  # to the command itself, add2 should be passed as nil
  def self.method_missing(method, *args, &block) = Vim.command "#{args[0..1].compact.join(',')}#{method} #{args[2..].join(' ')}"
  def self.[](command) = Vim.command command
end

# convenience for when you only have one addr
module Rex1
  include RubyWrapperUtil
  extend RubyWrapperUtil

  def self.method_missing(method, *args, &block) = Vim.command "#{args[0]}#{method} #{args[1..].join(' ')}"
  def self.[](command) = Vim.command command
end

module Ex
  include RubyWrapperUtil
  extend RubyWrapperUtil

  def self.method_missing(method, *args, &block) = Vim.command "#{method} #{args.join(' ')}"
  def self.[](command) = Vim.command command
end

module N
  include RubyWrapperUtil
  extend RubyWrapperUtil

  def self.method_missing(method, count="", &block) = Vim.command "normal! #{count}#{method}"
  def self.[](command) = Vim.command "normal! #{command}"
end

module Var
  include RubyWrapperUtil
  extend RubyWrapperUtil

  def self.method_missing(val, *args, &block) =
    val[-1] == "=" ? Vim.command("let #{val}#{to_vim args.first}")
                   : Vim.evaluate("#{val}")

  def self.[](val) = Vim.evaluate "#{val}"
  def self.[]=(val, o)
    Vim.command "let #{val}=#{to_vim o}"
  end
end

module Global
  include RubyWrapperUtil
  extend RubyWrapperUtil

  def self.method_missing(val, *args, &block) =
    val[-1] == "=" ? Vim.command("let g:#{val}#{to_vim args.first}")
                   : Vim.evaluate("g:#{val}")

  def self.[](val) = Vim.evaluate "g:#{val}"
  def self.[]=(val, o)
    Vim.command "let g:#{val}=#{to_vim o}"
  end
end

def source_ruby! *files, version: '1', root:
  target_path = root + "/#{version}.vim"

  File.open(target_path, 'w') do |f|
    f.puts "fu! s:Setup()"
    f.puts "ruby << EOF"
    files.uniq.each do |path|
      p = path.start_with?('/') ? path : (root + '/' + path)
      f.puts File.read(p)
    end
    f.puts "EOF"
    f.puts "endfu"
    f.puts "call s:Setup()"
  end

  # BUG: strangely I have to do this thought Vim.command
  # Ex.source target_path
  Vim.command "source " + target_path
end

def source_ruby *files, version:, root: nil
  target_path = root + "/#{version}.vim"

  if File.exist? target_path
    source_ruby! *files, version: version, root: root
  else
    Vim.command "source " + target_path
  end
end

class Selection
  attr_accessor :l, :r, :s, :e, :type
  Position = Struct.new(:bnum, :lnum, :cnum, :offset) do
    def cidx = cnum < 10000 ? cnum-1 : -1
    def lidx = lnum - 1
  end

  def initialize type
    raise 'use VisualSelection or MotionSelection instead'
  end

  def feed
    yield self
  end

  def replace
    outer.each.with_index do |line, i|
      if type == "line"
        line = yield line
      else
        line[l.cidx..r.cidx] = yield inner[i]
      end
      Ev.setline(l.lnum + i, line.sq)
    end
  end

  def replace_all
    if type == "line"
      result = yield outer.join(' ')
      Ev.setline(l.lnum, result.sq)
      i = r.lnum
      while i > l.lnum && i > 0
        Ev.deletebufline(Ev.bufname, i)
        i -= 1
      end
    else
      # fallback to normal replacement as replace all doesn't make sense
      outer.each.with_index do |line, i|
        line[l.cidx..r.cidx] = yield inner[i]
        Ev.setline(l.lnum + i, line.sq)
      end
    end
  end

  # BUG: works badly with multibyte characters.
  # the old hacky "qy would help at least with visual selection case
  def inner
    if l.lnum == r.lnum
      [ Ev.getline(l.lnum)[(l.cidx)..(r.cidx)] ]
    else
      lines = []
      i = l.lnum + 1

      if type == 'line'
        lines << Ev.getline(i)
      else
        lines << Ev.getline(l.lnum)[(l.cidx)..-1]
      end

      while i <= r.lnum
        if i == r.lnum
          if type == 'line'
            lines << Ev.getline(i)
          else
            lines << Ev.getline(i)[0..(r.cidx)]
          end
        else
          lines << Ev.getline(i)
        end
        i += 1
      end

      lines
    end
  end
  def outer = Ev.getline(l.lnum, r.lnum)
  def lines = Ev.getline(l.lnum, r.lnum)

  def lnums = l.lnum..r.lnum
end

class MotionSelection < Selection
  def initialize type
    @l = Position.new *Ev.getpos("'[")
    @r = Position.new *Ev.getpos("']")
    @type = type
  end
end

class VisualSelection < Selection
  def initialize
    @l = Position.new *Ev.getpos("'<")
    @r = Position.new *Ev.getpos("'>")
    @type =
      case Ev.visualmode
      when 'v'  ; 'char'
      when 'V'  ; 'line'
      when '' ; 'block'
      end
  end
end

module TextDebug
  @@msgs = []

  def self.clear = @@msgs = []
  def self.<<(msg)
    @@msgs << msg
    puts @@msgs
  end

  def self.puts msg
    msgs = []
    if !msg.is_a? Array
      msgs = [msg]
    else
      msgs = msg
    end
    msgs.map!(&:to_s)
    Ev.popup_close( $text_debug ) if $text_debug
    $text_debug = Ev.popup_create(
      msgs.last(20),
      {
        title: '',
        padding: [1,1,1,1],
        line: 1,
        col: 1,
        pos: 'topright',
        scrollbar: 1
      }
    )
  end
end

module SimpleNotify
  def self.clear
    Ev.popup_close( $simple_notify ) if $simple_notify
  end

  def self.puts msg
    Ev.popup_close( $simple_notify ) if $simple_notify
    $simple_notify = Ev.popup_create(
      msg,
      {title: '', padding: [1,1,1,1], pos: 'center' }
    )
  end
end

class EasyStorage
  require 'ostruct'
  require 'json'
  attr_accessor :p, :d, :loader
  def initialize p, loader=nil
    @p      = p
    @loader = loader || ->(l) { OpenStruct.new(JSON.parse(l)) }
    @d      = load
  end

  def load
    @d = []
    File.open(p).each_line {|l| @d << @loader[l] } if File.exist?(p)
    @d
  end

  def save
    File.write(p, d.map {|s| s.to_h.to_json }.join("\n"))
  end
end

class Cycler
  attr_accessor :els, :action, :cleanup, :alt_actions, :i, :out, :end
  # action is a lamda that takes a single el from els
  # cleanup is a lamda that runs on breaking cycle loop
  def initialize els, action, cleanup=->(){}, alt_actions={}
    @els     = els
    @action  = action
    @cleanup = cleanup
    @i       = 0
    @end     = @els.length-1
    @alt_actions = alt_actions
  end

  def n
    @i += 1
    @i = 0 if @i > @end
    @out = @action[@els[@i]]
  end

  def p
    @i -= 1
    @i = @end if @i < 0
    @out = @action[@els[@i]]
  end

  def cycle
    loop do
      c = Ev.getcharstr
      case c
      when 'j'; n
      when 'k'; p
      else
        if alt_actions[c]
          alt_actions[c].call(self)
        else
          cleanup.call @out
          break
        end
      end
    end
  end
end

class Mapping
  attr_accessor :original_mapping, :mode, :lhs

  def initialize mode, lhs
    @mode             = mode
    @lhs              = lhs
    # must use maplist and filter here because maparg prioritizes <buffer> local mappings
    @original_mapping = Ev.maplist.select { _1['mode'] == mode && _1['lhs'] == lhs && _1["buffer"] == 0 }.first
  end

  def set_rhs rhs, flags=''
    Ex["#{mode}no #{flags} #{lhs} #{rhs}"]
  end

  def restore
    if original_mapping
      Ev.mapset(original_mapping)
    else
      Ex["#{mode}unmap #{lhs}"]
    end
  end
end

module RubyEval
  def self.pipe_to_ruby_range s, e, cmd
    ls = Ev.getline(s, e)
    Vim.command "#{s},#{e}d"
    Ev.append(s-1, eval("ls.#{cmd}"))
  end

  def self.pipe_to_ruby s, e, cmd
    (s..e).each do |lnum|
      l = Vim::Buffer.current[lnum]
      Vim::Buffer.current[lnum] = eval("l.#{cmd}")
    end
  end

  def self.pipe_to_ruby_global qargs
    pattern = Regexp.new(qargs.match(/\/(.*)\//)[1])
    cmd = qargs.match(/\/.*\/\s(.+$)/)[1]
    Ev.getline(1, '$').each.with_index(1) do |l, lnum|
      if l.match? pattern
        Vim::Buffer.current[lnum] = eval("l.#{cmd}")
      end
    end
  end
end

class String
  def sm
    tap {|s| s.gsub! /def /, 'def self.' if start_with? /\s*def (?!self)/ }
  end
end

class Array
  def counter pat=/xx/
    pat = Regexp.new(pat) # in case we just pass a string
    i = 0
    each {|s|
      if s.match pat
        i += 1
        s.gsub! pat, i.to_s.rjust(3, '0')
      end
    }
  end

  def append_counter pat='log'
    pattern = Regexp.new(pat)
    i = 0
    each {|s|
      if s.match pattern
        i += 1
        s.gsub! pattern, pat+i.to_s.rjust(3, '0')
      end
    }
  end
end

class Slime
  attr_accessor :term_bufid

  def initialize
    @term_bufid = find_term_window_in_tab&.fetch "bufnr"
  end

  def active?
    !!@term_bufid
  end

  def send lines
    Ev.term_sendkeys(term_bufid, lines.join("\r").gsub('"', '\"')+"\r")
  end

  def find_term_window_in_tab
    Ev.gettabinfo(Ev.tabpagenr).first['windows']
      .flat_map { Ev.getwininfo(_1) }
      .find { _1["terminal"] == 1 }
  end
end
EOF
endfu

call s:setup()

command! -range -nargs=1 PipeToRubyRange  ruby RubyEval.pipe_to_ruby_range(<line1>, <line2>, <q-args>)
command!        -nargs=1 PipeToRubyGlobal ruby RubyEval.pipe_to_ruby_global(<q-args>)
command! -range -nargs=1 PipeToRuby       ruby RubyEval.pipe_to_ruby(<line1>, <line2>, <q-args>)

nno ,i :ruby U.ri(Ev.expand("<cword>")).dump<CR>
vno ,i :ruby U.ri(VisualSelection.new.inner).dump<CR>

" cabbrev pr PipeToRubyRange
" cabbrev pg PipeToRubyGlobal
" cabbrev p PipeToRuby

" Ev.append('.', U.ps.select {_1.include? 'vim'})
" Ev.append'.', U.ri('String.match')
" Ev.append'.', U.rg('class ')
" U.ri('String.upcase').dump
" U.man('sed').dump
" U.sed('-nE', '/pipe/p'.uq, Ev.expand('%')).dump
" U.grep('pipe', '. -R').dump
" U.rg('def ', Ev.expand('%'), "--type ruby").dump
" U['rg def | grep test'].dump

