require 'faraday'
require 'faraday_middleware'

module FcrepoHelper
  extend ActiveSupport::Concern

  DEFAULT_PATH = 'pcdm?wt=json&q=id:'
  ID_PREFIX = "fcrepo:"
  FCREPO_URL = Rails.application.config.fcrepo_url
  IMAGE_URL = Rails.application.config.iiif_image_url
  MANIFEST_URL = Rails.application.config.iiif_manifest_url
  SOLR_URL = Rails.application.config.solr_url
  HTTP_CONN = Faraday.new(ssl: {verify: false}, request: {params_encoder: Faraday::FlatParamsEncoder}) do |faraday|
    faraday.response :json, content_type: /\bjson$/
    faraday.adapter Faraday.default_adapter
  end

  DEFAULT_IIIF_PARAMS = {
    region: 'full',
    size: 'full',
    rotation: 0,
    quality: 'default',
    format: 'jpg'
  }
  def iiif_image_uri(image, param={})
    uri = IMAGE_URL + image.id
    unless param.empty?
      p = DEFAULT_IIIF_PARAMS.merge(param)
      uri += "/#{p[:region]}/#{p[:size]}/#{p[:rotation]}/#{p[:quality]}.#{p[:format]}"
    end
    uri
  end

  def get_formatted_id(path)
    ID_PREFIX + path.gsub('/', '%2F')
  end

  def get_path(uri)
    path = uri[FCREPO_URL.length..uri.length]
    path.gsub('/', ':').gsub /:(..):(..):(..):(..):\1\2\3\4/, '::\1\2\3\4'
  end

  def path_to_uri(path)
    if m = path.match(/^([^:]+)::((..)(..)(..)(..).*)/)
      pairtree = m[3..6].join('/')
      path = "#{m[1]}/#{pairtree}/#{m[2]}"
    end
    FCREPO_URL + path.gsub(':', '/')
  end

  MANIFEST_LEVEL = ['issue', 'letter', 'image', 'reel']
  CANVAS_LEVEL = ['page']

  class FcrepoPage
    include ManifestHelper
    include FcrepoHelper
    attr_reader :id, :number, :image, :uri

    def initialize(doc, page_doc)
      @uri = page_doc[:id]
      @id = get_formatted_id(get_path(@uri))
      @number = page_doc[:page_number]

      doc[:images][:docs].each do |image_doc|
        if image_doc[:pcdm_file_of] == @uri
          @image = FcrepoImage.new(image_doc)
        end
      end
    end
  end

  class FcrepoImage
    include ManifestHelper
    include FcrepoHelper
    attr_reader :id, :width, :height, :uri

    def initialize(image_doc)
      @uri = image_doc[:id]
      @id = get_formatted_id(get_path(@uri))
      @width = image_doc[:image_width]
      @height = image_doc[:image_height]
    end
  end

  class FcrepoItem
    include ManifestHelper
    include FcrepoHelper

    def initialize(path, query)
      @path = path
      @query = query
      @uri = path_to_uri(@path)
      # base URI of the manifest resources
      @base_uri = MANIFEST_URL + get_formatted_id(@path) + '/'
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

      begin
        response = HTTP_CONN.get SOLR_URL + "pcdm", q: "id:#{@uri.gsub(':', '\:')}", wt: 'json'
      rescue Faraday::ConnectionFailed => e
        raise InternalServerError, "Unable to connect to Solr"
      end
      raise InternalServerError, "Got a #{response.status} response from Solr" unless response.success?
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

    def pages
      doc[:pages][:docs].map {|page_doc| FcrepoPage.new(doc, page_doc)}
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

    def get_highlighted_hits(page_id)
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
      res = HTTP_CONN.get SOLR_URL + "select", solr_params
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
                  target: body['annotation_source'][0],
                  selector: fragment_selector("xywh=#{coords[0]}")
                )
              )
            end
          end
        end
      end
      annotation_list(annotation_list_uri, annotations)
    end

    def get_textblock_list(page_id)
      prefix, path = page_id.split /:/, 2
      page_uri = path_to_uri(path)
      solr_params = {
        'fq' => ['rdf_type:oa\:Annotation', "annotation_source:#{page_uri.gsub(':', '\:')}"],
        'wt' => 'json',
        'q' => '*:*',
        'fl' => '*',
        'rows' => 100,
      }
      res = HTTP_CONN.get SOLR_URL + "select", solr_params
      results = res.body
      coord_tag_pattern = /\|(\d+,\d+,\d+,\d+)/
      annotation_list_uri = list_uri(get_formatted_id(path))

      docs = results['response']['docs']
      annotations = docs.map do |doc|
        annotation(
          id: '#' + doc['resource_selector'][0],
          type: 'umd:articleSegment',
          motivation: 'sc:painting',
          text: doc['extracted_text'].gsub(coord_tag_pattern, ''),
          target: doc['annotation_source'][0],
          selector: fragment_selector(doc['resource_selector'][0])
        )
      end
      annotation_list(annotation_list_uri, annotations)
    end
  end
end
