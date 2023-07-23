" Preamble: {{{
vim9script

# The below shows some work to create an object oriented view of the running
# Vim environment, making it trivial to query and modify values
#
# It's all subject to change / being abandoned but seems cool so far

def Setup()
ruby << EOF
# }}}
# Filterable: {{{
module Filterable
  def where(hash)
    all.select do |m|
      hash.map {|k, v| m.send(k) == v}.all? true
    end
  end

  def like(hash)
    all.select do |m|
      hash.map {|k, v| m.send(k).to_s.match? v}.all? true
    end
  end
end
# }}}
# Examples: {{{

# Line.like(val: /focus/)
# [
#   Line(bnum: 1 lnum: 31 Line.like(val: /focus/),
#   Line(bnum: 1 lnum: 33 # "Line(bnum: 1 lnum: 25 Line.like(val: /focus/).pretty_inspect",
#   Line(bnum: 1 lnum: 34 # "Line(bnum: 1 lnum: 67   def focus",
#   Line(bnum: 1 lnum: 35 # "Line(bnum: 1 lnum: 113   def focus",
#   Line(bnum: 1 lnum: 36 # "Line(bnum: 1 lnum: 129 # Buffer.all.first.lines[20].focus",
#   Line(bnum: 1 lnum: 37 # "Line(bnum: 1 lnum: 162   def focus = Ex.buffer bnum",
#   Line(bnum: 1 lnum: 38 # "Line(bnum: 1 lnum: 212   def focus",
#   Line(bnum: 1 lnum: 39 # "Line(bnum: 1 lnum: 213     left.focus",
#   Line(bnum: 1 lnum: 86   def focus,
#   Line(bnum: 1 lnum: 134   def focus,
#   Line(bnum: 1 lnum: 152 # Buffer.all.first.lines[20].focus,
#   Line(bnum: 1 lnum: 187   def focus = Ex.buffer bnum,
#   Line(bnum: 1 lnum: 239   def focus,
#   Line(bnum: 1 lnum: 240     left.focus,
# ]

# }}}
# Mapping: {{{
class Mapping
  include Filterable
  extend Filterable

  attr_reader :lhs, :mode, :expr, :sid, :lnum, :noremap, :nowait, :rhs, :lhsraw, :abbr, :script, :buffer, :silent, :mode_bits, :scriptversion

  def self.all = Ev.maplist.map {|m| new m }

  def inspect = "Mapping(mode: #{mode} #{lhs}=#{rhs})"

  def initialize data
    @lhs           = data["lhs"]
    @mode          = data["mode"]
    @expr          = data["expr"]
    @sid           = data["sid"]
    @lnum          = data["lnum"]
    @noremap       = data["noremap"]
    @nowait        = data["nowait"]
    @rhs           = data["rhs"]
    @lhsraw        = data["lhsraw"]
    @abbr          = data["abbr"]
    @script        = data["script"]
    @buffer        = data["buffer"]
    @silent        = data["silent"]
    @mode_bits     = data["mode_bits"]
    @scriptversion = data["scriptversion"]
  end
end
# }}}
# Position: {{{
class Position
  attr_accessor :file, :lnum, :cnum, :screenoff, :bnum

  def initialize file: nil, lnum:, cnum:, screenoff: nil, bnum: nil
    @file = file
    @lnum = lnum
    @cnum = cnum
    @screenoff = screenoff
    @bnum = bnum
  end

  def focus
    Ex.buffer bnum
    Ev.cursor lnum, cnum
    Ex.normal! "zz"
  end

  def self.visual_start_pos = getcharpos "'<"
  def self.visual_end_pos = getcharpos "'>"

  def self.getcharpos expr
    Ev.getcharpos(expr).yield_self do |pos|
      bnum = pos[0] == 0 ? $curbuf.number : pos[0]
      new bnum: bnum, lnum: pos[1], cnum: pos[2], screenoff: pos[3]
    end
  end
end
# }}}
# Array: {{{
class Array
  def pretty_inspect
    map {|x| x.inspect }
  end
end
# }}}
# Line: {{{
class Line
  include Filterable
  extend Filterable

  attr_accessor :bnum, :lnum
  attr_reader :val

  def inspect = "Line(bnum: #{bnum} lnum: #{lnum} #{val}"

  def self.all
    Buffer.all.flat_map do |b|
      (1..b.linecount).map do |lnum|
        new bnum: b.bnum, lnum: lnum
      end
    end
  end

  def initialize bnum:, lnum:
    @bnum = bnum
    @lnum = lnum
    @val = Ev.getbufline(bnum, lnum).first
  end

  def focus
    Ex.buffer bnum
    Ev.cursor lnum, 1
    Ex.normal! "zz"
  end

  def val=(str)
    @val = str
    Ev.setbufline(
      bnum,
      lnum,
      val.gsub('"', '\"').gsub("'", "\'")
    )
  end
end
# }}}
# Examples: {{{

# Buffer.all.first.lines[20].focus

# Buffer
#   .all
#   .first
#   .lines[88]
#   .val = "hello"

# 'BLAHSLDK'

# line = Buffer
#   .all
#   .first
#   .lines[99]
# line.val = line.val.downcase

  # .val
# line.val = "line.val.upcase"

# Buffer.all.first
# Ev.getbufline(1, 1)
# ["fu! s:setup()"]

