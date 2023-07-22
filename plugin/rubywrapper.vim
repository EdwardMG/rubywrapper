vim9script

def Setup()
ruby << EOF
module Ev
  require 'json'

  def self.quote(s) = "\"#{s}\""

  class Literal
    attr_accessor :val
    def initialize(val) = @val = val
  end

  def self.lit(s) = Literal.new(s)

  def self.method_missing(method, *args, &block)
    args = args.map do |a|
      if a.is_a? String
        quote a
      elsif a.is_a? Hash
        a.to_json
      elsif a.is_a? Array
        a.to_s
      elsif a.is_a? Literal
        a.val
      else
        a
      end
    end
    Vim.evaluate "#{method}(#{args.join(', ')})"
  end
end

module Ex
  def self.method_missing(method, *args, &block) = Vim.command "#{method} #{args.join(' ')}"
end
EOF
enddef

Setup()

# if for some ungodly reason you needed to use vim lambdas, eg calling a vimscript utility function
# echo map([1,2,3], { i, v -> v*2})
# nno <silent><nowait> ,d :ruby puts Ev.map([1,2,3], Ev.lit('{ i, v -> v*2}')).inspect<CR>

# other examples of Evaluate
# nno <silent><nowait> ,d :ruby puts Ev.getline(1, 10)<CR>
# nno <silent><nowait> ,d :ruby puts Ev.getpos("'<").inspect<CR>
# nno <silent><nowait> ,d :ruby Ev.input("Hello? ")<CR>

# Examples of Ex commands. You would only ever pass a single string
# nno <silent><nowait> ,d :ruby Ex.edit("Hello.txt")<CR>
# nno <silent><nowait> ,d :ruby Ex.write<CR>
