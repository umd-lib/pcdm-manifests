require 'errors'

class ManifestsController < ApplicationController
  include Errors

  # Render the index page
  def index
    render :file => 'public/index.html'
  end

  # GET /manifests/:id/manifest
  def show
    begin
      if item.is_canvas_level?
        redirect_to_manifest item
      elsif item.is_manifest_level?
        render json: item.manifest
      else
        raise BadRequestError, "Resource #{params[:id]} does not have a recognized manifest or canvas type"
      end
    rescue *HTTP_ERRORS => e
      render json: e.to_h, status: e.status
    end
  end

  # GET /manifests/:id/list/:list_id
  def show_list
    begin
      if item.is_canvas_level?
        redirect_to_manifest item
      elsif item.is_manifest_level?
        if params[:q]
          raise NotFoundError, "No annotation list available" unless item.methods.include? :search_hit_list
          render json: item.search_hit_list(params[:list_id])
        else
          raise NotFoundError, "No annotation list available" unless item.methods.include? :textblock_list
          # text block sc:painting annotations
          render json: item.textblock_list(params[:list_id])
        end
      else
        raise BadRequestError, "Resource #{params[:id]} does not have a recognized manifest or canvas type"
      end
    rescue *HTTP_ERRORS => e
      render json: e.to_h, status: e.status
    end
  end

  private

  def item
    return @item if @item
    prefix, path = params[:id].split(':', 2)
    raise BadRequestError, "Manifest ID must be in the form prefix:local" unless prefix && path
    begin
      require "iiif/#{prefix}"
      classname = "IIIF::#{prefix.capitalize}::Item".constantize
      @item = classname.new(path, params[:q])
    rescue LoadError => e
      raise NotFoundError, "Unrecognized prefix '#{prefix}'"
    end
  end

  def redirect_to_manifest(item)
    redirect_to manifest_url(id: item.manifest_id, q: params[:q]), status: :see_other
  end
end
