require 'errors'
require 'http_utils'
require 'iiif_base'

module IIIF
  module Fcrepo
    class Item < IIIF::Item
      include Errors
      include HttpUtils

      PREFIX = "fcrepo"
      CONFIG = Rails.configuration.iiif[PREFIX]
      SOLR_URL = CONFIG['solr_url']

      def image_base_uri
        CONFIG['image_url']
      end

      def get_formatted_id(path)
        PREFIX + ':' + path.gsub('/', '%2F')
      end

      def get_path(uri)
        path = uri[CONFIG['fcrepo_url'].length..uri.length]
        path.gsub('/', ':').gsub /:(..):(..):(..):(..):\1\2\3\4/, '::\1\2\3\4'
      end

      def path_to_uri(path)
        if m = path.match(/^([^:]+)::((..)(..)(..)(..).*)/)
          pairtree = m[3..6].join('/')
          path = "#{m[1]}/#{pairtree}/#{m[2]}"
        end
        CONFIG['fcrepo_url'] + path.gsub(':', '/')
      end

      MANIFEST_LEVEL = ['issue', 'letter', 'image', 'reel']
      CANVAS_LEVEL = ['page']

      def initialize(path, query)
        @path = path
        @query = query
        @uri = path_to_uri(@path)
      end

      def base_uri
        # base URI of the manifest resources
        CONFIG['manifest_url'] + get_formatted_id(@path) + '/'
      end

      def query
        @query
      end

      def component
        doc[:component]
      end

      def is_manifest_level?
        return false unless component
        MANIFEST_LEVEL.include? component.downcase
      end

      def is_canvas_level?
        return false unless component
        CANVAS_LEVEL.include? component.downcase
      end

      def doc
        return @doc if @doc

        response = http_get(SOLR_URL + "pcdm", q: "id:#{@uri.gsub(':', '\:')}", wt: 'json')
        doc = response.body["response"]["docs"][0]
        raise NotFoundError, "No Solr document with id #{@uri}" if doc.nil?
        @doc = doc.with_indifferent_access
      end

      def manifest_id
        if is_manifest_level?
          get_formatted_id(@uri)
        else
          get_formatted_id(get_path(doc[:page_issue]))
        end
      end

      def get_page(doc, page_doc)
        IIIF::Page.new.tap do |page|
          page.uri = page_doc[:id]
          page.id = get_formatted_id(get_path(page.uri))
          page.label = "Page #{page_doc[:page_number]}"

          doc[:images][:docs].each do |image_doc|
            if image_doc[:pcdm_file_of] == page.uri
              page.image = get_image(image_doc)
            end
          end
        end
      end

      def get_image(image_doc)
        IIIF::Image.new.tap do |image|
          image.uri = image_doc[:id]
          image.id = get_formatted_id(get_path(image.uri))
          image.width = image_doc[:image_width]
          image.height = image_doc[:image_height]
        end
      end

      def pages
        doc[:pages][:docs].map {|page_doc| get_page(doc, page_doc)}
      end

      def date
        doc[:display_date] || doc[:date].sub(/T.*/, '')
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

      def metadata
        citation = doc[:citation] ? doc[:citation].join(' ') : nil
        [
          {'label': 'Date', 'value': date},
          {'label': 'Edition', 'value': doc[:issue_edition]},
          {'label': 'Volume', 'value': doc[:issue_volume]},
          {'label': 'Issue', 'value': doc[:issue_issue]},
          {'label': 'Bibliographic Citation', 'value': citation}
        ].reject {|item| item[:value].nil? }
      end

      def search_hit_list(page_id)
        prefix, path = page_id.split /:/, 2
        page_uri = path_to_uri(path)
        solr_params = {
          'fq'             => ['rdf_type:oa\:Annotation', "annotation_source:#{page_uri.gsub(':', '\:')}"],
          'q'              => @query,
          'wt'             => 'json',
          'fl'             => '*',
          'hl'             => 'true',
          'hl.fl'          => 'extracted_text',
          'hl.simple.pre'  => '<em>',
          'hl.simple.post' => '</em>',
          'hl.method'      => 'unified',
        }
        res = http_get(SOLR_URL + "select", solr_params)
        ocr_field = 'extracted_text'
        annotations = []
        results = res.body
        highlight_pattern = /<em>([^<]*)<\/em>/
        coord_pattern = /(\d+,\d+,\d+,\d+)/
        annotation_list_uri = list_uri(get_formatted_id(path)) + '?q=' + encode(@query)
        count = 0

        docs = results['response']['docs']

        snippets = results["highlighting"] || []
        snippets.select { |uri, fields| fields[ocr_field] }.each do |uri, fields|
          body = docs.select { |doc| doc['id'] == uri }.first
          fields[ocr_field].each do |text|
            text.scan highlight_pattern do |hit|
              hit[0].scan coord_pattern do |coords|
                count += 1
                annotations.push(
                  annotation(
                    id: "#search-result-%03d" % count,
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

      def textblock_list(page_id)
        prefix, path = page_id.split /:/, 2
        page_uri = path_to_uri(path)
        solr_params = {
          'fq' => ['rdf_type:oa\:Annotation', "annotation_source:#{page_uri.gsub(':', '\:')}"],
          'wt' => 'json',
          'q' => '*:*',
          'fl' => '*',
          'rows' => 100,
        }
        res = http_get(SOLR_URL + "select", solr_params)
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
