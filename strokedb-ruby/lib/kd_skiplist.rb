module StrokeDB
  
  #  k-dimensional skiplist, version 2 
  # (according to Bradford G. Nickerson,
  #  Skip List Data Structures for Multidimensional Data)
  class KDSkiplist2
    
    def initialize
      @dimensions = []
      @lists = {}
    end
    
    # Inserts some object to a k-d list.
    # Relies on a #[] and #each method to access dimensions slots.
    def insert(object, __cheater_levels = nil)
      locations = {}
      
      # Allocation nodes per each dimension
      object.each do |k, v|
        node = Node.new(object[k], object)
        locations[k] = node
        # build dimensions dynamically
        unless @lists[k]
          debug "Creating list #{k.inspect}"
          @lists[k] = Skiplist.new()
          @dimensions.push k
        end
        @lists[k].insert(node.key, node, __cheater_levels ? __cheater_levels[k] : nil)
      end
      
      # Add references to all nodes to their copies in other dimensions
      object.each do |k1, v2|
        object.each do |k2, v2|
          locations[k1].pointers[k2] = locations[k2].skiplist_node_container unless k1 == k2 
        end
      end
    end
    
    # Find a subset of data in a multidimensional range.
    # If range is not given for some dimension, it is 
    # assumed to be (-∞; +∞)
    # Semi-infinite range can be applied in such way:
    #
    #   :slot => [nil, 42 ]  # => (-∞; 42]
    #   :slot => [42,  nil]  # => [42; +∞) 
    #   :slot => [nil, nil]  # => (-∞; +∞) 
    #
    # Thus, nil is not a valid value for a slot. 
    # Slot with a nil value is considered missing.
    # 
    # Examples:
    #  list.find(:x => 10..20,   :y => 30..70)    # ranges
    #  list.find(:x => [10, 20], :y => [30, nil]) # :y is within [30; +∞)
    #  list.find(:x => 10)                        # :x is within [10; 10]
    #
    # Options example:
    #  list.find({:__meta__ => 'Article', :author => '@#oleg-andreevs-uuid'}, 
    #            :order_by       => :created_at,
    #            :reversed_order => true,
    #            :limit          => 10)
    #
    # Returns an Array instance (empty when nothing found).
    # 
    def find(ranges, options = {})
      
      # 0. Optimization
      find_optimized(ranges, options) unless options.delete(:non_optimized)
      
      # 1. Prepare input: options and ranges
      order_by       = options.delete(:order_by)
      reversed_order = options.delete(:reversed_order)
      limit          = options.delete(:limit)
      offset         = options.delete(:offset)
      raise ":reversed_order, :limit and :offset are not supported!" if reversed_order || limit || offset
      # Convert single-values to ranges
      ranges.each {|d, v| ranges[d] = [v, v] unless Enumerable === v }
      ranges[order_by] ||= [ nil, nil ] if order_by
      results = []
      
      iterators = {} # current node in each key list
      hyperkey  = {} # current key values for each key ("k-d key")
      
      # 2. Determine location of the smallest element in each range (iterators)
      ranges.each do |dim, range|
        f = range.first
        iterators[dim] = f.nil? ? @lists[dim].first_node : @lists[dim].find_node(f){|k1,k0| k1 >= k0}
        # return if no data with slot k found
        unless iterators[dim] 
          debug "#{dim.inspect} not found in #{@lists[dim].inspect}. Range is #{range}"
          return []
        end
        hyperkey[dim] = iterators[dim].key
      end
      
      dimensions  = ranges.keys
      dimension   = dimensions.first
      dimension_i = 0
      i = iterators[dimension]
      # two utility vars for faster hyperkey <=> hyperrange.higher comparison
      is_greater_by_dimensions = []
      lower_keys_counter = ranges.size
      while lower_keys_counter > 0
        d_i = dimension_i
        in_range = false
        begin
          range = ranges[dimension]
          hyperkey[dimension] = kd = i.key
          debug "Testing #{kd.inspect} against #{range.inspect}"
          # update hyperkey comparison data
          higher  = (kd.nil? || range.higher?(kd))
          greater = is_greater_by_dimensions[dimension_i]
          if higher && !greater
            debug "Dimension #{dimension.inspect} iterator is outside the range #{range.inspect}. #{dimensions.size - lower_keys_counter - 1} dimensions left."
            lower_keys_counter += 1
            is_greater_by_dimensions[dimension_i] = true
          elsif !higher && greater
            debug "Dimension #{dimension.inspect} iterator returned to #{range.inspect} or lower. #{dimensions.size - lower_keys_counter + 1} dimensions left."
            lower_keys_counter -= 1
            is_greater_by_dimensions[dimension_i] = false
          end
          
          # if outside the range, try next item in current dimension
          if range.outside?(kd)
            debug "Dimension #{dimension.inspect} iterator #{kd.inspect} is outside the range #{range.inspect}. going next iterator."
            in_range = false
            i = i.next
            break
          end
          in_range = true
          debug "Switching dimension: #{dimension.inspect} => #{dimensions[(dimension_i + 1) % dimensions.size].inspect}."
          # Switch dimension on current node
          dimension_i = (dimension_i + 1) % dimensions.size
          dimension = dimensions[dimension_i]
          i = i.value.pointers[dimension]
        end until d_i == dimension_i
                
        if in_range 
          results << i.value.data # skiplist node is wrapped into kdnode
          i = i.next
        end
      end
      
      # results may contain duplicate values
      results.uniq 
    end
    
    # This is stub. Optimized version is in optimizations/find.rb
    def find_optimized(ranges, options)
      find(ranges, options.merge(:non_optimized => true))
      # TODO:
      # write_find_optimization!(ranges, options)
      # find_optimized(ranges, options)
    end
        
    def to_s
      "#<#{self.class.name} " +
      "@dimensions=#{@dimensions} " +
      "@lists=[#{@lists.join(", ")}]>"
    end
    
    def debug(msg)
      puts "Debug #{self.class}: #{msg}"
    end
    
    # Utility classes
    
    class Node
      attr_accessor :key, :data, :pointers, :skiplist_node_container
      def initialize(key, data)
        @key      = key
        @data     = data
        @pointers = {}
      end
      
      # Very special comparison operators.
      # nil is considered a signed infinity.
      # ( node < LowerBound )
      # ( node > HigherBound )
      # Compare with lower bound. value = nil is -infinity.
      def <(value)
        return false if value.nil?
        key < value
      end
      # Compare with higher bound. value = nil is +infinity.
      def >(value)
        return false if value.nil?
        key > value
      end
      
      def to_s
        "#<KDNode:#{@data.inspect}>"
      end
    end
      
  end
  
  
  #  k-dimensional skiplist, version 3
  class KDSkiplist3
    
  end
  
end

module Enumerable
  def higher?(key)
    !last.nil? && last < key 
  end
  def lower?(key)
    !first.nil? && first > key 
  end
  def outside?(key)
    higher?(key) or lower?(key)
  end
end

