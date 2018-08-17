require 'http_utils'
require 'iiif_base'

module IIIF
  module Fedora2
    class Item < IIIF::Item
      include HttpUtils

      PREFIX = 'fedora2'
      CONFIG = Rails.configuration.iiif[PREFIX]
      METS_NAMESPACE = 'http://www.loc.gov/METS/'

      def image_base_uri
        CONFIG['image_url']
      end

      def initialize(path, query)
        @pid, @service = path.split /_/, 2
        @query = query
      end

      def get_formatted_id(pid)
        PREFIX + ':' + pid
      end

      def base_uri
        CONFIG['manifest_url'] + PREFIX + ':' + @pid + '/'
      end

      def doc
        return @doc if @doc
        solr_query = @service ? "hasPart:\"#{@pid}\"" : "pid:\"#{@pid}\""
        # stuck on ruby 2.2 so no #dig :(
        @doc =
          begin
            get_solr_doc(solr_query)['response']['docs']
              .first.with_indifferent_access
          rescue NoMethodError
            nil
          end
        @doc
      end

      def mets
        return @mets if @mets
        @mets = Nokogiri::XML(get_mets_xml)
        @mets
      end

      def label
        @pid
      end

      def query
        @query
      end

      def is_manifest_level?
        true
      end

      def is_canvas_level?
        false
      end

      def pages
        if @service
          # only one page; @pid is the image PID
          info = get_image_info(image_uri(get_formatted_id(@pid)))
          [
            IIIF::Page.new.tap do |page|
              page.id = get_formatted_id(@pid)
              page.label = 'Image'
              page.image = IIIF::Image.new.tap do |image|
                image.id = get_formatted_id(@pid)
                image.width = info['width']
                image.height = info['height']
              end
            end
          ]
        else
          # look up the METS relations in Fedora 2 to get a list of image PIDs
          fptrs = mets.xpath(
            '/mets:mets/mets:structMap[@TYPE="LOGICAL"]/mets:div[@ID="images"]//mets:div[@ID="DISPLAY"]/mets:fptr',
            mets: METS_NAMESPACE
          )
          fptrs.map do |fptr|
            label = doc ? doc['displayLabel'] : fptr.xpath('../..').attribute('LABEL').value
            fileid = fptr.attribute('FILEID').value
            flocat = mets.at_xpath(
              '/mets:mets/mets:fileSec/mets:fileGrp/mets:file[@ID=$id]/mets:FLocat',
              { mets: METS_NAMESPACE },
              { id: fileid }
            )
            pid = flocat.attribute('href').value

            IIIF::Page.new.tap do |page|
              page.id = get_formatted_id(pid)
              page.label = label
              page.image = IIIF::Image.new.tap do |image|
                image.id = get_formatted_id(pid)
                info = get_image_info(image_uri(image.id))
                image.width = info['width']
                image.height = info['height']
              end
            end
          end
        end
      end

      def get_solr_doc(query = '*:*')
        params = { q: query, wt: :json }
        JSON.parse(http_get(CONFIG['solr_url'], params).body)
      end

      def get_mets_xml
        http_get(CONFIG['fedora2_url'] + "/fedora/get/#{@pid}/umd-bdef:rels-mets/getRels/").body
      end

      def get_image_info(url)
        http_get(url + '/info.json').body
      end

      def metadata
        return {} unless doc
        # in the future we'll probably wanna get md from here..
        # we'll leave it on ice for now.
        # desc =  Nokogiri::XML(doc["umdm"])
        doc['dmDate'].map do |date|
          { 'label': 'Date', 'value': Time.parse(date).strftime('%Y-%m-%d') }
        end
      end
    end
  end
end