# }}}
# Buffer: {{{
class Buffer
  include Filterable
  extend Filterable

  attr_accessor :lnum, :bnum, :variables, :popups, :name, :changed, :lastused, :loaded, :windows, :hidden, :listed, :changedtick, :linecount

  def inspect = "Buffer(bnum: #{bnum} lnum: #{lnum} name: #{name} linecount: #{linecount})"

  def self.all = Ev.getbufinfo.map {|b| new b }

  def focus = Ex.buffer bnum

  def lines
    (1..linecount).map do |lnum|
      Line.new bnum: bnum, lnum: lnum
    end
  end

  def initialize data
    @lnum        = data["lnum"]
    @bnum        = data["bufnr"]
    @variables   = data["variables"]
    @popups      = data["popups"]
    @name        = data["name"]
    @changed     = data["changed"]
    @lastused    = data["lastused"]
    @loaded      = data["loaded"]
    @windows     = data["windows"]
    @hidden      = data["hidden"]
    @listed      = data["listed"]
    @changedtick = data["changedtick"]
    @linecount   = data["linecount"]
  end
end
# }}}
# Examples: {{{
# # valid but a little jank
# def visual_selection
#   tmp = Var['@a']
#   Ex.normal! 'gv"ay'
#   r = Var['@a']
#   Var['@a'] = tmp
#   r.force_encoding 'utf-8'
# end
# }}}
# Selection: {{{
class Selection
  attr_accessor :bnum, :left, :right

  def self.last
    left = Position.visual_start_pos
    new(bnum: left.bnum, left: left, right: Position.visual_end_pos)
  end

  def self.current = last

  def initialize bnum:, left:, right:
    @bnum = bnum
    @left = left
    @right = right
  end

  def focus
    left.focus
    Ex.buffer bnum
    Ev.cursor left.lnum, left.cnum
    Ex.normal! "zz"
  end

  def inspect
    "Selection(bnum: #{bnum}, lnum: #{left.lnum}, val: #{val})"
  end

  def lines
    (left.lnum..right.lnum).map do |lnum|
      Line.new(bnum: bnum, lnum: lnum)
    end
  end

  def val
    Ev.getline(left.lnum, right.lnum).tap do |lines|
      lines.map! {|l| l.force_encoding 'utf-8' } # or we'll have issues with multibyte
      if lines.length > 1
        lines[0] = lines[0][left.cnum-1..-1]
        lines[-1] = lines[-1][0..right.cnum-1]
        lines
      elsif lines.length > 0
        lines[0] = lines[0][left.cnum-1..right.cnum-1]
        lines
      else
        lines
      end
    end
  end

  def first_line = Ev.getline left.lnum
  def last_line  = Ev.getline right.lnum

  def ruby_eval
    r = ""
    val.each do |line|
      if line.start_with? /\s*\./
        r << line
      else
        r << "\n" << line
      end
    end
    eval(r)
  end

  def append_ruby_eval
    r = ruby_eval
    if r.inspect.length > 80
      if r.is_a? Array
        i = 0

        $curbuf.append right.lnum+i, "# ["
        i += 1

        r.each do |item|
          item.inspect.chars.each_slice(100) do |line|
            $curbuf.append right.lnum+i, "#   " + line.join('') + ","
            i += 1
          end
        end

        $curbuf.append right.lnum+i, "# ]"

      else
        r.inspect.chars.each_slice(100).with_index do |line, i|
          $curbuf.append right.lnum+i, "# " + line.join('')
        end
      end
    else
      $curbuf.append right.lnum, "# " + r.inspect
    end
  end

  def val=(o)
    v = val
    char_prior = left.cnum > 1 ? left.cnum-2 : left.cnum-1
    start_rem = first_line[0..char_prior]
    end_rem = last_line[right.cnum..-1]
    o.each_with_index do |replacement, i|
      # in the case we have more input lines than selection lines, add blank
      # lines
      if i >= v.length
        $curbuf.append left.lnum+i-1, ""
      end

      if i == 0 && i == o.length-1
        Line.new(bnum: bnum, lnum: left.lnum+i).val = start_rem + replacement + end_rem
      elsif i == 0
        Line.new(bnum: bnum, lnum: left.lnum+i).val = start_rem + replacement
      elsif i == o.length-1
        Line.new(bnum: bnum, lnum: left.lnum+i).val = replacement + end_rem
      else
        Line.new(bnum: bnum, lnum: left.lnum+i).val = replacement
      end
    end
  end
end
# }}}
# Examples: {{{

# Selection.current.val=["hello"]

# # "書く"
# # verbose and error prone
# def visual_selection
#   startp = Position.visual_start_pos
#   endp   = Position.visual_end_pos
#   Ev.getline(startp.lnum, endp.lnum).tap do |lines|
#     lines.map! {|l| l.force_encoding 'utf-8' } # or we'll have issues with multibyte
#     if lines.length > 1
#       lines[0] = lines[0][startp.cnum-1..-1]
#       lines[-1] = lines[-1][0..endp.cnum-1]
#       lines
#     elsif lines.length > 0
#       lines[0] = lines[0][startp.cnum-1..endp.cnum-1]
#       lines
#     else
#       lines
#     end
#   end
# end

# def run_in_ruby
#   r = ""
#   visual_selection.each do |line|
#     if line.start_with? /\s*\./
#       r << line
#     else
#       r << "\n" << line
#     end
#   end
#   $curbuf.append(Position.visual_end_pos.lnum, "# " + eval(r).inspect)
# end

# Mapping.all.map(&:mode).uniq
# # ["i", "c", "!", "v", "n", "o", "x", "t", " ", "s"]
# Mapping.where(mode: 'i').length
# # 142
# Mapping.where(mode: 'n').length
# # 798
# Mapping.where(mode: 'x').length
# # 73
# }}}
# Finish: {{{
EOF
enddef

Setup()

# }}}
# remaps: {{{
# vno gm :<C-u>ruby run_in_ruby<CR>
vno gm :<C-u>ruby Selection.current.append_ruby_eval<CR>

# }}}
