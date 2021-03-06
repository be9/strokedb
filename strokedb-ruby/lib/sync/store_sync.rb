module StrokeDB

  SynchronizationReport = Meta.new(:uuid => SYNCHRONIZATION_REPORT_UUID) do
    on_new_document do |report|
      report.conflicts = []
      report.added_documents = []
      report.fast_forwarded_documents = []
      report.non_matching_documents = []
    end
  end
  
  SynchronizationConflict = Meta.new(:uuid => SYNCHRONIZATION_CONFLICT_UUID) do
    def resolve!
      # by default, do nothing
    end
  end
  
  class Store
    def sync!(docs, _timestamp=nil)
      _timestamp_counter = timestamp.counter
      report = SynchronizationReport.new(self, :store_document => document, :timestamp => _timestamp_counter)
      existing_chain = {}
      docs.group_by {|doc| doc.uuid}.each_pair do |uuid, versions|
        doc = find(uuid)
        existing_chain[uuid] = doc.versions.all_versions if doc 
      end
      case _timestamp
      when Numeric
        @timestamp = LTS.new(_timestamp, timestamp.uuid) 
      when LamportTimestamp
        @timestamp = LTS.new(_timestamp.counter, timestamp.uuid)
      else
      end
      docs.each {|doc| save!(doc) unless exists?(doc.uuid, doc.version)}
      docs.group_by {|doc| doc.uuid}.each_pair do |uuid, versions|
        incoming_chain = find(uuid, versions.last.version).versions.all_versions
        if existing_chain[uuid].nil? or existing_chain[uuid].empty? # It is a new document
          added_doc = find(uuid, versions.last.version)
          save_as_head!(added_doc)
          report.added_documents << added_doc
        else
          begin
            sync = sync_chains(incoming_chain.reverse, existing_chain[uuid].reverse)
          rescue NonMatchingChains
            # raise NonMatchingDocumentCondition.new(uuid) # that will definitely leave garbage in the store (FIXME?)
            non_matching_doc = find(uuid)
            report.non_matching_documents << non_matching_doc
            next
          end
          resolution = sync.is_a?(Array) ? sync.first : sync
          case resolution
          when :up_to_date
            # nothing to do
          when :merge
            report.conflicts << SynchronizationConflict.create!(self, :document => find(uuid), :rev1 => sync[1], :rev2 => sync[2])
          when :fast_forward
            fast_forwarded_doc = find(uuid, sync[1].last)
            save_as_head!(fast_forwarded_doc)
            report.fast_forwarded_documents << fast_forwarded_doc
          else
            raise "Invalid sync resolution #{resolution}"
          end
        end
      end
      report.conflicts.each do |conflict|
        if resolution_strategy = conflict.document.meta[:resolution_strategy]
          conflict.metas << resolution_strategy
          conflict.save!
        end
        conflict.resolve!
      end
      report.save!
    end
    private
    
    include ChainSync
    
  end
end
