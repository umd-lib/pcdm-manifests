require_relative 'boot'

require 'rails/all'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module PcdmManifests
  class Application < Rails::Application
    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration should go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded.

    config.action_dispatch.default_headers = {
         'Access-Control-Allow-Origin' => '*'
    }

    config.solr_url = ENV['SOLR_URL'] || 'https://solrlocal:8984/solr/fedora4/'
    config.fcrepo_url = ENV['FCREPO_URL'] || 'https://fcrepolocal/fcrepo/rest/'
    config.iiif_image_url = ENV['IIIF_IMAGE_URL'] || 'https://iiiflocal/images/'
    config.iiif_manifest_url = ENV['IIIF_MANIFEST_URL'] || 'https://iiiflocal/manifests/'
  end
end
