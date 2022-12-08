require_relative 'boot'

require "action_controller/railtie"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module PcdmManifests
  VERSION = '1.9.0-rc2'
  class Application < Rails::Application
    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration should go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded.

    config.api_only = true

    config.action_dispatch.default_headers = {
         'Access-Control-Allow-Origin' => '*'
    }
  end
end
