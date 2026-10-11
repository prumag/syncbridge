Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  root "status#show"
  get "status" => "status#show"
  get "runs/:id" => "status#run", as: :run

  resources :sync_runs, only: %i[index create]
  resources :attendees, only: :index
end
