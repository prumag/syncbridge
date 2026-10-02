Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  resources :sync_runs, only: %i[index create]
  resources :attendees, only: :index
end
