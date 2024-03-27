# frozen_string_literal: true

require 'erb'

module IIIF
  # A single IIIF canvas
  class Page
    attr_accessor :id, :label, :image, :uri
  end

  # A single IIIF image
  class Image
    attr_accessor :id, :width, :height, :uri
  end

  # A resource with a manifest
  class Item # rubocop:disable Metrics/ClassLength
    DEFAULT_CANVAS_HEIGHT = 1200
    DEFAULT_CANVAS_WIDTH = 1200

    def encode(str)
      ERB::Util.url_encode(str)
    end

    def base_uri
    end

    def query
    end

    def manifest_level?
    end

    def canvas_level?
    end

    def pages
      []
    end

    def label
    end

    def nav_date
    end

    def license
    end

    def attribution
    end

    def metadata
      []
    end

    def description
    end

    def viewing_direction
    end

    def viewing_hint
    end

    def annotation_list(uri, annotations)
      {
        '@context' => 'http://iiif.io/api/presentation/2/context.json',
        '@id' => uri,
        '@type' => 'sc:AnnotationList',
        'resources' => annotations
      }
    end

    def canvases # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      pages.map do |page| # rubocop:disable Metrics/BlockLength
        image = page.image
        {
          '@id' => canvas_uri(page.id),
          '@type' => 'sc:Canvas',
          'label' => page.label,
          'height' => image.height || DEFAULT_CANVAS_HEIGHT,
          'width' => image.width || DEFAULT_CANVAS_WIDTH,

          'images' => [
            {
              '@id' => annotation_uri(image.id),
              '@type' => 'oa:Annotation',
              'motivation' => 'sc:painting',
              'resource' => {
                '@id' => image_uri(image.id),
                '@type' => 'dctypes:Image',
                'format' => 'image/jpeg',
                'service' => {
                  '@context' => 'http://iiif.io/api/image/2/context.json',
                  '@id' => image_uri(image.id),
                  'profile' => 'http://iiif.io/api/image/2/profiles/level2.json'
                },
                'height' => image.height || DEFAULT_CANVAS_HEIGHT,
                'width' => image.width || DEFAULT_CANVAS_WIDTH
              },
              'on' => canvas_uri(page.id)
            }
          ],
          'thumbnail' => thumbnail(image),
          'otherContent' => other_content(page)
        }
      end
    end

    def other_content(page) # rubocop:disable Metrics/MethodLength
      [].tap do |other|
        if methods.include?(:textblock_list)
          other.push(
            '@id' => list_uri(page.id),
            '@type' => 'sc:AnnotationList'
          )
        end
        if query && methods.include?(:search_hit_list)
          other.push(
            '@id' => "#{list_uri(page.id)}?q=#{encode(query)}",
            '@type' => 'sc:AnnotationList'
          )
        end
      end
    end

    def manifest # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
      {
        '@context' => 'http://iiif.io/api/presentation/2/context.json',
        '@id' => manifest_uri,
        '@type' => 'sc:Manifest',
        'label' => label,
        'metadata' => metadata,
        'sequences' => sequences(pages),
        'thumbnail' => thumbnail(pages&.first&.image),
        'logo' => logo
      }.tap do |manifest|
        manifest['navDate'] = nav_date if nav_date
        manifest['license'] = license if license
        manifest['attribution'] = attribution if attribution
        manifest['description'] = description if description
        manifest['viewing_direction'] = viewing_direction if viewing_direction
        manifest['viewing_hint'] = viewing_hint if viewing_hint
      end
    end

    def logo
      { '@id' => 'https://www.lib.umd.edu/images/wrapper/liblogo.png' }
    end

    def sequences(pages)
      return [] unless pages.length.positive?

      [sequence('normal', 'Current Page Order', pages.first)]
    end

    def sequence(id, label, first_page)
      return if first_page.nil?

      {
        '@id' => sequence_uri(id),
        '@type' => 'sc:Sequence',
        'label' => label,
        'startCanvas' => canvas_uri(first_page.id),
        'canvases' => canvases
      }
    end

    def thumbnail(image) # rubocop:disable Metrics/MethodLength
      return {} if image.nil?

      width = 80
      height = 100
      {
        '@id' => image_uri(image.id, size: "#{width},#{height}"),
        'service' => {
          '@context' => 'http://iiif.io/api/image/2/context.json',
          '@id' => image_uri(image.id),
          'profile' => 'http://iiif.io/api/image/2/level1.json'
        },
        'format' => 'image/jpeg',
        'width' => width,
        'height' => height
      }
    end

    def manifest_uri
      "#{base_uri}manifest"
    end

    def canvas_uri(page_id)
      "#{base_uri}canvas/#{page_id}"
    end

    def annotation_uri(doc_id)
      "#{base_uri}annotation/#{doc_id}"
    end

    def list_uri(page_id)
      "#{base_uri}list/#{page_id}"
    end

    def sequence_uri(label)
      "#{base_uri}sequence/#{label}"
    end

    def fragment_selector(value)
      {
        '@type' => 'oa:FragmentSelector',
        'value' => value
      }
    end

    def specific_resource(param = {})
      {
        '@type' => 'oa:SpecificResource',
        'selector' => param[:selector],
        'full' => param[:full]
      }
    end

    def text_body(param = {})
      {
        '@type' => 'cnt:ContentAsText',
        'format' => param[:format] || 'text/plain',
        'chars' => param[:text]
      }
    end

    def annotation(param = {})
      {
        '@id' => param[:id],
        '@type' => ['oa:Annotation', param[:type]],
        'on' => param[:target],
        'motivation' => param[:motivation]
      }.tap do |annotation|
        annotation['resource'] = [param[:body]] if param[:body]
      end
    end

    DEFAULT_IIIF_PARAMS = {
      region: 'full',
      size: 'full',
      rotation: 0,
      quality: 'default',
      format: 'jpg'
    }.freeze

    def image_uri(image_id, param = {})
      uri = "#{image_base_uri}#{image_id}"
      if param.empty?
        uri
      else
        p = DEFAULT_IIIF_PARAMS.merge(param)
        uri + "/#{p[:region]}/#{p[:size]}/#{p[:rotation]}/#{p[:quality]}.#{p[:format]}"
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
  end
end
