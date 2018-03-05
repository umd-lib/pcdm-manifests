require 'faraday'
require 'erb'

module ManifestHelper
  extend ActiveSupport::Concern

  DEFAULT_PATH = 'pcdm?wt=ruby&q=id:'
  ID_PREFIX = "fcrepo:"
  FCREPO_URL = Rails.application.config.fcrepo_url
  IMAGE_URL = Rails.application.config.iiif_image_url
  MANIFEST_URL = Rails.application.config.iiif_manifest_url
  SOLR_URL = Rails.application.config.solr_url
  HTTP_CONN = Faraday.new(ssl: {verify: false}, request: {params_encoder: Faraday::FlatParamsEncoder})
  MANIFEST_LEVEL = ['issue', 'letter', 'image', 'reel']
  CANVAS_LEVEL = ['page']

  def verify_prefix(id)
    raise "Missing prefix: " + ID_PREFIX unless id.starts_with?(ID_PREFIX)
  end

  def encode(str)
    ERB::Util.url_encode(str)
  end

  def get_formatted_id(id)
    ID_PREFIX + encode(id)
  end

  def get_prefixed_id(id)
    ID_PREFIX + id
  end

  def quote(str)
    '"' + str + '"'
  end

  def get_path(id)
    id[FCREPO_URL.length..id.length]
  end

  def get_solr_url(id)
    SOLR_URL + DEFAULT_PATH + quote(id)
  end

  def id_to_uri(id)
    FCREPO_URL + id[ID_PREFIX.length..id.length]
  end

  def uri_to_id(uri)
    get_formatted_id(get_path(uri))
  end

  def get_solr_doc(id)
    doc_id = id_to_uri(id)
    response = HTTP_CONN.get get_solr_url(doc_id)
    raise "Got #{response.status} for #{SOLR_URL + DEFAULT_PATH + quote(doc_id)}" unless response.success?
    doc = eval(response.body)["response"]["docs"][0]
    raise "No results for #{SOLR_URL + DEFAULT_PATH + quote(doc_id)}" if doc.nil?
    doc.with_indifferent_access
  end

  def is_manifest_level?(component)
    MANIFEST_LEVEL.include? component.downcase
  end

  def is_canvas_level?(component)
    CANVAS_LEVEL.include? component.downcase
  end

  def get_highlighted_hits(manifest_id, canvas_uri, query)
    base_uri = MANIFEST_URL + manifest_id
    solr_params = {
      'fq'             => ['rdf_type:oa\:Annotation', "annotation_source:#{canvas_uri.gsub(':', '\:')}"],
      'q'              => query,
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
    results = JSON.parse(res.body)
    highlight_pattern = /<em>([^<]*)<\/em>/
    coord_pattern = /(\d+,\d+,\d+,\d+)/
    annotation_list_uri = base_uri + '/list/' + uri_to_id(canvas_uri) + '?q=' + encode(query)
    count = 0

    docs = results['response']['docs']

    snippets = results["highlighting"] || []
    snippets.select { |uri, fields| fields[ocr_field] }.each do |uri, fields|
      body = docs.select { |doc| doc['id'] == uri }.first
      fields[ocr_field].each do |text|
        text.scan highlight_pattern do |hit|
          hit[0].scan coord_pattern do |coords|
            count += 1
            annotations.push({
              "@id" => "#search-result-%03d" % count,
              "@type" => ["oa:Annotation", "umd:searchResult"],
              "on" => {
                "@type" => "oa:SpecificResource",
                "selector" => {
                  "@type" => "oa:FragmentSelector",
                  "value" => "xywh=#{coords[0]}"
                },
                "full" => body['annotation_source'][0]
              },
              "motivation" => "oa:highlighting"
            })
          end
        end
      end
    end

    annotation_list(annotation_list_uri, annotations)
  end

  def annotation_list(uri, annotations)
    {
      "@context"  => "http://iiif.io/api/presentation/2/context.json",
      "@id"       => uri,
      "@type"     => "sc:AnnotationList",
      "resources" => annotations
    }
  end

  def get_textblock_list(manifest_id, canvas_uri)
    base_uri = MANIFEST_URL + manifest_id
    solr_params = {
      'fq'             => ['rdf_type:oa\:Annotation', "annotation_source:#{canvas_uri.gsub(':', '\:')}"],
      'wt'             => 'json',
      'q' => '*:*',
      'fl'             => '*',
      'rows' => 100,
    }
    res = HTTP_CONN.get SOLR_URL + "select", solr_params
    annotations = []
    results = JSON.parse(res.body)
    coord_tag_pattern = /\|(\d+,\d+,\d+,\d+)/
    annotation_list_uri = base_uri + '/list/' + uri_to_id(canvas_uri)

    docs = results['response']['docs']
    docs.each do |doc|
      annotations.push({
        '@id' => '#' + doc['resource_selector'][0],
        "@type" => ["oa:Annotation", "umd:articleSegment"],
        "on" => {
          "@type" => "oa:SpecificResource",
          "selector" => {
            "@type" => "oa:FragmentSelector",
            "value" => doc['resource_selector'][0]
          },
          "full" => doc['annotation_source'][0]
        },
        "resource" => [
          {
            "@type" => "cnt:ContentAsText",
            "format" => "text/plain",
            "chars" => doc['extracted_text'].gsub(coord_tag_pattern, '')
          }
        ],
        "motivation" => "sc:painting"
      })
    end
    annotation_list(annotation_list_uri, annotations)
  end

  def get_image(doc, page_id)
    doc[:images][:docs].each do |image|
      if page_id == image[:pcdm_file_of]
        return image
      end
    end
  end

  def canvas_length(length)
    if length > 1200
      return length
    else
      return 2 * length
    end
  end

  def add_page_info(doc, query)
    issue_id = get_path(doc[:id])
    base_id = MANIFEST_URL + get_formatted_id(issue_id)
    doc[:pages] = doc[:pages][:docs]
    doc[:pages].each do |page|
      image = get_image(doc, page[:id])
      page_id = get_path(page[:id])
      image_id = get_path(image[:id])
      page[:canvas_height] = canvas_length(image[:image_height])
      page[:canvas_width] = canvas_length(image[:image_width])
      page[:image_height] = image[:image_height]
      page[:image_width] = image[:image_width]
      page[:image_mime_type] = image[:mime_type]
      page[:canvas_id] = base_id + '/canvas/' + get_formatted_id(page_id)
      page[:image_id] = base_id + '/annotation/' + get_formatted_id(image_id)
      page[:resource_id] = IMAGE_URL + get_formatted_id(image_id)
      page[:search_hits_list] = query ? base_id + '/list/' + get_formatted_id(page_id) + '?q=' + encode(query) : nil
      page[:textblocks_list] = base_id + '/list/' + get_formatted_id(page_id)
    end
  end

  def add_thumbnail_info(doc)
    return if doc[:pages].empty?
    first_image_resource_id = get_path(doc[:pages][0][:resource_id])
    doc[:thumbnail_service_id] = first_image_resource_id
    doc[:thumbnail_id] = first_image_resource_id + '/full/80,100/0/default.jpg'
  end

  def add_sequence_info(doc)
    return if doc[:pages].empty?
    issue_id = get_path(doc[:id])
    first_page_id = get_path(doc[:pages][0][:id])
    sequence_base = MANIFEST_URL + get_formatted_id(issue_id)
    doc[:sequence_id] =  sequence_base + '/sequence/normal'
    doc[:start_canvas] = sequence_base + '/canvas/' + get_formatted_id(first_page_id)
  end

  def prepare_for_render(doc, query)
    add_page_info(doc, query)
    add_thumbnail_info(doc)
    add_sequence_info(doc)
    doc.delete(:images)
  end
end
