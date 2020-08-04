# frozen_string_literal: true

# Base application record
# TODO: can we remove this?
class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end
