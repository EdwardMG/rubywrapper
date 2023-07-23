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

  class Relation
    attr_accessor :klass, :clause_groups, :clause_cursor, :_ranges, :all_rows, :pred_mem

    def initialize klass:, clause_groups: [], ranges: [], all_rows: nil, pred_mem: nil
      @klass = klass
      @clause_groups = clause_groups
      @clause_cursor = 0
      @_ranges = ranges # need to differentiate the user facing ranges setter method from the data
      @all_rows = all_rows ? all_rows : klass.all
      @pred_mem = pred_mem
    end

    def method_missing(method, *args, &block)
      if Array.respond_to? method
        to_a.send(method, *args, &block)
      else
        super(method, *args, &block)
      end
    end

    def to_a
      rows = []
      if _ranges.length > 0
        _ranges.each do |range|
          rows.concat all_rows[range]
        end
      else
        rows = all_rows
      end

      if @clause_groups.length > 0
        rows.select do |row|
          @clause_groups.any? do |clause| # OR together each group
            clause.all? do |predicate| # AND together each clause
              predicate.call(row)
            end
          end
        end
      else
        rows
      end
    end

    def ranges(*rs)
      Relation.new klass: self, ranges: rs, all_rows: to_a
    end

    def where(hash=nil)
      if hash
        clause_groups[clause_cursor] = [] unless clause_groups[clause_cursor]
        clause_groups[clause_cursor] << -> (row) { hash.map {|k, v| row.send(k) == v}.all? true }
      else
        pred_mem = :where
      end

      if pred_mem == :not
        negate_last_predicate
        pred_mem = nil
      end
      self
    end

    def like(hash=nil)
      if hash
        clause_groups[clause_cursor] = [] unless clause_groups[clause_cursor]
        clause_groups[clause_cursor] << -> (row) { hash.map {|k, v| row.send(k)&.match? v}.all? true }
      else
        pred_mem = :like
      end

      if self.pred_mem == :not
        negate_last_predicate
        # it's funny how rarely this comes up in ruby, but setters called
        # WITHIN a class MUST use self. This behaviour does not mirror
        # getters. I wonder why this was necessary. I guess if this were not
        # the case, then you could accidentally set an instance variable when
        # you meant to create an local one, and this confusing behaviour was
        # simply the lesser of two evils without wanting to require self. for
        # all getters
        self.pred_mem = nil
      end
      self
    end

    def or
      self.clause_cursor += 1
      self
    end

    def not(hash=nil)
      if pred_mem
        # add the memorized predicate to the last clause group
        send pred_mem, hash
        self.pred_mem = nil

        negate_last_predicate
      else # we will negate the next predicate
        self.pred_mem = :not
      end
      self
    end

    def pred_mem=(o)
      @pred_mem = o
    end

    def negate_last_predicate
      predicate = clause_groups.last.last
      clause_groups.last[-1] = -> (row) { !predicate.call(row) }
    end

    def in_buffer
      if klass.method_defined? :bnum
        where(bnum: $curbuf.number)
      else
        raise "#{klass} does not support bnum"
      end
    end
  end

  def self.included(includer_klass) = includer_klass.extend ClassMethods

  module ClassMethods

    def in_buffer
      if method :bnum
        where(bnum: $curbuf.number)
      else
        raise "#{klass} does not support bnum"
      end
    end

    def ranges(*rs)
      Relation.new klass: self, ranges: rs
    end

    def where(hash=nil)
      if hash
        @relation = Relation.new(
          klass: self,
          clause_groups: [[-> (row) { hash.map {|k, v| row.send(k) == v}.all? true }]]
        )
      else
        @relation = Relation.new(
          klass: self,
          pred_mem: :where
        )
      end
    end

    def like(hash=nil)
      if hash
        @relation = Relation.new(
          klass: self,
          clause_groups: [[-> (row) { hash.map {|k, v| row.send(k)&.match? v}.all? true }]]
        )
      else
        @relation = Relation.new(klass: self, pred_mem: :like)
      end
    end

    def not
      @relation = Relation.new(
        klass: self,
        pred_mem: :not
      )
    end
  end
end
# }}}
# Examples: {{{

# Line.not.like(val: /Filterable/).to_a

# Line
#   .where(bnum: 7)
#   .ranges(0..20, -10..-1)
#   .not.like(val: /^\s*#/)
#   .ranges(0..20)
#   .to_a

# Line.where.not(bnum: 7).to_a

# Line.where(bnum: 7).ranges(0..20, -10..-1).like(val: /Filterable/).to_a

# Line.ranges(0..5).to_a

# Line.where(bnum: 7).first(30).like(val: /Relation/).to_a

# Line.where(bnum: 7).not.like(val: /focus/).to_a

# Line.all[0..10]
# Line.where(bnum: 7).not.like(val: /focus/).to_a
# Line.where(bnum: 7).like.not(val: /focus/).to_a

# Line
#   .where(bnum: 7)
#   .like(val: /^\s*class /)
#   .or.like(val: /^\s*def /)
#   .to_a

# Line.where(bnum: 7).like(val: /focus/).to_a

# Line.where(bnum: 1).like(val: /focus/).to_a

# }}}
# Mapping: {{{
class Mapping
  include Filterable
  # extend Filterable

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
  # extend Filterable

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

  def method_missing(method, *args, &block)
    if String.instance_method method
      r = val.send(method, *args, &block)
      self.val = r
    else
      super(method, *args, &block)
    end
  end

  # def gsub(*args)
  #   r = val.gsub(*args)
  #   self.val = r
  # end
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
  # extend Filterable

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
# Mapping.where(mode: 'i').first(2)
# Mapping.where(mode: 'n').length
# Mapping.where(mode: 'x').length
#
# SOMETHINGTOREPLACE
# SOMETHINGTOREPLACE
# SOMETHINGTOREPLACE
#

# Line.like(val: "SOMETHINGTOREPLACE").to_a.first.gsub(/SOMETHINGTOREPLACE/, "ohhh")

# Line.like(val: "SOMETHINGTOREPLACE").to_a.each {|l| l.gsub(/SOMETHINGTOREPLACE/, "ohhh") }

# Line.like(val: "SOMETHINGTOREPLACE").each &:downcase

# Line.like(val: "SOMETHINGTOREPLACE").in_buffer.to_a

# Line.in_buffer.to_a

#
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