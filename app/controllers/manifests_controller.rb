# frozen_string_literal: true

require 'errors'

class ManifestsController < ApplicationController
  include Errors

  # Render the index page
  def index
  end

  # GET /manifests/:id/manifest
  def show # rubocop:disable Metrics/AbcSize
    if item.canvas_level?
      redirect_to_manifest item
    elsif item.manifest_level?
      render json: item.manifest
    else
      raise BadRequestError, "Resource #{params[:id]} does not have a recognized manifest or canvas type"
    end
  rescue *HTTP_ERRORS => e
    render json: e.to_h, status: e.status
  end

  # GET /manifests/:id/list/:list_id
  def show_list # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    if item.canvas_level?
      redirect_to_manifest item
    elsif item.manifest_level?
      if params[:q]
        search_hit_list
      else
        textblock_list
      end
    else
      raise BadRequestError, "Resource #{params[:id]} does not have a recognized manifest or canvas type"
    end
  rescue *HTTP_ERRORS => e
    render json: e.to_h, status: e.status
  end

  private

    def item
      return @item if @item

      prefix, path = params[:id].split(':', 2)
      raise BadRequestError, 'Manifest ID must be in the form prefix:local' unless prefix && path

      begin
        require "iiif/#{prefix}"
        classname = "IIIF::#{prefix.capitalize}::Item".constantize
        @item = classname.new(path, params[:q])
      rescue LoadError
        raise NotFoundError, "Unrecognized prefix '#{prefix}'"
      end
    end

    def redirect_to_manifest(item)
      redirect_to manifest_url(id: item.manifest_id, q: params[:q]), status: :see_other
    end

    def search_hit_list
      raise NotFoundError, 'No annotation list available' unless item.methods.include? :search_hit_list

      render json: item.search_hit_list(params[:list_id])
    end

    def textblock_list
      raise NotFoundError, 'No annotation list available' unless item.methods.include? :textblock_list

      # text block sc:painting annotations
      render json: item.textblock_list(params[:list_id])
    end
end
