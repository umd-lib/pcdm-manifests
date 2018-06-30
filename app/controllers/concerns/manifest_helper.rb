require 'erb'

module ManifestHelper
  extend ActiveSupport::Concern

  # RFC 7807 Problem Details format
  # https://tools.ietf.org/html/rfc7807
  module ProblemDetails
    def to_h
      {
        title: self.title,
        details: self.message,
        status: self.status
      }
    end
  end

  class BadRequestError < StandardError
    include ProblemDetails
    def title
      'Bad Request'
    end
    def status
      400
    end
  end

  class NotFoundError < StandardError
    include ProblemDetails
    def title
      'Not Found'
    end
    def status
      404
    end
  end

  class InternalServerError < StandardError
    include ProblemDetails
    def title
      'Internal Server Error'
    end
    def status
      500
    end
  end

  def encode(str)
    ERB::Util.url_encode(str)
  end

  HTTP_ERRORS = [BadRequestError, NotFoundError, InternalServerError]

  # generic mixin methods

  def annotation_list(uri, annotations)
    {
      "@context"  => "http://iiif.io/api/presentation/2/context.json",
      "@id"       => uri,
      "@type"     => "sc:AnnotationList",
      "resources" => annotations
    }
  end

  def canvases
    canvases = []
    pages.map do |page|
      image = page.image
      {
        '@id': canvas_uri(page.id),
        '@type': 'sc:Canvas',
        'label': "Page #{page.number}",
        'height': image.height,
        'width': image.width,

        'images': [
          {
            '@id': annotation_uri(image.id),
            '@type': 'oa:Annotation',
            'motivation': 'sc:painting',
            'resource': {
              '@id': iiif_image_uri(image),
              '@type': 'dctypes:Image',
              'format': 'image/jpeg',
              'service': {
                '@context': 'http://iiif.io/api/image/2/context.json',
                '@id': iiif_image_uri(image),
                'profile': 'http://iiif.io/api/image/2/profiles/level2.json'
              },
              'height': image.height,
              'width': image.width,
            },
            'on': canvas_uri(page.id)
          }
        ],
        'otherContent': [
          {
            '@id': list_uri(page.id),
            '@type': 'sc:AnnotationList'
          }
        ]
      }.tap do |canvas|
        if @query
          canvas[:otherContent].push({
            '@id': list_uri(page.id) + '?q=' + encode(@query),
            '@type': 'sc:AnnotationList',
          })
        end
      end
    end
  end

  def manifest
    first_page = pages[0]
    first_image = first_page.image

    {
      '@context': 'http://iiif.io/api/presentation/2/context.json',
      '@id': manifest_uri,
      '@type': 'sc:Manifest',

      'label': label,
      'metadata': metadata,
      'thumbnail': {
        '@id': iiif_image_uri(first_image, size: '80,100'),
        'service': {
          '@context': 'http://iiif.io/api/image/2/context.json',
          '@id': iiif_image_uri(first_image),
          'profile': 'http://iiif.io/api/image/2/level1.json'
        }
      },
      'navDate': date,
      'license': license,
      'attribution': attribution,

      'logo': {
        '@id': 'https://www.lib.umd.edu/images/wrapper/liblogo.png'
      },

      'sequences': [
        {
          '@id': sequence_uri('normal'),
          '@type': 'sc:Sequence',
          'label': 'Current Page Order',
          'startCanvas': canvas_uri(first_page.id),
          'canvases': canvases
        }
      ]
    }
  end

  def manifest_uri
    @base_uri + 'manifest'
  end

  def canvas_uri(page_id)
    @base_uri + 'canvas/' + page_id
  end

  def annotation_uri(doc_id)
    @base_uri + 'annotation/' + doc_id
  end

  def list_uri(page_id)
    @base_uri + 'list/' + page_id
  end

  def sequence_uri(label)
    @base_uri + 'sequence/' + label
  end

  def fragment_selector(value)
    {
      "@type" => "oa:FragmentSelector",
      "value" => value
    }
  end

  def annotation(param = {})
    {
      '@id' => param[:id],
      "@type" => ["oa:Annotation", param[:type]],
      "on" => {
        "@type" => "oa:SpecificResource",
        "selector" => param[:selector],
        "full" => param[:target]
      },
      "motivation" => param[:motivation]
    }.tap do |anno|
      if param[:text]
        anno['resource'] = [
          {
            "@type" => "cnt:ContentAsText",
            "format" => "text/plain",
            "chars" => param[:text]
          }
        ]
      end
    end
  end
end
