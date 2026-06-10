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
    get :rabbi, on: :member
    get :sermon, on: :member
    post :share, on: :member
    get :share_card, on: :member
    get :prayer, on: :member
    get "lexicon/:strongs", on: :member, action: :lexicon, as: :lexicon
    resource :live, only: %i[ create update destroy ], controller: "live_sessions"
  end

  # Public "follow along" pages — congregants follow the pulpit live, no login.
  get "/live/:code",         to: "live_sessions#show",    as: :live_session
  get "/live/:code/passage", to: "live_sessions#passage", as: :live_session_passage

  get "/s/:token", to: "shared_studies#show", as: :shared_study

  # Public, no-login share pages for a passage + an optional chapter prayer.
  get "/p/:slug/open", to: "passages#open", as: :open_passage
  get "/p/:slug",      to: "passages#show", as: :passage

  resources :highlights, only: %i[ create update destroy ]

  resource :preferences, only: %i[ update ]

  get    "/guide",         to: "guide#show",    as: :guide
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

  get "/verse_count",      to: "verses#count" # JSON: verses in a book+chapter (for the browser)
  get "/reference_check",  to: "verses#check" # JSON: parse a typed reference (preach quick chase)

  root "studies#index"
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/*
  get "manifest"       => "rails/pwa#manifest",       as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
