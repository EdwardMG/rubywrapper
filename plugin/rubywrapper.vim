fu! s:setup()
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
endfu

call s:setup()

