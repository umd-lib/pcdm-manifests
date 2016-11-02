require 'pcdm2manifest'

class ManifestsController < ApplicationController
  # GET /manifests/:id
  def show
    id = params[:id]
    begin
      resource_info = PCDM2Manifest.get_info(id)
    rescue NoMethodError => e
      raise "Error encountered while generating manifest! " + e.to_s
    end
    if (resource_info[:type] == 'ISSUE')
      render :json => get_manifest(resource_info[:issue_id])
    elsif (resource_info[:type] == 'NON_PCDM')
      raise ActionController::RoutingError.new('Not an PCDM Object/File: ' + id) 
    else
      encoded_id = PCDM2Manifest.escape_slashes(resource_info[:issue_id])
      redirect_to '/manifests/' + encoded_id, status: :see_other
    end
  end

  def get_manifest(issue_id)
    issue_uri = PCDM2Manifest.get_uri_from_id(issue_id)
    return PCDM2Manifest.generate_issue_manifest(issue_uri).to_json
  end
end
