# extracted from ActiveRecord (http://rubyforge.org/projects/activesupport/)

class Object
  unless respond_to?(:send!)
    # Anticipating Ruby 1.9 neutering send
    alias send! send
  end
end