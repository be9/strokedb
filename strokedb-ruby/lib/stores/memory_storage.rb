module StrokeDB
  class MemoryStorage < Storage
    
    def initialize(options = {})
    	@options = options.stringify_keys
      @container = SimpleSkiplist.new
    end
    
    def save_as_head!(document, timestamp)
      write(document.uuid, document, timestamp)
		end      
    
    def find(uuid, version=nil, opts = {})
      uuid_version = uuid + (version ? ".#{version}" : "")
      unless raw_doc = read(uuid_version)
        authoritative_source.find(uuid,version,opts) if authoritative_source
      else
        unless opts[:no_instantiation]
          doc = Document.from_raw(opts[:store], raw_doc.freeze) # FIXME: there should be a better source for store (probably)
          doc.extend(VersionedDocument) if version
          doc
        else
          raw_doc
        end
      end
    end
    
    def exists?(uuid,version=nil)
      uuid_version = uuid + (version ? ".#{version}" : "")
      !@container.find(uuid_version).nil?
    end

    def head_version(uuid, opts = {})
      if doc = find(uuid,nil, opts)
      	 doc.version
      end	 
    end
 		
 		def each(options = {})
      after = options[:after_timestamp]
      include_versions = options[:include_versions]
      @container.each do |key, value|
          next if after && (value[1] <= after)
          if uuid_match = key.match(/^#{UUID_RE}$/) || (include_versions && uuid_match = key.match(/#{UUID_RE}./) )
            yield value[0]
          end
      end
 		end

    def perform_save!(document, timestamp)
      uuid = document.uuid
      version = document.version
      document = document.to_raw
      uuid_version = uuid + (version ? ".#{version}" : "")
      write(uuid, document, timestamp)
      write(uuid_version, document, timestamp)
    end

    private

    def read(key)
      if record = @container.find(key)
      	 record.first
      end
    end
        
    def write(key, document, timestamp)
      @container.insert(key, [document, timestamp.counter])
    end
    
  end
end