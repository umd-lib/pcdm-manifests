#!/usr/bin/env ruby

require 'yaml'
require 'faraday'
require 'faraday_middleware'
require 'link_header'

config = YAML.load_file('config.yml')

FCREPO_BASE_URI = config['fcrepo_base_uri']
IIIF_IMAGE_URI = config['iiif_image_uri']

issue_uri = ARGV[0]

@fcrepo_conn = Faraday.new(:ssl => { ca_file: config['server_cert'] }) do |faraday|
  faraday.response :json, :content_type => /\bjson$/
  faraday.adapter  Faraday.default_adapter
  faraday.basic_auth(config['username'], config['password'])
  faraday.headers['Accept'] = 'application/ld+json'
end

@iiif_conn = Faraday.new(:ssl => { verify: false }) do |faraday|
  faraday.response :json, :content_type => /\bjson$/
  faraday.adapter  Faraday.default_adapter
end

def get(uri)
  @fcrepo_conn.get(uri).body[0]
end

def get_described_by_link_header(uri)
  links = @fcrepo_conn.head(uri).headers["link"]
  links_array = LinkHeader.parse(links).to_a
  links_array.each do |link_item|
    link_item[1].each do |key_val_pair|
      if (key_val_pair[0] == "rel" && key_val_pair[1] == "describedby")
        return link_item[0]
      end
    end
  end
  nil
end

def get_metadata_value(metadata, key)
  metadata[key][0]["@value"]
end

def get_mime_type(metadata)
  mime_type_uri = "http://www.ebu.ch/metadata/ontologies/ebucore/ebucore#hasMimeType"
  get_metadata_value(metadata, mime_type_uri)
end

def get_path_from_uri(uri)
  uri_unfrozen = uri.dup
  uri_unfrozen.slice!(FCREPO_BASE_URI)
  return uri_unfrozen
end

def get_image_dimensions(image_uri)
  dimensions = {}
  iiif_image_uri = IIIF_IMAGE_URI + get_path_from_uri(image_uri)
  info_uri = iiif_image_uri + "/info.json"
  info = @iiif_conn.get(info_uri).body
  dimensions["height"] = info["height"]
  dimensions["width"] = info["width"]
  return dimensions
end

# Template for generating manifests
manifest = {
  # Metadata about this manifest file
  "@context" => "http://iiif.io/api/presentation/2/context.json",
  "@id" => "http://example.org/iiif/book1/manifest",
  "@type" => "sc:Manifest",

  # Descriptive metadata about the object/work
  "label" => "Book 1",
  "metadata" => [
    {"label" => "Author", "value": "Anne Author"},
    {"label" => "Published", "value": [
      {"@value" => "Paris, circa 1400", "@language": "en"},
      {"@value" => "Paris, environ 1400", "@language": "fr"}
    ]
    },
    {"label" => "Notes", "value": ["Text of note 1", "Text of note 2"]},
    {"label" => "Source",
     "value" => "<span>From: <a href=\"http://example.org/db/1.html\">Some Collection</a></span>"}
  ],
  "description" => "A longer description of this example book. It should give some real information.",
  "thumbnail" => {
    "@id" => "http://example.org/images/book1-page1/full/80,100/0/default.jpg",
    "service" => {
      "@context" => "http://iiif.io/api/image/2/context.json",
      "@id" => "http://example.org/images/book1-page1",
      "profile" => "http://iiif.io/api/image/2/level1.json"
    }
  },

  # Presentation Information
  "viewingDirection" => "right-to-left",
  "viewingHint" => "paged",
  "navDate" => "1856-01-01T00:00:00Z",

  # Rights Information
  "license" => "http://example.org/license.html",
  "attribution" => "Provided by Example Organization",

  "logo" => {
    "@id" => "http://example.org/logos/institution1.jpg",
    "service" => {
      "@context" => "http://iiif.io/api/image/2/context.json",
      "@id" => "http://example.org/service/inst1",
      "profile" => "http://iiif.io/api/image/2/profiles/level2.json"
    }
  },

  # Links
  "related":{
    "@id" => "http://example.org/videos/video-book1.mpg",
    "format" => "video/mpeg"
  },
  "service" => {
    "@context" => "http://example.org/ns/jsonld/context.json",
    "@id" => "http://example.org/service/example",
    "profile" => "http://example.org/docs/example-service.html"
  },
  "seeAlso" => {
    "@id" => "http://example.org/library/catalog/book1.xml",
    "format" => "text/xml",
    "profile" => "http://example.org/profiles/bibliographic"
  },
  "rendering" => {
    "@id" => "http://example.org/iiif/book1.pdf",
    "label" => "Download as PDF",
    "format" => "application/pdf"
  },
  "within" => "http://example.org/collections/books/",

  # List of sequences
  "sequences" => [
    {
      "@id" => "http://example.org/iiif/book1/sequence/normal",
      "@type" => "sc:Sequence",
      "label" => "Current Page Order",
      # sequence's page order should be included here, see below...
      #
      "viewingDirection" => "left-to-right",
      "viewingHint" => "paged",
      "startCanvas" => "http://example.org/iiif/book1/canvas/p2",

      # The order of the canvases
      "canvases" => [
        {
          "@id" => "http://example.org/iiif/book1/canvas/p1",
          "@type" => "sc:Canvas",
          "label" => "p. 1",
          "height":1000,
          "width":750,

          "images" => [
            {
              # Link from Image to canvas should be included here, as below
              "@id" => "http://example.org/iiif/book1/annotation/p0001-image",
              "@type" => "oa:Annotation",
              "motivation" => "sc:painting",
              "resource" => {
                "@id" => "http://example.org/iiif/book1/res/page1.jpg",
                "@type" => "dctypes:Image",
                "format" => "image/jpeg",
                "service" => {
                  "@context" => "http://iiif.io/api/image/2/context.json",
                  "@id" => "http://example.org/images/book1-page1",
                  "profile" => "http://iiif.io/api/image/2/profiles/level2.json"
                },
                "height":2000,
                "width":1500
              },
              "on" => "http://example.org/iiif/book1/canvas/p1"
            }
          ],
          "otherContent" => [
            {
              # Reference to list of other Content resources, _not included directly_
              "@id" => "http://example.org/iiif/book1/list/p1",
              "@type" => "sc:AnnotationList"
            }
          ]
        },
        {
          "@id" => "http://example.org/iiif/book1/canvas/p2",
          "@type" => "sc:Canvas",
          "label" => "p. 2"
          # ...
        },
        {
          "@id" => "http://example.org/iiif/book1/canvas/p3",
          "@type" => "sc:Canvas",
          "label" => "p. 3"
          # ...
        }
      ]
    }
    # Any additional sequences can be referenced here...
  ]
}

issue = get(issue_uri)

hasMember = 'http://pcdm.org/models#hasMember'
hasFile = 'http://pcdm.org/models#hasFile'
rdf_type = 'http://www.w3.org/1999/02/22-rdf-syntax-ns#type'

pages = issue[hasMember]
pages.each_with_index do |page_link, index|
  puts "Page #{index + 1}"
  puts page_link['@id']
  page = get(page_link['@id'])
  files = page[hasFile]
  files.each do |file_link|
    metadata_link = get_described_by_link_header(file_link['@id'])
    file_meta = get(metadata_link)
    mime_type = get_mime_type(file_meta)
    if (mime_type == "image/tiff")
      puts "  #{file_link['@id']}"
      dimensions = get_image_dimensions(file_link['@id'])
    end
  end
end


