require 'thread'
require File.expand_path(File.dirname(__FILE__) + '/../util/class_optimization')

module StrokeDB
  # Implements a thread-safe skiplist structure.
  # Doesn't yield new skiplists
  class SimpleSkiplist
    include Enumerable
    
    DEFAULT_MAXLEVEL     = 32
    DEFAULT_PROBABILITY  = 1/Math::E
    
    attr_accessor :maxlevel, :probability
    
    def initialize(raw_list = nil, options = {})
      @maxlevel    = options[:maxlevel]    || DEFAULT_MAXLEVEL
      @probability = options[:probability] || DEFAULT_PROBABILITY
      @head        = raw_list && unserialize_list!(raw_list) || new_head
      @mutex       = Mutex.new
    end
    
    # Marshal API
    def marshal_dump
      raw_list = serialize_list(@head)
      {
        :options => {
          :maxlevel    => @maxlevel,
          :probability => @probability
          },
        :raw_list => raw_list
      }
    end
    
    def marshal_load(dumped)
      initialize(dumped[:raw_list], dumped[:options])
      self
    end
    
    def empty?
      !node_next(@head, 0)
    end
    
    def insert(key, value, __level = nil)
      @mutex.synchronize do
        newlevel = __level || random_level
        x = node_first
        level = node_level(x)
        update = Array.new(level)
        while level > 0
          level -= 1
          xnext = node_next(x, level)
          while node_compare(xnext, key) < 0
            x = xnext
            xnext = node_next(x, level)
          end
          update[level] = x
        end
        
        x = xnext
        
        # rewrite existing key
  	    if node_compare(x, key) == 0
  	      node_set_value!(x, value)
    	  # insert in a middle
    	  else
    	    level = newlevel
    	    newx = new_node(newlevel, key, value)
  	      while level > 0
  	        level -= 1
  	        node_insert_after!(newx, update[level], level)
          end
    	  end
    	end
    	self
  	end
  	
    # Find is thread-safe and requires no mutexes locking.
    def find_nearest_node(key)
      x = node_first
      level = node_level(x)
      while level > 0
        level -= 1
        xnext = node_next(x, level)
        while node_compare(xnext, key) <= 0
          x = xnext
          xnext = node_next(x, level)
        end
      end
      x
    end
    
    declare_optimized_methods(:InlineC, :find_nearest_node) do
      require 'rubygems'
      require 'inline'
      inline(:C) do |builder|
        builder.prefix %{
          static ID i_node_first, i_node_level;
          #define SS_NODE_NEXT(x, level) (rb_ary_entry(rb_ary_entry(x, 0), level))
          static int ss_node_compare(VALUE x, VALUE key)
          {
            if (x == Qnil) return 1;          /* tail */
            VALUE key1 = rb_ary_entry(x, 1);
            if (key1 == Qnil) return -1;      /* head */
            return rb_str_cmp(key1, key);
          }
        }
        builder.add_to_init %{
          i_node_first    = rb_intern("node_first");
          i_node_level    = rb_intern("node_level");
        }
        builder.c %{
          VALUE find_nearest_node_InlineC(VALUE key) 
          {
            VALUE x = rb_funcall(self, i_node_first, 0);
            long level = FIX2LONG(rb_funcall(self, i_node_level, 1, x));
            VALUE xnext;
            while (level-- > 0)
            {
              xnext = SS_NODE_NEXT(x, level);
              while (ss_node_compare(xnext, key) <= 0)
              {
                x = xnext;
                xnext = SS_NODE_NEXT(x, level);
              }
            }
            return x;
          }
        }
      end
    end
  
    def find(key)
      x = find_nearest_node(key)
      return node_value(x) if node_compare(x, key) == 0
      nil # nothing found
    end

    def find_C(key)
      x = find_nearest_node_C(key)
      return node_value(x) if node_compare(x, key) == 0
      nil # nothing found
    end
        
    def each
      x = node_next(node_first, 0)
      while x 
        yield(x)
        x = node_next(x, 0)
      end
      self
    end

    def self.from_hash(hash, options = {})
      from_a(hash.to_a, options)
    end
    
    def self.from_a(ary, options = {})
      sl = new(nil, options)
      ary.each do |kv|
        sl.insert(kv[0], kv[1])
      end
      sl
    end
        
    def to_a
      inject([]) do |arr, node|
        arr << node[1, 2]  # key, data
        arr
      end
    end
    
  private

    def serialize_list(head)
      head           = node_first.dup
      head[0]        = [ nil  ] * node_level(head)
      raw_list       = [ head ]
      prev_by_levels = [ head ] * node_level(head)
      x = node_next(head, 0)
      i = 1
      while x
        l = node_level(x)
        nx = node_next(x, 0)
        x  = x.dup                  # make modification-safe copy of node
        forwards = x[0]
        while l > 0                 # for each node level update forwards
          l -= 1
          prev_by_levels[l][l] = i  # set raw_list's index as a forward ref
          forwards[l] = nil         # nullify forward pointer (point to tail)
          prev_by_levels[l] = x     # set in a previous stack
        end
        raw_list << x               # store serialized node in an array
        x = nx                      # step to next node
        i += 1                      # increment index in a raw_list array
      end
      raw_list
    end
    
    # Returns head of an imported skiplist. 
    # Caution: raw_list is modified (thus the bang). 
    # Pass dup-ed value if you need.
    def unserialize_list!(raw_list)
      x = raw_list[0]
      while x != nil
        forwards = x[0]
        forwards.each_with_index do |rawindex, i|
          forwards[i] = rawindex ? raw_list[rawindex] : nil
        end
        # go next node
        x = forwards[0]
      end
      # return head
      raw_list[0]
    end
      
    # C-style API for node operations    
    def node_first
      @head
    end
    
    def node_level(x)
      x[0].size
    end
    
    def node_next(x, level)
      x[0][level]
    end
      
    def node_compare(x, key)
      return  1 unless x    # tail
      return -1 unless x[1] # head
      x[1] <=> key
    end
        
    def node_value(x)
      x[2]
    end
    
    def node_set_value!(x, value)
      x[2] = value
    end
    
    def node_insert_after!(x, prev, level)
      x[0][level] = prev[0][level]
      prev[0][level] = x
    end
    
    def new_node(level, key, value)
      [
        [nil]*level,
        key,
        value
      ]
    end
    
    def new_head
      new_node(@maxlevel, nil, nil)
    end

  	def random_level
  	  p = @probability
  	  m = @maxlevel
  		l = 1
  		l += 1 while rand < p && l < m
  		return l
  	end
    
  end
