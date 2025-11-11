# frozen_string_literal: true

puts "Ruby version: #{RUBY_VERSION}"

begin
  eval <<-RUBY
    def capture_with_anonymous_rest(*, **)
      yield(*, **)
    end
  RUBY
rescue SyntaxError => e
  puts "  #{e.message}"
end
