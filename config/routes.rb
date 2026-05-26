Rails.application.routes.draw do
  resource :session
  resource :registration, only: %i[ new create ]
  resources :passwords, param: :token

  resources :studies, only: %i[ index show create update destroy ] do
    resources :panes, only: %i[ update ]
    get :suggest, on: :member
    get :search, on: :member
    get :cross_references, on: :member
    get :commentary, on: :member
    get :sermon, on: :member
    get "lexicon/:strongs", on: :member, action: :lexicon, as: :lexicon
  end

  resources :highlights, only: %i[ create update destroy ]

  resource :preferences, only: %i[ update ]

  post   "/guide/dismiss", to: "guide#dismiss", as: :dismiss_guide
  delete "/guide/dismiss", to: "guide#restore", as: :restore_guide

  resources :reading_plans do
    member do
      get :open_today
    end
    resources :plan_days, only: %i[ update ], path: "days" do
      member do
        post   :complete
        delete :complete, action: :uncomplete, as: :uncomplete
      end
    end
  end

  get "/verse_count", to: "verses#count" # JSON: verses in a book+chapter (for the browser)

  root "studies#index"
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
