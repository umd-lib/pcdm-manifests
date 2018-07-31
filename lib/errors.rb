module Errors
  # RFC 7807 Problem Details format
  # https://tools.ietf.org/html/rfc7807
  module ProblemDetails
    def to_h
      {
        title: self.title,
        details: self.message,
        status: self.status
      }
    end
  end

  class BadRequestError < StandardError
    include ProblemDetails
    def title
      'Bad Request'
    end
    def status
      400
    end
  end

  class NotFoundError < StandardError
    include ProblemDetails
    def title
      'Not Found'
    end
    def status
      404
    end
  end

  class InternalServerError < StandardError
    include ProblemDetails
    def title
      'Internal Server Error'
    end
    def status
      500
    end
  end

  HTTP_ERRORS = [BadRequestError, NotFoundError, InternalServerError]
end
