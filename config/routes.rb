Rails.application.routes.draw do
  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
  get 'manifests/:id/manifest' => 'manifests#show', defaults: {format: :json}
  get 'manifests' => 'manifests#index'
end
