# frozen_string_literal: true

Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  root "tickets#index"

  resources :tickets do
    member do
      patch :update_status
      patch :update_priority
      patch :assign
      post  :add_message
      post  :customer_reply
      post  :reopen_issue
      post  :simulate_time
    end

    collection do
      get  :customer_portal
      post :run_auto_close
      post :reset_seed_data
      get  :presentation_defense
    end
  end

  resources :agents, only: [:index]
end
