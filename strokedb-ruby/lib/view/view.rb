module StrokeDB
  View = Meta.new(:uuid => VIEW_UUID) do
    attr_accessor :map_with_proc
    attr_reader :reduce_with_proc

    on_initialization do |view|
      view.map_with_proc = proc {|doc, *args| doc } 
    end

    def reduce_with(&block)
      @reduce_with_proc = block
      self
    end

    def map_with(&block)
      @map_with_proc = block
      self
    end

    def emit(*args) 
      ViewCut.new(store, :view => self, :args => args, :timestamp_state => LTS.zero.counter).emit
    end

  end
  ViewCut = Meta.new(:uuid => VIEWCUT_UUID) do

    on_new_document do |cut|
      cut.instance_eval do
        if view.is_a?(View)
          @map_with_proc = view.map_with_proc
          @reduce_with_proc = view.reduce_with_proc
        end
      end
    end

    before_save do |cut|
      view = cut.view
      view.last_cut = cut if view[:last_cut].nil? or (cut[:previous] && view.last_cut == cut.previous)
      view.save!
    end


    def emit
      mapped = []
      store.each(:after_timestamp => timestamp_state, :include_versions => view[:include_versions]) do |doc| 
        mapped << @map_with_proc.call(doc,*args) 
      end
      documents = (@reduce_with_proc ? mapped.select {|doc| @reduce_with_proc.call(doc,*args) } : mapped).map{|d| d.is_a?(Document) ? d.extend(VersionedDocument) : d}
      ViewCut.new(store, :documents => documents, :view => view, :args => args, :timestamp_state => store.timestamp.counter, :previous => timestamp_state == 0 ? nil : self)
    end
    def to_a
      documents
    end
  end
end
