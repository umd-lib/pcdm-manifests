# frozen_string_literal: true

require 'errors'
require 'http_utils'
require 'iiif_base'

module IIIF
  module Fcrepo
    UUID_REGEX = /^\h{8}-\h{4}-\h{4}-\h{4}-\h{12}$/
    OCR_FIELDS = %w[extracted_text__dps_txt extracted_text__txt].freeze
    HIGHLIGHT_PATTERN = %r{<b class="hl">([^<]*)</b>}
    COORD_PATTERN = /(\S+)\|(\S+)/

    # location of a repository resource
    # can be in 4 forms:
    # * uri: the fully qualified URI to the resource
    # * path: the full path to the resource inside the repo, without the leading slash
    # * prefixed: slashes in the full path replaced with colons, and "fcrepo:" prepended
    # * abbreviated: prefixed form, but with any pairtree sequences replaced with a "::"
    class Path
      include Errors

      def self.from_uri(uri, base_uri: nil)
        base_uri ||= Item::CONFIG.fetch(:fcrepo_url, '')
        repo_path = uri.delete_prefix(base_uri)
        new(repo_path)
      end

      def self.from_prefixed(prefixed_path)
        prefixed_path.delete_prefix(Item::PREFIX).gsub(':', '/')
      end

      def self.from_abbreviated(abbreviated_path) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
        segments = abbreviated_path.delete_prefix(Item::PREFIX).split(':', -1)
        last_index = segments.count - 1
        new(segments.each_with_index.map do |segment, index|
          # pass through non-empty segments
          # ignore empty final segments
          if segment.present? || index == last_index
            segment
          else
            # attempt to expand the abbreviation marker "::"
            # using the next segment in the path
            next_segment = segments[index + 1]
            if index + 1 >= last_index && next_segment == ''
              raise ArgumentError,
                    'Cannot end with abbreviation marker "::"'
            end
            unless UUID_REGEX.match?(next_segment.to_s.downcase)
              raise ArgumentError,
                    'Can only abbreviate UUID segments'
            end

            # scan the next segment 2 characters at a time
            # and take the first 4 to create the pairtree
            next_segment.scan(/../).take(4).join('/')
          end
        end.join('/'))
      rescue ArgumentError => e
        raise BadRequestError, "Unable to parse identifier \"#{Item::PREFIX}#{abbreviated_path}\": #{e.message}"
      end

      def initialize(path)
        @path = path.delete_prefix('/')
        # pass -1 to split to preserve empty segments at the end of the path
        @segments = @path.split('/', -1)
      end

      def to_string(prefix: '/', separator: '/')
        prefix + @segments.join(separator)
      end

      def to_prefixed(abbreviate: true)
        prefixed = to_string(prefix: Item::PREFIX, separator: ':')
        # remove the pairtree from the path if abbreviated
        abbreviate ? prefixed.gsub(/:(..):(..):(..):(..):\1\2\3\4/, '::\1\2\3\4') : prefixed
      end

      def to_abbreviated
        to_prefixed(abbreviate: true)
      end

      def to_uri(base_uri: nil)
        base_uri ||= Item::CONFIG.fetch(:fcrepo_url, '')
        base_uri + @path
      end

      def to_s
        @path
      end
    end

    # Manifest-able resource from fcrepo
    class Item < IIIF::Item # rubocop:disable Metrics/ClassLength
      include Errors
      include HttpUtils

      PREFIX = 'fcrepo:'
      CONFIG = IIIF_CONFIG.fetch(PREFIX.delete_suffix(':'), {}).with_indifferent_access
      SOLR_URL = CONFIG.fetch('solr_url', '')
      PREFERRED_FORMATS = %w[image/tiff image/jpeg image/png image/gif].freeze

      def image_base_uri
        CONFIG[:image_url]
      end

      MANIFEST_LEVEL = ['issue', 'letter', 'image', 'reel', 'archival record set'].freeze
      CANVAS_LEVEL = ['page'].freeze

      def initialize(local_id, query) # rubocop:disable Lint/MissingSuper
        @path = Path.from_abbreviated(local_id)
        @query = query
        @uri = @path.to_uri
      end

      def base_uri
        # base URI of the manifest resources
        "#{CONFIG[:manifest_url]}#{@path.to_prefixed(abbreviate: false)}/"
      end

      attr_reader :query

      def rdf_types
        model_field('rdf_type__curies')
      end

      def manifest_level?
        doc[:is_top_level]
      end

      def canvas_level?
        !doc[:is_top_level]
      end

      def doc
        return @doc if @doc

        response = http_get("#{SOLR_URL}select", q: "id:#{@uri.gsub(':', '\:')}", wt: 'json')
        doc = response.body['response']['docs'][0]
        raise NotFoundError, "No Solr document with id #{@uri}" if doc.nil?

        @doc = doc.with_indifferent_access
      end

      def manifest_id
        if canvas_level?
          Path.from_uri(doc[:page__member_of__uri]).to_prefixed(abbreviate: false)
        else
          Path.from_uri(@uri).to_prefixed(abbreviate: false)
        end
      end

      def get_preferred_image(image_docs)
        images_by_type = image_docs.index_by { |doc| doc[:file__mime_type__str] }
        PREFERRED_FORMATS.each do |mime_type|
          return images_by_type[mime_type] if images_by_type.key? mime_type
        end
        nil
      end

      def get_page(_doc, page_doc)
        IIIF::Page.new.tap do |page|
          page.uri = page_doc[:id]
          page.id = Path.from_uri(page.uri).to_prefixed(abbreviate: false)
          page.label = page_doc[:page__title__txt]
          page.image = get_image(page_doc[:page__has_file])
        end
      end

      # in Solr 6, subqueries return structures like this:
      # "images": [
      #   { "field1": "...", "field2": "..." },
      #   { "field1": "...", "field2": "..." }
      # ]
      # whereas in Solr 7+, they return structures like this:
      # "images": {
      #   "docs": [
      #     { "field1": "...", "field2": "..." },
      #     { "field1": "...", "field2": "..." }
      #   ]
      # }
      def get_subquery_docs(subquery_field)
        return subquery_field[:docs] if subquery_field.respond_to? :key?

        subquery_field
      end

      def get_image(images)
        image_doc = get_preferred_image(images)

        # NOTE: the more semantically correct solution to the problem of a
        # missing image would be to return an empty images array and let the
        # IIIF view handle displaying a placeholder. Unfortunately at this
        # time Mirador does not support empty images arrays, so we have
        # implemented the placeholder on the IIIF Presentation API side.
        return unavailable_image unless image_doc

        IIIF::Image.new.tap do |image|
          image.uri = image_doc[:id]
          # re-expand the path for image IDs that are destined for the image server
          # since it currently cannot process the shorthand pcdm::... notation
          image.id = Path.from_uri(image.uri).to_prefixed(abbreviate: false)
          image.width = image_doc[:image_width]
          image.height = image_doc[:image_height]
        end
      end

      def pages
        page_docs = doc[:page_uri_sequence__uris].map do |uri|
          model_field('has_member').select { |member| member[:id] == uri }.first
        end
        page_docs.map { |page_doc| get_page(doc, page_doc) }
      end

      def nav_date
        model_field('date__dt')
      end

      def license
        model_field('rights__same_as__uris').first
      end

      def attribution
        model_field('terms_of_use__value__txt')
      end

      def label
        model_field('title__txt')
      end

      def metadata
        [
          { 'label': 'Date', 'value': model_field('date__edtf') },
          { 'label': 'Edition', 'value': doc[:issue_edition] },
          { 'label': 'Volume', 'value': doc[:issue_volume] },
          { 'label': 'Issue', 'value': doc[:issue_issue] },
          { 'label': 'Bibliographic Citation', 'value': model_field('bibliographic_citation__txt') }
        ].reject { |item| item[:value].nil? }
      end

      def search_hit_list(page_id) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
        _, path_string = page_id.split(/:/, 2)
        path = Path.from_abbreviated(path_string)
        page_uri = path.to_uri
        Rails.logger.debug("Fetching hit highlights with source #{page_uri}")
        results = http_get("#{SOLR_URL}select", highlight_search_params).body
        annotation_list_uri = "#{list_uri(path.to_prefixed)}?q=#{encode(@query)}"

        docs = results['response']['docs']
        body = docs.select { |doc| doc['id'] == @uri }.first
        raise Errors::NotFoundError if body.nil?

        page_sequence = body['page_uri_sequence__uris']
        annotations = get_ocr_annotations(
          page_uri: page_uri,
          page_index: page_sequence.index(page_uri),
          snippets: results['highlighting'] || []
        )
        Rails.logger.debug("Found #{annotations.count} hit highlights with source #{page_uri}")
        annotation_list(annotation_list_uri, annotations)
      end

      def textblock_list(page_id) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
        _prefix, path_string = page_id.split(/:/, 2)
        path = Path.from_abbreviated(path_string)
        page_uri = path.to_uri
        Rails.logger.debug("Fetching annotations with source #{page_uri}")
        solr_params = {
          fq: ['rdf_type:oa\:Annotation', "annotation_source:#{page_uri.gsub(':', '\:')}"],
          wt: 'json',
          q: '*:*',
          fl: '*',
          rows: 100
        }
        res = http_get("#{SOLR_URL}select", solr_params)
        results = res.body
        coord_tag_pattern = /\|(\d+,\d+,\d+,\d+)/
        annotation_list_uri = list_uri(path.to_prefixed)

        docs = results['response']['docs']
        Rails.logger.debug("Found #{docs.count} annotations with source #{page_uri}")
        annotations = docs.map do |doc|
          annotation(
            id: "##{doc['resource_selector'][0]}",
            type: 'umd:articleSegment',
            motivation: 'sc:painting',
            body: text_body(
              text: doc['extracted_text'].gsub(coord_tag_pattern, '')
            ),
            target: specific_resource(
              full: doc['annotation_source'][0],
              selector: fragment_selector(doc['resource_selector'][0])
            )
          )
        end
        annotation_list(annotation_list_uri, annotations)
      end

      private

        def highlight_search_params # rubocop:disable Metrics/MethodLength
          {
            fq: ["id:#{@uri.gsub(':', '\:')}"],
            defType: 'edismax',
            q: @query,
            hl: true,
            'q.alt': '*:*',
            'qf': 'extracted_text__dps_txt',
            'hl.fl': 'extracted_text__dps_txt',
            'hl.snippets': 100,
            'hl.maxAnalyzedChars': 1_000_000,
            'hl.tag.pre': '<b class="hl">',
            'hl.tag.post': '</b>'
          }
        end

        def get_ocr_annotations(page_uri:, page_index:, snippets:) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
          [].tap do |annotations|
            count = 0
            OCR_FIELDS.each do |ocr_field|
              snippets.select { |_uri, fields| fields[ocr_field] }.each do |_uri, fields|
                fields[ocr_field].each do |text|
                  text.scan HIGHLIGHT_PATTERN do |hit|
                    # NOTE: need the [0] subscript since `scan()` with capture groups returns an iterator of arrays
                    # rather than single string values
                    # ALSO NOTE: if there are multiword matches, each word gets highlighted individually; if we wanted
                    # to change this, we would need to collapse the values and coordinates in the scan for the
                    # `COORD_PATTERN` into a single annotation for each hit
                    hit[0].scan COORD_PATTERN do |value, tag_string|
                      tags = Rack::Utils.parse_nested_query(tag_string)
                      if tags['n'].to_i == page_index
                        count += 1
                        annotations.push(
                          hit_highlight(
                            page_uri: page_uri,
                            value: value,
                            xywh: tags['xywh'],
                            id: format('#search-result-%03d', count)
                          )
                        )
                      end
                    end
                  end
                end
              end
            end
          end
        end

        def hit_highlight(page_uri:, value:, xywh:, id:)
          annotation(
            id: id,
            type: 'umd:searchResult',
            motivation: 'oa:highlighting',
            target: specific_resource(
              full: page_uri,
              selector: fragment_selector("xywh=#{xywh}")
            ),
            body: text_body(text: value)
          )
        end

        def model_prefix
          'object__'
        end

        def model_field(field)
          doc[model_prefix + field]
        end
    end
  end
end
