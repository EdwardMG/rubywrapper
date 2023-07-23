vim9script

# The below shows some work to create an object oriented view of the running
# Vim environment, making it trivial to query and modify values
#
# It's all subject to change / being abandoned but seems cool so far

def Setup()
ruby << EOF

module Filterable
  def where(hash)
    all.select do |m|
      hash.map {|k, v| m.send(k) == v}.all? true
    end
  end
end

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

class Position
  attr_accessor :file, :lnum, :cnum, :screenoff, :bnum

  def initialize file: nil, lnum:, cnum:, screenoff: nil, bnum: nil
    @file = file
    @lnum = lnum
    @cnum = cnum
    @screenoff = screenoff
    @bnum = bnum
  end

  def self.visual_start_pos = getcharpos "'<"
  def self.visual_end_pos = getcharpos "'>"

  def self.getcharpos expr
    Ev.getcharpos(expr).yield_self {|pos| new bnum: pos[0], lnum: pos[1], cnum: pos[2], screenoff: pos[3] }
  end
end

class Line
  include Filterable
  extend Filterable

  attr_accessor :bnum, :lnum
  attr_reader :val

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

# # valid but a little jank
# def visual_selection
#   tmp = Var['@a']
#   Ex.normal! 'gv"ay'
#   r = Var['@a']
#   Var['@a'] = tmp
#   r.force_encoding 'utf-8'
# end

# "書く"
# verbose and error prone
def visual_selection
  startp = Position.visual_start_pos
  endp   = Position.visual_end_pos
  Ev.getline(startp.lnum, endp.lnum).tap do |lines|
    lines.map! {|l| l.force_encoding 'utf-8' } # or we'll have issues with multibyte
    if lines.length > 1
      lines[0] = lines[0][startp.cnum-1..-1]
      lines[-1] = lines[-1][0..endp.cnum-1]
      lines
    elsif lines.length > 0
      lines[0] = lines[0][startp.cnum-1..endp.cnum-1]
      lines
    else
      lines
    end
  end
end

def run_in_ruby
  r = ""
  visual_selection.each do |line|
    if line.start_with? /\s*\./
      r << line
    else
      r << "\n" << line
    end
  end
  $curbuf.append(Position.visual_end_pos.lnum, "# " + eval(r).inspect)
end

# Mapping.all.map(&:mode).uniq
# # ["i", "c", "!", "v", "n", "o", "x", "t", " ", "s"]
# Mapping.where(mode: 'i').length
# # 142
# Mapping.where(mode: 'n').length
# # 798
# Mapping.where(mode: 'x').length
# # 73

EOF
enddef

Setup()

vno gm :<C-u>ruby run_in_ruby<CR>

