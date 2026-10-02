Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  root "status#show"
  get "status" => "status#show"

  resources :sync_runs, only: %i[index create]
  resources :attendees, only: :index
end
