require 'pcdm2manifest'

class ManifestsController < ApplicationController
  # GET /manifests/:id
  def show
    id = params[:id]
    resource_info = PCDM2Manifest.get_info(id)
    if (resource_info[:type] == 'ISSUE')
      issue_uri = PCDM2Manifest.get_uri_from_id(resource_info[:issue_id])
      output = PCDM2Manifest.generate_issue_manifest(issue_uri).to_json
      render :json => output
    else
      encoded_id = PCDM2Manifest.escape_slashes(resource_info[:issue_id])
      redirect_to '/manifests/' + encoded_id, status: :see_other
    end
  end
end
