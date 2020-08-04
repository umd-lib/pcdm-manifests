# frozen_string_literal: true

namespace :app do
  desc 'Report the current version of the application'
  task version: :environment do
    puts PcdmManifests::VERSION
  end
end
