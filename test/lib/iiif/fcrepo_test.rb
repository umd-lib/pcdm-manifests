# frozen_string_literal: true

require 'minitest/autorun'
require 'test_helper'
require 'iiif/fcrepo'

module IIIF
  module Fcrepo
    # test configuration
    CONFIG = {
      fcrepo_url: 'http://localhost:8080/rest/'
    }.with_indifferent_access.freeze
  end

  class FcrepoTest < ActiveSupport::TestCase
    test 'simple path' do
      path = IIIF::Fcrepo::Path.new('a:b:c')
      assert_equal 'a/b/c', path.expanded
      assert_equal 'http://localhost:8080/rest/a/b/c', path.to_uri(base_uri: 'http://localhost:8080/rest/')
      assert_equal 'http://localhost:8080/rest/a/b/c', path.to_uri
    end

    test 'flat style' do
      path = IIIF::Fcrepo::Path.new('pcdm::1d8a71b8-7356-4282-8e99-da88f0f997c7')
      assert_equal 'pcdm/1d/8a/71/b8/1d8a71b8-7356-4282-8e99-da88f0f997c7', path.expanded
      assert_equal 'http://localhost:8080/rest/pcdm/1d/8a/71/b8/1d8a71b8-7356-4282-8e99-da88f0f997c7', path.to_uri
    end

    test 'hierarchical style' do
      path = IIIF::Fcrepo::Path.new('dc:2021:1::1d8a71b8-7356-4282-8e99-da88f0f997c7')
      assert_equal 'dc/2021/1/1d/8a/71/b8/1d8a71b8-7356-4282-8e99-da88f0f997c7', path.expanded
      assert_equal 'http://localhost:8080/rest/dc/2021/1/1d/8a/71/b8/1d8a71b8-7356-4282-8e99-da88f0f997c7', path.to_uri
    end

    test 'hierarchical style with sub-path' do
      path = IIIF::Fcrepo::Path.new('dc:2021:1::1d8a71b8-7356-4282-8e99-da88f0f997c7:m:IQMYmY-R')
      assert_equal 'dc/2021/1/1d/8a/71/b8/1d8a71b8-7356-4282-8e99-da88f0f997c7/m/IQMYmY-R', path.expanded
      assert_equal 'http://localhost:8080/rest/dc/2021/1/1d/8a/71/b8/1d8a71b8-7356-4282-8e99-da88f0f997c7/m/IQMYmY-R', path.to_uri
    end
  end
end
