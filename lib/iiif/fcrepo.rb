# frozen_string_literal: true

require 'errors'
require 'http_utils'
require 'iiif_base'

module IIIF
  module Fcrepo
    PREFIX = 'fcrepo'
    CONFIG = IIIF_CONFIG.fetch(PREFIX, {}).with_indifferent_access
    UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.freeze

    # abbreviated path to a repository resource
    class Path
      include Errors

      def fcrepo_uri
        CONFIG.fetch(:fcrepo_url, '')
      end

      def self.from_uri(uri, base_uri: fcrepo_uri)
        repo_path = uri[base_uri.length..uri.length]
        # remove the pairtree from the path
        new(repo_path.gsub('/', ':').gsub(/:(..):(..):(..):(..):\1\2\3\4/, '::\1\2\3\4'))
      end

      def initialize(path)
        @path = path
        # pass -1 to split to preserve empty segments at the end of the path
        @segments = @path.split(':', -1)
        @last_index = @segments.count - 1
      end

      # reinsert the pairtree into the path
      def expanded
        @segments.each_with_index.map do |segment, index|
          # pass through non-empty segments
          # ignore empty final segments
          if segment.present? || index == @last_index
            segment
          else
            # attempt to expand the abbreviation marker "::"
            # using the next segment in the path
            expand_segment(next_segment(index), index)
          end
        end.join('/')
      rescue ArgumentError => e
        raise BadRequestError, "Unable to parse identifier containing \"#{@path}\": #{e.message}"
      end

      def to_prefixed(expand: false)
        path = expand ? expanded : @path
        PREFIX + ':' + path.gsub('/', '%2F')
      end

      def to_uri(base_uri: fcrepo_uri)
        base_uri + expanded
      end

      def to_s
        @path
      end

      private

        def next_segment(index)
          @segments[index + 1]
        end

        def expand_segment(segment, index)
          raise ArgumentError, 'Cannot end with abbreviation marker "::"' if index + 1 >= @last_index && segment == ''
          raise ArgumentError, 'Can only abbreviate UUID segments' unless UUID_REGEX.match?(segment.to_s.downcase)

          # scan the next segment 2 characters at a time
          # and take the first 4 to create the pairtree
          segment.scan(/../).take(4).join('/')
        end
    end

    # Manifest-able resource from fcrepo
    class Item < IIIF::Item # rubocop:disable Metrics/ClassLength
      include Errors
      include HttpUtils

      PREFIX = 'fcrepo'
      CONFIG = IIIF_CONFIG.fetch(PREFIX, {}).with_indifferent_access
      SOLR_URL = CONFIG.fetch('solr_url', '')
      PREFERRED_FORMATS = %w[image/tiff image/jpeg image/png image/gif].freeze

      def image_base_uri
        CONFIG[:image_url]
      end

      MANIFEST_LEVEL = ['issue', 'letter', 'image', 'reel', 'archival record set'].freeze
      CANVAS_LEVEL = ['page'].freeze

      def initialize(path, query)
        @path = Path.new(path)
        @query = query
        @uri = @path.to_uri
      end

      def base_uri
        # base URI of the manifest resources
        CONFIG[:manifest_url] + @path.to_prefixed + '/'
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
          SOLR_URL + 'pcdm',
          q: "id:#{@uri.gsub(':', '\:')}",
          wt: 'json',
          fl: 'id,rdf_type,component,containing_issue,display_title,date,issue_edition,issue_volume,issue_issue,' \
            'rights,pages:[subquery],citation,display_date,image_height,image_width,mime_type',
          rows: 1,
          'pages.q': '{!terms f=id v=$row.pcdm_members}',
          'pages.fq': 'component:Page',
          'pages.fl': 'id,display_title,page_number,images:[subquery]',
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
          get_formatted_id(get_path(doc[:containing_issue]))
        else
          get_formatted_id(@uri)
        end
      end

      def get_preferred_image(images)
        images_by_type = Hash[images.map { |doc| [doc[:mime_type], doc] }]
        PREFERRED_FORMATS.each do |mime_type|
          return images_by_type[mime_type] if images_by_type.key? mime_type
        end
        nil
      end

      def get_page(_doc, page_doc)
        IIIF::Page.new.tap do |page|
          page.uri = page_doc[:id]
          page.id = Path.from_uri(page.uri).to_prefixed
          page.label = "Page #{page_doc[:page_number]}"
          page.image = get_image(page_doc[:images])
        end
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
          # re-expand the path for image IDs that are destined for Loris
          # since it currently cannot process the shorthand pcdm::... notation
          image.id = Path.from_uri(image.uri).to_prefixed(expand: true)
          image.width = image_doc[:image_width]
          image.height = image_doc[:image_height]
        end
      end

      def unavailable_image
        IIIF::Image.new.tap do |image|
          image.uri = image_uri('static:unavailable', format: 'jpg')
          image.id = 'static:unavailable'
          image.width = 200
          image.height = 200
        end
      end

      def pages
        doc[:pages][:docs].map { |page_doc| get_page(doc, page_doc) }
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
        display_date = doc[:display_date] || (doc[:date]&.sub(/T.*/, ''))
        [
          { 'label': 'Date', 'value': display_date },
          { 'label': 'Edition', 'value': doc[:issue_edition] },
          { 'label': 'Volume', 'value': doc[:issue_volume] },
          { 'label': 'Issue', 'value': doc[:issue_issue] },
          { 'label': 'Bibliographic Citation', 'value': citation }
        ].reject { |item| item[:value].nil? }
      end

      def search_hit_list(page_id) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
        _, path = page_id.split(/:/, 2)
        page_uri = Path.new(path).to_uri
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
        res = http_get(SOLR_URL + 'select', solr_params)
        ocr_field = 'extracted_text'
        annotations = []
        results = res.body
        highlight_pattern = %r{<em>([^<]*)</em>}
        coord_pattern = /(\d+,\d+,\d+,\d+)/
        annotation_list_uri = list_uri(get_formatted_id(path)) + '?q=' + encode(@query)
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
        annotation_list(annotation_list_uri, annotations)
      end

      def textblock_list(page_id) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
        _prefix, path = page_id.split(/:/, 2)
        page_uri = Path.new(path).to_uri
        solr_params = {
          fq: ['rdf_type:oa\:Annotation', "annotation_source:#{page_uri.gsub(':', '\:')}"],
          wt: 'json',
          q: '*:*',
          fl: '*',
          rows: 100
        }
        res = http_get(SOLR_URL + 'select', solr_params)
        results = res.body
        coord_tag_pattern = /\|(\d+,\d+,\d+,\d+)/
        annotation_list_uri = list_uri(get_formatted_id(path))

        docs = results['response']['docs']
        annotations = docs.map do |doc|
          annotation(
            id: '#' + doc['resource_selector'][0],
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
