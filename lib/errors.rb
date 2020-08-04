# frozen_string_literal: true

module Errors
  # RFC 7807 Problem Details format
  # https://tools.ietf.org/html/rfc7807
  module ProblemDetails
    def to_h
      {
        title: title,
        details: message,
        status: status
      }
    end
  end

  # 400 Bad Request
  class BadRequestError < StandardError
    include ProblemDetails
    def title
      'Bad Request'
    end

    def status
      400
    end
  end

  # 404 Not Found
  class NotFoundError < StandardError
    include ProblemDetails
    def title
      'Not Found'
    end

    def status
      404
    end
  end

  # 500 Internal Server Error
  class InternalServerError < StandardError
    include ProblemDetails
    def title
      'Internal Server Error'
    end

    def status
      500
    end
  end

  HTTP_ERRORS = [BadRequestError, NotFoundError, InternalServerError].freeze
end
