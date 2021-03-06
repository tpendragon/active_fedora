module ActiveFedora
  class CleanConnection < SimpleDelegator
    def get(*args)
      result = __getobj__.get(*args) do |req|
        prefer_headers = Ldp::PreferHeaders.new(req.headers["Prefer"])
        prefer_headers.omit = prefer_headers.omit | omit_uris
        req.headers["Prefer"] = prefer_headers.to_s
      end
      CleanResult.new(result)
    end

    private

    def omit_uris
      [
        RDF::Fcrepo4.ServerManaged,
        RDF::Ldp.PreferContainment,
        RDF::Ldp.PreferEmptyContainer,
        RDF::Ldp.PreferMembership
      ]
    end

    class CleanResult < SimpleDelegator
      def graph
        @graph ||= clean_graph
      end

      private

      def clean_graph
        __getobj__.graph.delete(has_model_query)
        __getobj__.graph
      end

      def has_model_query
        [nil, ActiveFedora::RDF::Fcrepo::Model.hasModel, nil]
      end
    end
  end
end
