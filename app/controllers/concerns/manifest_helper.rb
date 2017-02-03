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
  HTTP_CONN = Faraday.new(ssl: {verify: false})

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

  def get_solr_doc(id)
    doc_id = FCREPO_URL + id[ID_PREFIX.length..id.length]
    response = HTTP_CONN.get get_solr_url(doc_id)
    raise "Got #{response.status} for #{SOLR_URL + DEFAULT_PATH + quote(doc_id)}" unless response.success?
    doc = eval(response.body)["response"]["docs"][0]
    raise "No results for #{SOLR_URL + DEFAULT_PATH + quote(doc_id)}" if doc.nil?
    doc.with_indifferent_access
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

  def add_page_info(doc)
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
      page[:resource_id] = IMAGE_URL + get_prefixed_id(image_id)
    end
  end

  def add_thumbnail_info(doc)
    first_image_resource_id = get_path(doc[:pages][0][:resource_id])
    doc[:thumbnail_service_id] = first_image_resource_id
    doc[:thumbnail_id] = first_image_resource_id + '/full/80,100/0/default.jpg'
  end

  def add_sequence_info(doc)
    issue_id = get_path(doc[:id])
    first_page_id = get_path(doc[:pages][0][:id])
    sequence_base = MANIFEST_URL + get_formatted_id(issue_id)
    doc[:sequence_id] =  sequence_base + '/sequence/normal'
    doc[:start_canvas] = sequence_base + '/canvas/' + get_formatted_id(first_page_id)
  end

  def prepare_for_render(doc)
    add_page_info(doc)
    add_thumbnail_info(doc)
    add_sequence_info(doc)
    doc.delete(:images)
  end
end
