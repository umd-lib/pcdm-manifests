#!/usr/bin/env ruby

require 'yaml'
require 'faraday'
require 'faraday_middleware'
require 'link_header'
require 'json'
require 'erb'
require 'logger'

module PCDM2Manifest

  @@logger = Logger.new('log/pcdm2manifest.log')

  @@config = YAML.load_file("config/pcdm2manifest.yml")

  FCREPO_BASE_URI = @@config['fcrepo_base_uri']
  IIIF_IMAGE_URI = @@config['iiif_image_uri']
  IIIF_MANIFEST_URI = @@config['iiif_manifest_uri']
  PREFIX = @@config['id_prefix']

  #RDF METADATA KEYS
  RDF_TYPE = 'http://www.w3.org/1999/02/22-rdf-syntax-ns#type'
  PCDM_OBJECT = 'http://pcdm.org/models#Object'
  PCDM_FILE = 'http://pcdm.org/models#File'
  DCTERMS_TITLE = 'http://purl.org/dc/terms/title'
  DC_DATE = 'http://purl.org/dc/elements/1.1/date'
  BIBO_EDITION = 'http://purl.org/ontology/bibo/edition'
  BIBO_ISSUE = 'http://purl.org/ontology/bibo/issue'
  BIBO_VOLUME = 'http://purl.org/ontology/bibo/volume'
  IANA_FIRST = 'http://www.iana.org/assignments/relation/first'
  IANA_LAST = 'http://www.iana.org/assignments/relation/last'
  IANA_NEXT = 'http://www.iana.org/assignments/relation/next'
  HAS_MEMBER = 'http://pcdm.org/models#hasMember'
  HAS_FILE = 'http://pcdm.org/models#hasFile'
  MIME_TYPE_URI = 'http://www.ebu.ch/metadata/ontologies/ebucore/ebucore#hasMimeType'
  FILE_OF = 'http://pcdm.org/models#fileOf'
  MEMBER_OF = 'http://pcdm.org/models#memberOf'
  PROXY_FOR = 'http://www.openarchives.org/ore/terms/proxyFor'

  @@fcrepo_conn = Faraday.new(:ssl => { ca_file: @@config['server_cert'] }) do |faraday|
    faraday.response :json, :content_type => /\bjson$/
    faraday.adapter  Faraday.default_adapter
    faraday.basic_auth(@@config['username'], @@config['password'])
    faraday.headers['Accept'] = 'application/ld+json'
  end

  @@iiif_conn = Faraday.new(:ssl => { verify: false }) do |faraday|
    faraday.response :json, :content_type => /\bjson$/
    faraday.adapter  Faraday.default_adapter
  end

  def self.get(uri, accept_header=true)
    if(accept_header == false)
      @@fcrepo_conn.headers.delete('Accept')
    end
    response = @@fcrepo_conn.get(uri)
    @@fcrepo_conn.headers['Accept'] = 'application/ld+json'
    if (response.status == 200)
      return response
    else
      raise "Got #{response.status} for #{uri}"
    end
  end

  def self.head(uri, accept_header=true)
    if(accept_header == false)
      @@fcrepo_conn.headers.delete('Accept')
    end
    response = @@fcrepo_conn.head(uri)
    @@fcrepo_conn.headers['Accept'] = 'application/ld+json'
    if (response.status == 200)
      return response
    else
      raise "Got #{response.status} for #{uri}"
    end
  end

  def self.iiif_get(uri)
    response = @@iiif_conn.get(uri)
    if (response.status == 200)
      return response
    else
      raise "Got #{response.status} for #{uri}"
    end
  end

  def self.get_body(uri)
    get(uri).body[0]
  end

  def self.get_described_by_link_header(uri)
    links = head(uri, false).headers['link']
    links_array = LinkHeader.parse(links).to_a
    links_array.each do |link_item|
      link_item[1].each do |key_val_pair|
        if (key_val_pair[0] == 'rel' && key_val_pair[1] == 'describedby')
          return link_item[0]
        end
      end
    end
    nil
  end

  def self.get_metadata_value(metadata, key)
    metadata[key][0]['@value']
  end

  def self.get_mime_type(metadata)
    get_metadata_value(metadata, MIME_TYPE_URI)
  end

  def self.get_path_from_uri(uri)
    uri_unfrozen = uri.dup
    uri_unfrozen.slice!(FCREPO_BASE_URI)
    return uri_unfrozen
  end

  def self.get_uri_from_id(id)
    return FCREPO_BASE_URI + id
  end

  def self.get_image_dimensions(image_uri)
    dimensions = {}
    iiif_image_uri = IIIF_IMAGE_URI + PREFIX + get_path_from_uri(image_uri)
    info_uri = iiif_image_uri + '/info.json'
    info = iiif_get(info_uri).body
    dimensions['height'] = info['height']
    dimensions['width'] = info['width']
    return dimensions
  end

  def self.escape_slashes(str)
    ERB::Util.url_encode(str)
  end

  def self.uri2encoded_id(uri)
    escape_slashes(get_path_from_uri(uri))
  end

  def self.get_canvas_dimension(image_dimensions)
    canvas_dimensions = image_dimensions.dup
    if ((canvas_dimensions['height'] < 1200) || (canvas_dimensions['width'] < 1200))
      canvas_dimensions['height'] = canvas_dimensions['height'] * 2
      canvas_dimensions['width'] = canvas_dimensions['width'] * 2
    end
    return canvas_dimensions
  end

  def self.get_issue_id_of_page(page_uri)
    page = get_body(page_uri)
    if (page.key?(MEMBER_OF))
      page[MEMBER_OF].each do |member_of|
        membership_uri = member_of['@id']
        membership_meta = get_body(membership_uri)
        if (membership_meta.key?(BIBO_ISSUE))
          return get_path_from_uri(membership_uri)
        end
      end
    end
  end

  def self.get_issue_id_of_file(file_meta_uri)
    file_meta = get_body(file_meta_uri)
    if (file_meta.key?(FILE_OF))
      page_uri = file_meta[FILE_OF][0]['@id']
      return get_issue_id_of_page(page_uri)
    end
  end

  def self.get_proxy_data(proxy_uri)
    proxy = get_body(proxy_uri)
    proxy_data = Hash.new
    proxy_data[:page_uri] = proxy[PROXY_FOR][0]['@id']
    if (proxy.key?(IANA_NEXT))
      proxy_data[:next_page_proxy] = proxy[IANA_NEXT][0]['@id']
    end
    return proxy_data
  end

  def self.is_pcdm_file(file_meta)
    file_meta['@type'].include?(PCDM_FILE)
  end

  def self.is_pcdm_object(object_meta)
    object_meta['@type'].include?(PCDM_OBJECT)
  end

  # Returns a hash map containing the resource type and corresponding issue id
  def self.get_info(resource_id)
    info = Hash.new
    info[:type] = "NON_PCDM"
    resource_url = get_uri_from_id(resource_id)
    desc_header_link = get_described_by_link_header(resource_url)
    if (desc_header_link != nil)
      file_meta = get_body(desc_header_link)
      if is_pcdm_file(file_meta)
        info[:type] = "FILE"
        info[:issue_id] = get_issue_id_of_file(desc_header_link)
      end
    else
      object = get_body(resource_url)
      if is_pcdm_object(object)
        if (object.key?(HAS_FILE))
          info[:type] = "PAGE"
          info[:issue_id] = get_issue_id_of_page(resource_url)
        else
          info[:type] = "ISSUE"
          info[:issue_id] = resource_id
        end
      end
    end
    return info
  end


  # Template for generating manifests
  @@manifest_template = {
    # Metadata about this manifest file
    '@context' => 'http://iiif.io/api/presentation/2/context.json',
    '@id' => 'http://example.org/iiif/book1/manifest', # Issue Manifest ID
    '@type' => 'sc:Manifest',

    # Descriptive metadata about the object/work
    'label' => 'Book 1', # Issue Title
    'metadata' => [  # Issue Meta
      {'label' => 'Author', 'value': 'Anne Author'},
      {'label' => 'Published', 'value': [
        {'@value' => 'Paris, circa 1400', '@language': 'en'},
        {'@value' => 'Paris, environ 1400', '@language': 'fr'}
      ]
      },
      {'label' => 'Notes', 'value': ['Text of note 1', 'Text of note 2']},
      {'label' => 'Source',
       'value' => '<span>From: <a href=\'http://example.org/db/1.html\'>Some Collection</a></span>'}
    ],
    'description' => '  ', # Issue Description
    'thumbnail' => { 
      '@id' => 'http://example.org/images/book1-page1/full/80,100/0/default.jpg', # Issue First Page Image Thumbnail
      'service' => {
        '@context' => 'http://iiif.io/api/image/2/context.json',
        '@id' => 'http://example.org/images/book1-page1/', # Base URL of the image (i.e. without '/full/80,100/0/default.jpg')
        'profile' => 'http://iiif.io/api/image/2/level1.json'
      }
    },

    # Presentation Information
    'viewingDirection' => 'right-to-left',
    'viewingHint' => 'paged',
    'navDate' => '1856-01-01T00:00:00Z',

    # Rights Information
    'license' => 'http://example.org/license.html',
    'attribution' => 'Provided by Example Organization',

    'logo' => {
      '@id' => 'http://wwwdev.lib.umd.edu/images/wrapper/liblogo.png',
      'service' => {
        '@context' => 'http://iiif.io/api/image/2/context.json',
        '@id' => 'http://example.org/service/inst1', # IIIF Base URL of the logo
        'profile' => 'http://iiif.io/api/image/2/profiles/level2.json'
      }
    },

    # Links
    'related':{
      '@id' => 'http://example.org/videos/video-book1.mpg',
      'format' => 'video/mpeg'
    },
    'service' => {
      '@context' => 'http://example.org/ns/jsonld/context.json',
      '@id' => 'http://example.org/service/example',
      'profile' => 'http://example.org/docs/example-service.html'
    },
    'seeAlso' => {
      '@id' => 'http://example.org/library/catalog/book1.xml',
      'format' => 'text/xml',
      'profile' => 'http://example.org/profiles/bibliographic'
    },
    'rendering' => {
      '@id' => 'http://example.org/iiif/book1.pdf',
      'label' => 'Download as PDF',
      'format' => 'application/pdf'
    },
    'within' => 'http://example.org/collections/books/',

    # List of sequences
    'sequences' => [
      {
        '@id' => 'http://example.org/iiif/book1/sequence/normal', # Derefrencing optionale 
        '@type' => 'sc:Sequence',
        'label' => 'Current Page Order',
        # sequence's page order should be included here, see below...
        #
        'viewingDirection' => 'left-to-right',
        'viewingHint' => 'paged',
        'startCanvas' => 'http://example.org/iiif/book1/canvas/p2', # Default can be Page 1 Canvas 

        # The order of the canvases
        'canvases' => [
          {
            '@id' => 'http://example.org/iiif/book1/canvas/p1', # Recommended to be dereferenceable
            '@type' => 'sc:Canvas',
            'label' => 'p. 1', # Page title
            'height':1000, # Height of the largest image for the page (double if less than 1200)
            'width':750, # WIdth of the largest image for the page (double if less than 1200)

            'images' => [
              {
                # Link from Image to canvas should be included here, as below
                '@id' => 'http://example.org/iiif/book1/annotation/p0001-image', # Recommended to be dereferenced
                '@type' => 'oa:Annotation',
                'motivation' => 'sc:painting',
                'resource' => {
                  '@id' => 'http://example.org/iiif/book1/res/page1.jpg', # IIIF Image URL
                  '@type' => 'dctypes:Image',
                  'format' => 'image/jpeg',
                  'service' => {
                    '@context' => 'http://iiif.io/api/image/2/context.json',
                    '@id' => 'http://example.org/images/book1-page1', # IIIF Base URL of the image
                    'profile' => 'http://iiif.io/api/image/2/profiles/level2.json'
                  },
                  'height':2000,
                  'width':1500
                },
                'on' => 'http://example.org/iiif/book1/canvas/p1' # Canvas ID
              }
            ],
            'otherContent' => [
              {
                # Reference to list of other Content resources, _not included directly_
                '@id' => 'http://example.org/iiif/book1/list/p1',
                '@type' => 'sc:AnnotationList'
              }
            ]
          },
          {
            '@id' => 'http://example.org/iiif/book1/canvas/p2',
            '@type' => 'sc:Canvas',
            'label' => 'p. 2'
            # ...
          },
          {
            '@id' => 'http://example.org/iiif/book1/canvas/p3',
            '@type' => 'sc:Canvas',
            'label' => 'p. 3'
            # ...
          }
        ]
      }
      # Any additional sequences can be referenced here...
    ]
  }

  # Remove any properties that are currently used
  @@manifest_template.delete('related')
  @@manifest_template.delete('service')
  @@manifest_template.delete('seeAlso')
  @@manifest_template.delete('rendering')
  @@manifest_template['sequences'][0]['canvases'][0].delete('otherContent')
  @@manifest_template['logo'].delete('service')


  def self.generate_issue_manifest(issue_uri)
    @@logger.debug "Issue: #{issue_uri}"
    issue = get_body(issue_uri)
    issue_id_encoded = uri2encoded_id(issue_uri)
    first_page_proxy = get_proxy_data(issue[IANA_FIRST][0]['@id'])
    first_page_id =  get_path_from_uri(first_page_proxy[:page_uri])
    first_page_id_encoded =  escape_slashes(first_page_id)

    # Populate Manifest properties
    # Clone will onle make a shallow copy of the manifest templates
    # Reinitiate any child arrays and hashes that needs to be modified
    #   array objects should be reinitiated with Arrays.new
    #   hash objects should be cloned before updates
    manifest = @@manifest_template.clone
    manifest['@id'] = IIIF_MANIFEST_URI + PREFIX + issue_id_encoded + '/manifest'
    manifest['label'] = issue[DCTERMS_TITLE]
    manifest['metadata'] = Array.new
    manifest['metadata'].push({'label': 'Date', 'value': issue[DC_DATE]})
    manifest['metadata'].push({'label': 'Edition', 'value': issue[BIBO_EDITION]})
    manifest['metadata'].push({'label': 'Volume', 'value': issue[BIBO_VOLUME]})
    manifest['metadata'].push({'label': 'Issue', 'value': issue[BIBO_ISSUE]})
    manifest['thumbnail'] = manifest['thumbnail'].clone
    manifest['thumbnail']['@id'] = IIIF_IMAGE_URI + PREFIX + first_page_id + '/full/80,100/0/default.jpg'
    manifest['thumbnail']['service'] = manifest['thumbnail']['service'].clone
    manifest['thumbnail']['service']['@id'] = IIIF_IMAGE_URI + PREFIX + first_page_id

    # Populate Sequence properties
    sequence = manifest['sequences'][0].clone
    sequence['@id'] = IIIF_MANIFEST_URI + PREFIX + issue_id_encoded + '/sequence/normal'
    sequence['startCanvas'] = IIIF_MANIFEST_URI + PREFIX + issue_id_encoded + '/canvas/' + PREFIX + first_page_id_encoded
    manifest['sequences'][0] = sequence

    # Get the canvas template and reinitiate canvases array
    canvases = sequence['canvases']
    canvas_template = canvases[0]
    canvases = Array.new

    # Get the image template 
    images = canvas_template['images']
    image_template = images[0]

    # Get the resource and service template
    resource_template = image_template['resource'].clone
    service_template = resource_template['service'].clone

    # Populate the canvases from the pages
    page_proxy = first_page_proxy
    page_count = 1
    while page_proxy != nil do
      page_uri = page_proxy[:page_uri]
      @@logger.debug "  Page #{page_count}: #{page_uri}"
      page = get_body(page_uri)
      files = page[HAS_FILE]
      files.each do |file_link|
        metadata_link = get_described_by_link_header(file_link['@id'])
        file_meta = get_body(metadata_link)
        mime_type = get_mime_type(file_meta)
        if (mime_type == 'image/tiff')
          @@logger.debug "    File: #{file_link["@id"]}"
          dimensions = get_image_dimensions(file_link['@id'])
          canvas_dimensions = get_canvas_dimension(dimensions)

          page_id_encoded = escape_slashes(get_path_from_uri(page_uri))
          file_id = get_path_from_uri(file_link['@id'])
          file_id_encoded = escape_slashes(file_id)

          # Populate Canvas properties
          page_canvas = canvas_template.clone
          page_canvas['@id'] = IIIF_MANIFEST_URI + PREFIX + issue_id_encoded + '/canvas/' + PREFIX + page_id_encoded
          page_canvas['label'] = page[DCTERMS_TITLE][0]['@value']
          page_canvas[:height] = canvas_dimensions['height']
          page_canvas[:width] = canvas_dimensions['width']

          # Populate Image properties
          page_image = image_template.clone
          page_image['@id'] = IIIF_MANIFEST_URI + PREFIX + issue_id_encoded + '/annotation/' + PREFIX + file_id_encoded
          page_image['on'] = page_canvas['@id']

          # Populate Resource properties
          page_resource = resource_template.clone
          page_resource['@id'] = IIIF_IMAGE_URI + PREFIX + file_id
          page_resource['format'] = mime_type
          page_resource[:height] = dimensions['height']
          page_resource[:width] = dimensions['width']

          # Populate Service properties
          page_service = service_template.clone
          page_service['@id'] = page_resource['@id']

          # Set all the populated objects to page canvas
          page_resource['service'] = page_service
          page_image['resource'] = page_resource
          page_canvas['images'] = [page_image]

          # Add the page canvas to issue manifest's canvases array
          canvases.push(page_canvas)
        end
      end
      if page_proxy.key?(:next_page_proxy)
        page_proxy = get_proxy_data(page_proxy[:next_page_proxy])
        page_count += 1
      else
        page_proxy = nil
      end
    end
    sequence['canvases'] = canvases
    return manifest
  end
end

# MAIN Execution
if __FILE__ == $0
  issue_uri = ARGV[0]
  issue_manifest = PCDM2Manifest.generate_issue_manifest(issue_uri)
  puts JSON.pretty_generate(issue_manifest)
end