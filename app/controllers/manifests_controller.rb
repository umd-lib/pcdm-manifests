require 'pcdm2manifest'

class ManifestsController < ApplicationController
  # GET /manifests/:id
  def show
    id = params[:id]
    issue_uri = PCDM2Manifest.get_uri_from_id(id)
    output = PCDM2Manifest.generate_issue_manifest(issue_uri).to_json
    render :json => output
  end
end
