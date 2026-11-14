Rails.application.routes.draw do
  mount Testimonials::Engine => "/testimonials"
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
    post :rabbi_diagram, on: :member
    post :rabbi_illustration, on: :member
    get :sermon, on: :member
    post :share, on: :member
    get :share_card, on: :member
    get :prayer, on: :member
    get "lexicon/:strongs", on: :member, action: :lexicon, as: :lexicon
    get :quick_find, on: :member
    resource :live, only: %i[ create update destroy ], controller: "live_sessions"
    resource :remote, only: %i[ create ], controller: "remotes"
    resources :setlist_items, only: %i[ index create update destroy ], path: "setlist" do
      patch :order, on: :collection
      post :move, on: :member
      get :library, on: :collection
    end
  end

  resources :songs, only: %i[ create destroy ]
  # Song bank collections and saved service orders, keyed by the device's id.
  resources :song_collections, only: %i[ update destroy ]
  resources :service_templates, only: %i[ index update destroy ] do
    post :start, on: :member
  end

  # Public "follow along" pages — congregants follow the pulpit live, no login.
  get "/live/:code",         to: "live_sessions#show",    as: :live_session
  get "/live/:code/passage", to: "live_sessions#passage", as: :live_session_passage
  get "/live/:code/recap",   to: "live_sessions#recap",   as: :live_session_recap

  # Phone remote pad — pairs with the operator console over a secret code.
  get "/remote/:code", to: "remotes#show", as: :remote_pad

  get "/admin", to: "admin#show", as: :admin
  post "/admin/daily_word/regenerate", to: "admin#regenerate_daily_word", as: :admin_regenerate_daily_word

  # Glossary of the Faith: public pages show reviewed terms only; the review
  # desk (admins + reviewers) edits drafts and marks them reviewed.
  get "/faith",       to: "faith_terms#index", as: :faith_terms
  get "/faith/:slug", to: "faith_terms#show",  as: :faith_term
  scope "/admin/faith", controller: "faith_term_reviews" do
    get    "/",             action: :index,    as: :admin_faith_terms
    get    "/:slug/edit",   action: :edit,     as: :edit_admin_faith_term
    patch  "/:slug",        action: :update,   as: :admin_faith_term
    post   "/:slug/review", action: :review,   as: :review_admin_faith_term
    delete "/:slug/review", action: :unreview
    post   "/:slug/rewrite", action: :rewrite, as: :rewrite_admin_faith_term # AI suggestion, saves nothing
  end

  get "/s/:token", to: "shared_studies#show", as: :shared_study

  # Public, no-login share pages for a passage + an optional chapter prayer.
  get "/p/:slug/open", to: "passages#open", as: :open_passage
  get "/p/:slug",      to: "passages#show", as: :passage

  # Word for Today: today's passage + AI reflection, past days, share JSON.
  get "/today", to: "daily_words#show", as: :today
  constraints date: /\d{4}-\d{2}-\d{2}/ do
    get "/today/:date",        to: "daily_words#show",   as: :daily_word
    get "/today/:date/card",   to: "daily_words#card",   as: :daily_word_card, defaults: { format: :json }
    get "/today/:date/prayer", to: "daily_words#prayer", as: :daily_word_prayer, defaults: { format: :json }
  end

  # Audio Bible: cached per-chapter narration (JSON status + playable URL).
  get "/audio/chapter", to: "audio_chapters#show", as: :audio_chapter
  get "/audio/sample", to: "audio_chapters#sample", as: :audio_sample

  resources :highlights, only: %i[ create update destroy ]

  # "Report this answer" on AI-generated content (Play AI-content policy).
  resources :ai_reports, only: %i[ create ]

  resource :preferences, only: %i[ update ]

  get    "/whats-new",     to: "whats_new#show", as: :whats_new
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

  # Mobile apps (Hotwire Native): the Bible tab, the More tab, path rules, and
  # the files that let bibliorata.com links open in the apps.
  get "/read", to: "read#show", as: :read
  get "/more", to: "more#show", as: :more
  get "/search", to: "search#show", as: :search
  get "configurations/ios_v1.json",     to: "configurations#ios_v1",     defaults: { format: :json }
  get "configurations/android_v1.json", to: "configurations#android_v1", defaults: { format: :json }
  get ".well-known/assetlinks.json", to: "well_known#assetlinks", defaults: { format: :json }
  get ".well-known/apple-app-site-association", to: "well_known#apple_app_site_association", defaults: { format: :json }
  get "apple-app-site-association", to: "well_known#apple_app_site_association", defaults: { format: :json }

  # Offline reading: downloads page, Bible bundles for IndexedDB, own highlights.
  get "/offline",              to: "offline#show",       as: :offline
  # The offline reader is drawn by the service worker (lib/offline/shell.js);
  # without one (or with ?sw=off) these addresses just open the Bible.
  get "/offline/read(/*rest)", to: redirect("/read"), as: :offline_reader
  get "/offline/bibles",       to: "offline#manifest",   as: :offline_bibles, defaults: { format: :json }
  get "/offline/bibles/:code", to: "offline#bible",      as: :offline_bible, defaults: { format: :json }
  get "/offline/highlights",   to: "offline#highlights", as: :offline_highlights, defaults: { format: :json }
  post "/offline/prepare",     to: "offline#prepare",    as: :offline_prepare, defaults: { format: :json }

  # Root word projection (preach mode): Strong's words for a verse, the offline word pack, Ask Rabbi.
  get "/root_words/pack",                   to: "root_words#pack",      as: :root_words_pack, defaults: { format: :json }
  get "/root_words/pack/info",              to: "root_words#pack_info", as: :root_words_pack_info, defaults: { format: :json }
  post "/root_words/explain",               to: "root_words#explain",   as: :root_words_explain, defaults: { format: :json }
  get "/root_words/:osis/:chapter/:verse",  to: "root_words#verse",     as: :root_words_verse, defaults: { format: :json },
                                            constraints: { osis: /[1-3]?[A-Za-z]+/, chapter: /\d+/, verse: /\d+/ }

  get "/verse_count",      to: "verses#count" # JSON: verses in a book+chapter (for the browser)
  get "/verse_chapter",    to: "verses#chapter" # JSON: a reference's whole chapter (queue preview)
  get "/verse_passage",    to: "verses#passage" # JSON: a reference's words in one translation (scripture slide composer)
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

  # ---- Account & legal (security/commercial basics) --------------------------
  resource :account, only: %i[ show destroy ] do
    get :export, on: :member
  end
  get "/terms",   to: "legal#terms",   as: :terms
  get "/privacy", to: "legal#privacy", as: :privacy
  get "/delete-account", to: "legal#delete_account", as: :delete_account

  # Sources & licences for every translation and dataset (required attributions).
  get "credits" => "credits#show", as: :credits
end
