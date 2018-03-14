class ManifestsController < ApplicationController
  include ManifestHelper

  # Render the index page
  def index
    render :file => 'public/index.html'
  end

  # GET /manifests/:id
  def show
    prefixed_id = params[:id]
    begin
      verify_prefix(prefixed_id)
      @doc = get_solr_doc(prefixed_id)
      if is_manifest_level? @doc[:component]
        prepare_for_render(@doc, params[:q])
        render :show
      elsif is_canvas_level? @doc[:component]
        page_id = get_prefixed_id(get_path(@doc[:page_issue]))
        redirect_to manifest_url(id: page_id, q: params[:q]), status: :see_other
      else
        raise BadRequestError, "Resource #{prefixed_id} does not have a recognized manifest or canvas type"
      end
    rescue *HTTP_ERRORS => e
      render json: e.to_h, status: e.status
    end
  end

  # GET /manifests/:id/list/:list_id
  def show_list
    prefix, path = params[:id].split /:/
    manifest_id = "#{prefix}:#{encode(path)}"
    begin
      verify_prefix(manifest_id)
      canvas_id = params[:list_id]
      verify_prefix(canvas_id)
      if params[:q]
        render json: get_highlighted_hits(manifest_id, id_to_uri(canvas_id), params[:q])
      else
        # text block sc:painting annotations
        render json: get_textblock_list(manifest_id, id_to_uri(canvas_id))
      end
    rescue *HTTP_ERRORS => e
      render json: e.to_h, status: e.status
    end
  end
end
