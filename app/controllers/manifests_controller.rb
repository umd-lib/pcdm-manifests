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
    case @doc[:component]
    when "issue"
      prepare_for_render(@doc)
      render :show
    when "page"
      redirect_to '/manifests/' + get_formatted_id(get_path(@doc[:page_issue])), status: :see_other
    else
      raise ActionController::RoutingError.new('Not an PCDM Object/File: ' + prefixed_id) 
    end
  end
end
