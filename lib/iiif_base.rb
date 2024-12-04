# frozen_string_literal: true

require 'http_utils'
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

    def canvas(page) # rubocop:disable Metrics/MethodLength
      annotation = image_annotation(page)
      {
        '@id' => canvas_uri(page.id),
        '@type' => 'sc:Canvas',
        'label' => page.label,
        'height' => annotation.dig('resource', 'height') || DEFAULT_CANVAS_HEIGHT,
        'width' => annotation.dig('resource', 'width') || DEFAULT_CANVAS_WIDTH,
        'images' => annotation ? [annotation] : [],
        'thumbnail' => thumbnail(page.image),
        'otherContent' => other_content(page)
      }
    end

    def canvases
      pages.map { |page| canvas(page) }
    end

    def image_dimensions(image)
      # use the dimensions found in the index, if present
      return { w: image.width, h: image.height } if image.height && image.width

      # otherwise, attempt retrieve from the image server
      # only fall back to the defaults if we cannot contact the image server
      begin
        response = HttpUtils::HTTP_CONN.get "#{image_uri(image.id)}/info.json"
        return { w: DEFAULT_CANVAS_WIDTH, h: DEFAULT_CANVAS_HEIGHT } unless response.success?

        info = response.body
        { w: info['width'], h: info['height'] }
      rescue Faraday::ConnectionFailed
        { w: DEFAULT_CANVAS_WIDTH, h: DEFAULT_CANVAS_HEIGHT }
      end
    end

    def image_service(iiif_image_uri, iiif_version = 2, level = 2)
      {
        '@context' => "http://iiif.io/api/image/#{iiif_version}/context.json",
        '@id' => iiif_image_uri,
        'profile' => "http://iiif.io/api/image/#{iiif_version}/profiles/level#{level}.json"
      }
    end

    def image_annotation(page)
      return unless page.image

      image = page.image
      {
        '@id' => annotation_uri(image.id),
        '@type' => 'oa:Annotation',
        'motivation' => 'sc:painting',
        'resource' => image_resource(page.image),
        'on' => canvas_uri(page.id)
      }
    end

    def image_resource(image)
      iiif_image_uri = image_uri(image.id)
      image_size = image_dimensions(image)
      {
        '@id' => iiif_image_uri,
        '@type' => 'dctypes:Image',
        'format' => 'image/jpeg',
        'service' => image_service(iiif_image_uri),
        'height' => image_size[:h],
        'width' => image_size[:w]
      }
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

    def manifest # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
      {
        '@context' => 'http://iiif.io/api/presentation/2/context.json',
        '@id' => manifest_uri,
        '@type' => 'sc:Manifest',
        'label' => label,
        'metadata' => metadata,
        'sequences' => sequences(pages),
        'thumbnail' => thumbnail(pages&.first&.image),
        'logo' => logo,
        'navDate' => nav_date,
        'license' => license,
        'attribution' => attribution,
        'description' => description,
        'viewing_direction' => viewing_direction,
        'viewing_hint' => viewing_hint
      }.filter { |_k, v| v }
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

    def thumbnail(image, width = 100)
      return {} if image.nil?

      {
        '@id' => image_uri(image.id, size: "#{width},"),
        'service' => image_service(image_uri(image.id)),
        'format' => 'image/jpeg',
        'width' => width
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
