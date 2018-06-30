class ManifestsController < ApplicationController
  include ManifestHelper
  include FcrepoHelper

  # Render the index page
  def index
    render :file => 'public/index.html'
  end

  # GET /manifests/:id/manifest
  def show
    begin
      if item.is_manifest_level?
        render json: item.manifest
      elsif item.is_canvas_level?
        redirect_to_manifest item
      else
        raise BadRequestError, "Resource #{id} does not have a recognized manifest or canvas type"
      end
    rescue *HTTP_ERRORS => e
      render json: e.to_h, status: e.status
    end
  end

  # GET /manifests/:id/list/:list_id
  def show_list
    begin
      if item.is_manifest_level?
        if params[:q]
          render json: item.get_highlighted_hits(params[:list_id])
        else
          # text block sc:painting annotations
          render json: item.get_textblock_list(params[:list_id])
        end
      elsif item.is_canvas_level?
        redirect_to_manifest item
      else
        raise BadRequestError, "Resource #{id} does not have a recognized manifest or canvas type"
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
    if prefix == 'fcrepo'
      @item = FcrepoItem.new(path, params[:q])
    else
      raise NotFoundError, "Unrecognized prefix '#{prefix}'"
    end
  end

  def redirect_to_manifest(item)
    redirect_to manifest_url(id: item.manifest_id, q: params[:q]), status: :see_other
  end
end
