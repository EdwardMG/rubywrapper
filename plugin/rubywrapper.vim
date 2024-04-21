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

module Ev
  include RubyWrapperUtil
  extend RubyWrapperUtil

  def self.method_missing(method, *args, &block)
    raise "called method_missing with to_vim" if method == :to_vim
    Vim.evaluate "#{method}(#{args.map {|a| to_vim a }.join(', ')})"
  end
end

module Ex
  include RubyWrapperUtil
  extend RubyWrapperUtil

  def self.method_missing(method, *args, &block) = Vim.command "#{method} #{args.join(' ')}"
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
        pos: 'topleft',
        scrollbar: 1
      }
    )
  end
end
EOF
endfu

call s:setup()

