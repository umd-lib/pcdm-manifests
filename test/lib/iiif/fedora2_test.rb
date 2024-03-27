# frozen_string_literal: true

require 'minitest/autorun'
require 'test_helper'
require 'errors'
require 'iiif/fedora2'

module IIIF
  module Fedora2
    # test configuration
    CONFIG = {
      fedora2_url: 'http://localhost:8080/fedora/get/'
    }.with_indifferent_access.freeze
  end

  class Fedora2Test < ActiveSupport::TestCase
    include Errors
    test 'missing source image' do
      item = IIIF::Fedora2::Item.new('umd:1234', nil)
      item.stub :get_image_info, ->(_url) { raise NotFoundError } do
        image = item.get_image('umd:5678')
        assert_equal 'static:unavailable', image.id
      end
    end
  end
end