end

if __FILE__ == $0
  
  require 'benchmark'
  include StrokeDB
  
  puts "Serialization techniques"

  len = 2_000
  array = (1..len).map{ [rand(len).to_s]*2 }
  biglist = SimpleSkiplist.from_a(array)
  dumped = biglist.marshal_dump
#=begin
  Benchmark.bm(17) do |x|
    # First technique: to_a/from_a
    GC.start
    x.report("SimpleSkiplist#to_a          ") do
      biglist.to_a
      biglist.to_a
      biglist.to_a
      biglist.to_a
      biglist.to_a
    end
    GC.start
    x.report("SimpleSkiplist.from_a        ") do
      SimpleSkiplist.from_a(array)
      SimpleSkiplist.from_a(array)
      SimpleSkiplist.from_a(array)
      SimpleSkiplist.from_a(array)
      SimpleSkiplist.from_a(array)
    end
    
    # Another technique: Marshal.dump
    GC.start
    x.report("SimpleSkiplist#marshal_dump  ") do
      biglist.marshal_dump
      biglist.marshal_dump
      biglist.marshal_dump
      biglist.marshal_dump
      biglist.marshal_dump
    end
    GC.start
    x.report("SimpleSkiplist#marshal_load  ") do
      SimpleSkiplist.allocate.marshal_load(dumped.dup)
      SimpleSkiplist.allocate.marshal_load(dumped.dup)
      SimpleSkiplist.allocate.marshal_load(dumped.dup)
      SimpleSkiplist.allocate.marshal_load(dumped.dup)
      SimpleSkiplist.allocate.marshal_load(dumped.dup)
    end
  end
#=end
  puts
  puts "Find/insert techniques"
  
  Benchmark.bm(17) do |x|
    GC.start
    x.report("MRI SimpleSkiplist#find      ") do 
      100.times do
        key = rand(len).to_s
        biglist.find(key)
        biglist.find(key)
        biglist.find(key)
        biglist.find(key)
        biglist.find(key)
      end
    end
    GC.start
    x.report("MRI SimpleSkiplist#insert    ") do 
      100.times do
        key = rand(len).to_s
        biglist.insert(key, key)
        key = rand(len).to_s
        biglist.insert(key, key)
        key = rand(len).to_s
        biglist.insert(key, key)
        key = rand(len).to_s
        biglist.insert(key, key)
        key = rand(len).to_s
        biglist.insert(key, key)
      end
    end
    
    SimpleSkiplist.optimized_with(:InlineC) do 
      GC.start
      x.report("Inline C SimpleSkiplist#find ") do 
        100.times do
          key = rand(len).to_s
          biglist.find(key)
          biglist.find(key)
          biglist.find(key)
          biglist.find(key)
          biglist.find(key)
        end
      end
    end
  end
end

