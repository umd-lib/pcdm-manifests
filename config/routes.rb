Rails.application.routes.draw do
  # For details on the DSL available within this file, see https://guides.rubyonrails.org/routing.html
  get 'manifests/:id/manifest' => 'manifests#show', defaults: {format: :json}, as: 'manifest'
  get 'manifests/:id/list/:list_id' => 'manifests#show_list'
  get 'manifests' => 'manifests#index'
end
