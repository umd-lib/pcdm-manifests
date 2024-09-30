# frozen_string_literal: true

require 'errors'
require 'http_utils'
require 'iiif_base'

module IIIF
  module Fcrepo
    UUID_REGEX = /^\h{8}-\h{4}-\h{4}-\h{4}-\h{12}$/

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
        "#{CONFIG[:manifest_url]}#{@path.to_prefixed}/"
      end

      attr_reader :query

      def component
        doc[:component]
      end

      def rdf_types
        doc[:rdf_type]
      end

      def manifest_level?
        rdf_types&.include?('pcdm:Object') && !rdf_types.include?('pcdm:Collection')
      end

      def canvas_level?
        component && CANVAS_LEVEL.include?(component.downcase)
      end

      def doc # rubocop:disable Metrics/MethodLength
        return @doc if @doc

        response = http_get(
          "#{SOLR_URL}pcdm",
          q: "id:#{@uri.gsub(':', '\:')}",
          wt: 'json',
          fl: 'id,rdf_type,component,containing_issue,display_title,date,issue_edition,issue_volume,issue_issue,' \
            'rights,pcdm_members,pages:[subquery],citation,display_date,image_height,image_width,mime_type',
          rows: 1,
          'pages.q': '{!terms f=id v=$row.pcdm_members}',
          'pages.fq': 'component:Page',
          'pages.fl': 'id,display_title,page_number,pcdm_files,images:[subquery]',
          'pages.sort': 'page_number asc',
          'pages.rows': '1000',
          'pages.images.q': '{!terms f=id v=$row.pcdm_files}',
          'pages.images.fl': 'id,pcdm_file_of,image_height,image_width,mime_type,display_title,rdf_type',
          'pages.images.fq': 'mime_type:image/*',
          'pages.images.rows': 1000
        )
        doc = response.body['response']['docs'][0]
        raise NotFoundError, "No Solr document with id #{@uri}" if doc.nil?

        @doc = doc.with_indifferent_access
      end

      def manifest_id
        if canvas_level?
          Path.from_uri(doc[:containing_issue]).to_prefixed
        else
          Path.from_uri(@uri).to_prefixed
        end
      end

      def get_preferred_image(images)
        images_by_type = images.index_by { |doc| doc[:mime_type] }
        PREFERRED_FORMATS.each do |mime_type|
          return images_by_type[mime_type] if images_by_type.key? mime_type
        end
        nil
      end

      def get_page(_doc, page_doc)
        IIIF::Page.new.tap do |page|
          page.uri = page_doc[:id]
          page.id = Path.from_uri(page.uri).to_abbreviated
          page.label = "Page #{page_doc[:page_number]}"
          page.image = get_image(get_subquery_docs(page_doc[:images]))
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
        get_subquery_docs(doc[:pages]).map { |page_doc| get_page(doc, page_doc) }
      end

      def nav_date
        doc[:date]
      end

      def license
        doc[:rights].is_a?(Array) ? doc[:rights][0] : doc[:rights]
      end

      def attribution
        doc[:attribution]
      end

      def label
        doc[:display_title]
      end

      def metadata # rubocop:disable Metrics/AbcSize
        citation = doc[:citation] ? doc[:citation].join(' ') : nil
        display_date = doc[:display_date] || doc[:date]&.sub(/T.*/, '')
        [
          { 'label': 'Date', 'value': display_date },
          { 'label': 'Edition', 'value': doc[:issue_edition] },
          { 'label': 'Volume', 'value': doc[:issue_volume] },
          { 'label': 'Issue', 'value': doc[:issue_issue] },
          { 'label': 'Bibliographic Citation', 'value': citation }
        ].reject { |item| item[:value].nil? }
      end

      def search_hit_list(page_id) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
        _, path_string = page_id.split(/:/, 2)
        path = Path.from_abbreviated(path_string)
        page_uri = path.to_uri
        Rails.logger.debug("Fetching hit highlights with source #{page_uri}")
        solr_params = {
          fq: ['rdf_type:oa\:Annotation', "annotation_source:#{page_uri.gsub(':', '\:')}"],
          q: @query,
          wt: 'json',
          fl: '*',
          hl: 'true',
          'hl.fl': 'extracted_text',
          'hl.simple.pre': '<em>',
          'hl.simple.post': '</em>',
          'hl.method': 'unified'
        }
        res = http_get("#{SOLR_URL}select", solr_params)
        ocr_field = 'extracted_text'
        annotations = []
        results = res.body
        highlight_pattern = %r{<em>([^<]*)</em>}
        coord_pattern = /(\d+,\d+,\d+,\d+)/
        annotation_list_uri = "#{list_uri(path.to_prefixed)}?q=#{encode(@query)}"
        count = 0

        docs = results['response']['docs']

        snippets = results['highlighting'] || []
        snippets.select { |_uri, fields| fields[ocr_field] }.each do |uri, fields|
          body = docs.select { |doc| doc['id'] == uri }.first
          fields[ocr_field].each do |text|
            text.scan highlight_pattern do |hit|
              hit[0].scan coord_pattern do |coords|
                count += 1
                annotations.push(
                  annotation(
                    id: format('#search-result-%03d', count),
                    type: 'umd:searchResult',
                    motivation: 'oa:highlighting',
                    target: specific_resource(
                      full: body['annotation_source'][0],
                      selector: fragment_selector("xywh=#{coords[0]}")
                    )
                  )
                )
              end
            end
          end
        end
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
    end
  end
end
