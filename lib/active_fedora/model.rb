SOLR_DOCUMENT_ID = "id" unless defined?(SOLR_DOCUMENT_ID)

module ActiveFedora
  # = ActiveFedora
  # This module mixes various methods into the including class,
  # much in the way ActiveRecord does.  
  module Model 
    extend ActiveSupport::Concern

    included do
      class_attribute  :solr_query_handler
      self.solr_query_handler = 'standard'
    end
    
    # Takes a Fedora URI for a cModel and returns classname, namespace
    def self.classname_from_uri(uri)
      local_path = uri.split('/')[1]
      parts = local_path.split(':')
      return parts[-1].split(/_/).map(&:camelize).join('::'), parts[0]
    end

    # Takes a Fedora URI for a cModel, and returns a 
    # corresponding Model if available
    # This method should reverse ClassMethods#to_class_uri
    # @return [Class, False] the class of the model or false, if it does not exist
    def self.from_class_uri(uri)
      model_value, pid_ns = classname_from_uri(uri)
      raise "model URI incorrectly formatted: #{uri}" unless model_value

      unless class_exists?(model_value)
        logger.warn "#{model_value} is not a real class"
        return false
      end
      if model_value.include?("::")
        result = eval(model_value)
      else
        result = Kernel.const_get(model_value)
      end
      unless result.nil?
        model_ns = (result.respond_to? :pid_namespace) ? result.pid_namespace : ContentModel::CMODEL_NAMESPACE
        if model_ns != pid_ns
          logger.warn "Model class namespace '#{model_ns}' does not match uri: '#{uri}'"
        end
      end
      result
    end


    #
    # =Class Methods
    # These methods are mixed into the inheriting class.
    #
    # Accessor and mutator methods are dynamically generated based 
    # on the contents of the @@field_spec hash, which stores the 
    # field specifications recorded during invocation of has_metadata.
    #
    # Each metadata field will generate 3 methods:
    #
    #   fieldname_values
    #     *returns the current values array for this field
    #   fieldname_values=(val) 
    #     *store val as the values array. val 
    #     may be a single string, or an array of strings 
    #     (single items become single element arrays).
    #   fieldname_append(val)
    #     *appends val to the values array.
    module ClassMethods

      # Retrieve the Fedora object with the given pid and deserialize it as an instance of the current model
      # Note that you can actually pass a pid into this method, regardless of Fedora model type, and
      # ActiveFedora will try to parse the results into the current type of self, which may or may not be what you want.
      #
      # @param [String] pid of the object to load
      #
      # @example this will return an instance of Book, even if the object hydra:dataset1 asserts that it is a Dataset
      #   Book.load_instance("hydra:dataset1") 
      def load_instance(pid)
        ActiveSupport::Deprecation.warn("load_instance is deprecated.  Use find instead")
        find(pid)
      end
 

      
      # Returns a suitable uri object for :has_model
      # Should reverse Model#from_class_uri
      def to_class_uri(attrs = {})
        unless self.respond_to? :pid_suffix
          pid_suffix = attrs.has_key?(:pid_suffix) ? attrs[:pid_suffix] : ContentModel::CMODEL_PID_SUFFIX
        else
          pid_suffix = self.pid_suffix
        end
        unless self.respond_to? :pid_namespace
          namespace = attrs.has_key?(:namespace) ? attrs[:namespace] : ContentModel::CMODEL_NAMESPACE   
        else
          namespace = self.pid_namespace
        end
        "info:fedora/#{namespace}:#{ContentModel.sanitized_class_name(self)}#{pid_suffix}" 
      end
      
      # Returns an Array of objects of the Class that +find+ is being 
      # called on
      #
      # @param[String,Symbol,Hash] args either a pid or :all or a hash of conditions
      # @param [Hash] opts the options to create a message with.
      # @option opts [Integer] :rows when :all is passed, the maximum number of rows to load from solr
      # @option opts [Boolean] :cast when true, examine the model and cast it to the first known cModel
      def find(args, opts={}, &block)
        return find_one(args, opts[:cast]) if args.class == String
        return to_enum(:find, args, opts).to_a unless block_given?

        args = {} if args == :all
        find_each(args, opts) do |obj|
          yield obj
        end
      end

      def all(opts = {}, &block)
        find(:all, opts, &block)
      end


      # Yields each batch of solr records that was found by the find +options+ as
      # an array. The size of each batch is set by the <tt>:batch_size</tt>
      # option; the default is 1000.
      #
      # Returns a solr result matching the supplied conditions
      # @param[Hash] conditions solr conditions to match
      # @param[Hash] options 
      # @option opts [Array] :sort a list of fields to sort by 
      # @option opts [Array] :rows number of rows to return
      #
      # @example
      #  Person.find_in_batches('age_t'=>'21', {:batch_size=>50}) do |group|
      #  group.each { |person| puts person['name_t'] }
      #  end
      
      def find_in_batches conditions, opts={}
        opts[:q] = create_query(conditions)
        opts[:qt] = solr_query_handler
        #set default sort to created date ascending
        unless opts.include?(:sort)
          opts[:sort]=[ActiveFedora::SolrService.solr_name(:system_create,:date)+' asc'] 
        end

        batch_size = opts.delete(:batch_size) || 1000

        counter = 0
        begin
          counter += 1
          response = ActiveFedora::SolrService.instance.conn.paginate counter, batch_size, "select", :params => opts
          docs = response["response"]["docs"]
          yield docs
        end while docs.has_next? 
      end

      # Yields the found ActiveFedora::Base object to the passed block
      #
      # @param [Hash] conditions the conditions for the solr search to match
      # @param [Hash] opts 
      # @option opts [Boolean] :cast when true, examine the model and cast it to the first known cModel
      def find_each( conditions={}, opts={})
        find_in_batches(conditions, opts.merge({:fl=>SOLR_DOCUMENT_ID})) do |group|
          group.each do |hit|
            yield(find_one(hit[SOLR_DOCUMENT_ID], opts[:cast]))
          end
        end
      end


      # Returns true if the pid exists in the repository 
      # @param[String] pid 
      # @return[boolean] 
      def exists?(pid)
        inner = DigitalObject.find_or_initialize(self, pid)
        !inner.new?
      end

      #@deprecated
      def find_model(pid)
        ActiveSupport::Deprecation.warn("find_model is deprecated.  Use find instead")
        find(pid)
      end


      # Get a count of the number of objects from solr
      # Takes :conditions as an argument
      def count(args = {})
        q = search_model_clause ? [search_model_clause] : []
        q << "#{args[:conditions]}"  if args[:conditions]
        SolrService.query(q.join(' AND '), :raw=>true, :rows=>0)['response']['numFound']
      end

      #@deprecated
      #Sends a query directly to SolrService
      def solr_search(query, args={})
        ActiveSupport::Deprecation.warn("solr_search is deprecated and will be removed in the next release. Use SolrService.query instead")
        SolrService.instance.conn.query(query, args)
      end

      #  @deprecated
      #  If query is :all, this method will query Solr for all instances
      #  of self.type (based on active_fedora_model_s as indexed
      #  by Solr). If the query is any other string, this method simply does
      #  a pid based search (id:query). 
      #
      #  Note that this method does _not_ return ActiveFedora::Model 
      #  objects, but rather an array of SolrResults.
      #
      #  Args is an options hash, which is passed into the SolrService 
      #  connection instance.
      def find_by_solr(query, args={})
        ActiveSupport::Deprecation.warn("find_by_fields_by_solr is deprecated and will be removed in 5.0. Use find_with_conditions instead.")
        if query == :all
          escaped_class_name = self.name.gsub(/(:)/, '\\:')
          SolrService.query("#{ActiveFedora::SolrService.solr_name(:active_fedora_model, :symbol)}:#{escaped_class_name}", args) 
        elsif query.class == String
          escaped_id = query.gsub(/(:)/, '\\:')          
          SolrService.query("#{SOLR_DOCUMENT_ID}:#{escaped_id}", args) 
        end
      end

      # @deprecated
      # Find all ActiveFedora objects for this model that match arguments
      # passed in by querying Solr.  Like find_by_solr this returns a solr result.
      #
      # @param query_fields [Hash] field names and values to filter on (query_fields must be the solr_field_name for non-MetadataDatastream derived datastreams)
      # @param opts [Hash] specifies options for the solr query
      #
      #   options may include:
      # 
      #   :sort             => array of hash with one hash per sort by field... defaults to [{system_create=>:descending}]
      #   :default_field, :rows, :filter_queries, :debug_query,
      #   :explain_other, :facets, :highlighting, :mlt,
      #   :operator         => :or / :and
      #   :start            => defaults to 0
      #   :field_list       => array, defaults to ["*", "score"]
      #
      def find_by_fields_by_solr(query_fields,opts={})
        ActiveSupport::Deprecation.warn("find_by_fields_by_solr is deprecated and will be removed in 5.0")
        #create solr_args from fields passed in, needs to be comma separated list of form field1=value1,field2=value2,...
        escaped_class_name = self.name.gsub(/(:)/, '\\:')
        query = "#{ActiveFedora::SolrService.solr_name(:active_fedora_model, :symbol)}:#{escaped_class_name}" 
        
        query_fields.each_pair do |key,value|
          unless value.nil?
            solr_key = key
            #convert to symbol if need be
            key = key.to_sym if !class_fields.has_key?(key)&&class_fields.has_key?(key.to_sym)
            #do necessary mapping with suffix in most cases, otherwise ignore as a solr field key that activefedora does not know about
            if class_fields.has_key?(key) && class_fields[key].has_key?(:type)
              type = class_fields[key][:type]
              type = :string unless type.kind_of?(Symbol)
              solr_key = ActiveFedora::SolrService.solr_name(key,type)
            end
            
            escaped_value = value.gsub(/(:)/, '\\:')
            #escaped_value = escaped_value.gsub(/ /, '\\ ')
            key = SOLR_DOCUMENT_ID if (key === :id || key === :pid)
            query = key.to_s.eql?(SOLR_DOCUMENT_ID) ? "#{query} AND #{key}:#{escaped_value}" : "#{query} AND #{solr_key}:#{escaped_value}"  
          end
        end
      
        query_opts = {}
        opts.each do |key,value|
          key = key.to_sym
          query_opts[key] = value
        end
      
        #set default sort to created date ascending
        unless query_opts.include?(:sort)
          query_opts.merge!({:sort=>[ActiveFedora::SolrService.solr_name(:system_create,:date)+' asc']}) 
        else
          #need to convert to solr names for all fields
          sort_array =[]
        
          opts[:sort].collect do |sort|
            sort_direction = 'ascending'
            if sort.respond_to?(:keys)
              key = sort.keys[0]
              sort_direction = sort[key]
            else
              key = sort.to_s
            end
            sort_direction = sort_direction =~ /^desc/ ? 'desc' : 'asc'
            field_name = key
            
            if key.to_s =~ /^system_create/
              field_name = :system_create_date
              key = :system_create
            elsif key.to_s =~ /^system_mod/  
              field_name = :system_modified_date
              key = :system_modified
            end
         
            solr_name = field_name 
            if class_fields.include?(field_name.to_sym)
              solr_name = ActiveFedora::SolrService.solr_name(key,class_fields[field_name.to_sym][:type])
            end
            sort_array.push("#{solr_name} #{sort_direction}")
          end
        
          query_opts[:sort] = sort_array.join(",")
        end

        logger.debug "Querying solr for #{self.name} objects with query: '#{query}'"
        SolrService.query(query, query_opts) 
      end

      # Returns a solr result matching the supplied conditions
      # @param[Hash,String] conditions can either be specified as a string, or 
      # hash representing the query part of an solr statement. If a hash is 
      # provided, this method will generate conditions based simple equality
      # combined using the boolean AND operator.
      # @param[Hash] options 
      # @option opts [Array] :sort a list of fields to sort by 
      # @option opts [Array] :rows number of rows to return
      def find_with_conditions(conditions, opts={})
        #set default sort to created date ascending
        unless opts.include?(:sort)
          opts[:sort]=[ActiveFedora::SolrService.solr_name(:system_create,:date)+' asc'] 
        end
        SolrService.query(create_query(conditions), opts) 
      end

      def quote_for_solr(value)
        '"' + value.gsub(/(:)/, '\\:').gsub(/(\/)/, '\\/').gsub(/"/, '\\"') + '"'
      end
    
      # @deprecated
      def class_fields
        #create dummy object that is empty by passing in fake pid
        object = self.new()#{:pid=>'FAKE'})
        fields = object.fields
        #reset id to nothing
        fields[:id][:values] = []
        return fields
      end

      private 

      # Returns a solr query for the supplied conditions
      # @param[Hash] conditions solr conditions to match
      def create_query(conditions)
        conditions.kind_of?(Hash) ? create_query_from_hash(conditions) : create_query_from_string(conditions)
      end

      def create_query_from_hash(conditions)
        clauses = search_model_clause ?  [search_model_clause] : []
        conditions.each_pair do |key,value|
          unless value.nil?
            if value.is_a? Array
              value.each do |val|
                clauses << "#{key}:#{quote_for_solr(val)}"  
              end
            else
              key = SOLR_DOCUMENT_ID if (key === :id || key === :pid)
              escaped_value = quote_for_solr(value)
              clauses << (key.to_s.eql?(SOLR_DOCUMENT_ID) ? "#{key}:#{escaped_value}" : "#{key}:#{escaped_value}")
            end
          end
        end
        return "*:*" if clauses.empty?
        clauses.compact.join(" AND ")
      end

      def create_query_from_string(conditions)
        model_clause = search_model_clause
        model_clause ? "#{model_clause} AND (#{conditions})" : conditions
      end

      # Return the solr clause that queries for this type of class
      def search_model_clause
        unless self == ActiveFedora::Base
          return ActiveFedora::SolrService.construct_query_for_rel(:has_model, self.to_class_uri)
        end
      end

      # Retrieve the Fedora object with the given pid, explore the returned object, determine its model 
      # using #{ActiveFedora::ContentModel.known_models_for} and cast to that class.
      # Raises a ObjectNotFoundError if the object is not found.
      # @param [String] pid of the object to load
      # @param [Boolean] cast when true, cast the found object to the class of the first known model defined in it's RELS-EXT
      #
      # @example because the object hydra:dataset1 asserts it is a Dataset (hasModel info:fedora/afmodel:Dataset), return a Dataset object (not a Book).
      #   Book.find_one("hydra:dataset1") 
      def find_one(pid, cast=false)
        inner = DigitalObject.find(self, pid)
        af_base = self.allocate.init_with(inner)
        cast ? af_base.adapt_to_cmodel : af_base
      end
    end

    private 
    
      def self.class_exists?(class_name)
        klass = class_name.constantize
        return klass.is_a?(Class)
      rescue NameError
        return false
      end
    
  end
end