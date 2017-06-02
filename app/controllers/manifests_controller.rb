class ManifestsController < ApplicationController
  include ManifestHelper

  # Render the index page
  def index
    render :file => 'public/index.html'
  end

  # GET /manifests/:id
  def show
    prefixed_id = params[:id]
    verify_prefix(prefixed_id)
    @doc = get_solr_doc(prefixed_id)
    case @doc[:component].downcase
    when "issue"
      prepare_for_render(@doc, params[:q])
      render :show
    when "page"
      redirect_to '/manifests/' + get_formatted_id(get_path(@doc[:page_issue])) + '/manifest', status: :see_other
    else
      raise ActionController::RoutingError.new('Not an PCDM Object/File: ' + prefixed_id)
    end
  end

  def show_list
    prefix, path = params[:id].split /:/
    manifest_id = "#{prefix}:#{encode(path)}"
    verify_prefix(manifest_id)
    canvas_id = params[:list_id]
    verify_prefix(canvas_id)
    render json: get_highlighted_hits(manifest_id, id_to_uri(canvas_id), params[:q])
  end
end
