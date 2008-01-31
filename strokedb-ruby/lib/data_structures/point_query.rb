module StrokeDB
  # PointQuery is used to perform navigation to a single multidimensinal point.
  # Initializer accepts a hash of slots. Slots may have such value types: 
  #   "string"           scalar string value
  #   3.1415 (numeric)   numeric value
  #   :L                 lowest value
  #   :H                 highest value
  #
  # Example:
  #   PointQuery.new(:meta   => 'Article', 
  #                  :author => 'Oleg Andreev', 
  #                  :date   => :last)
  #
  class PointQuery
    attr_reader :slots
        
    def initialize(slots)
      @slots = slots
      @slots.each do |k, v|
        @slots[k] = "@\##{v.uuid}" if v.is_a? Document
      end
    end
  end
end
