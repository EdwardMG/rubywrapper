fu! s:setup()
ruby << EOF
require 'json'

module RubyWrapperUtil
  def quote(s) = "\"#{s}\""

  class Literal
    attr_accessor :val
    def initialize(val) = @val = val

    def inspect = "--LITERAL--#{val}--LITERAL--"
  end

  def lit(s) = Literal.new(s)

  def recur_to_vim v, count=0
    raise if count > 1000
    if v.is_a? Hash
      count+=1
      v.transform_values {|v| recur_to_vim v, count }
    elsif v.is_a? TrueClass
      "--LITERAL_TRUE--"
    elsif v.is_a? FalseClass
      "--LITERAL_FALSE--"
    elsif v.is_a? NilClass
      "--LITERAL_NULL--"
    elsif v.is_a? Array
      v.map {|e| recur_to_vim e, count}
    elsif v.is_a? Literal
      v.inspect
    else
      v
    end
  end

  def to_vim v, recurring=false
    if v.is_a? String
      quote v
    elsif v.is_a? Hash
      v = recur_to_vim v
      v.to_json
        .gsub(/"--LITERAL_TRUE--"/, " v:true")
        .gsub(/"--LITERAL_FALSE--"/, " v:false")
        .gsub(/"--LITERAL_NULL--"/, " v:null")
        .gsub(/"--LITERAL--/, "")
        .gsub(/--LITERAL--"/, "")
    elsif v.is_a? TrueClass
      "v:true"
    elsif v.is_a? FalseClass
      "v:false"
    elsif v.is_a? NilClass
      "v:null"
    elsif v.is_a? Array
      v.to_s
    elsif v.is_a? Literal
      v.val
    else
      v
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

  def self.method_missing(val, *args, &block)
    if val[-1] == "="
      Vim.command "let #{val}#{to_vim args.first}"
    else
      Vim.evaluate "#{val}"
    end
  end

  def self.[](val) = Vim.evaluate "#{val}"
  def self.[]=(val, o)
    Vim.command "let #{val}=#{to_vim o}"
  end
end
EOF
endfu

call s:setup()

