# Parallel Scripture

Don't co-author wwith me when you giot commit.

A Bible reader and study workspace in the style of YouVersion. Opt-in Compare lays out up to 4 Scripture
panes side by side to compare **the same verse across translations** or **different verses in
one translation**, with one-click cross-references. Single-user, calm/scholarly aesthetic,
keyboard-driven. Full spec in `PROJECT_BRIEF.md` — read it before non-trivial work.

**Primary user:** one pastor preparing sermons, on a laptop. Every core action must be
reachable in **two clicks or fewer**. Optimize for that flow, not for generality.

---

## Stack (what's actually here — don't assume otherwise)

- **Rails 8.1** / **Ruby 3.4.3** / **PostgreSQL** (`pg`).
- **Hotwire**: Turbo + Stimulus. **No SPA, no React.** This is a hard architectural rule.
- **Tailwind v4, CSS-first.** Config lives in `app/assets/stylesheets/application.tailwind.css`
  via `@import "tailwindcss"` + `@theme { ... }`. **There is no `tailwind.config.js`** — do not
  create one. Custom fonts and the warm palette are defined as `@theme` tokens.
- **JS bundling: esbuild** via `yarn build` (`app/javascript/*` → `app/assets/builds/`). Package
  manager is **yarn**.
- **Testing: Minitest** (`test/`, Rails default) + **Capybara** for system tests. **Do NOT add
  RSpec** — stay consistent with the boilerplate.
- Background jobs / cache / cable: **solid_queue / solid_cache / solid_cable** (DB-backed, Rails 8
  defaults). `jbuilder` for JSON. `brakeman` + `rubocop-rails-omakase` for static analysis.

## Dev commands

```bash
bin/dev                       # start web + esbuild watch + tailwind watch (Procfile.dev)
bin/rails db:prepare          # create + migrate
bin/rails test                # run Minitest unit/integration
bin/rails test:system         # Capybara system tests
bin/rails bibles:seed         # seed translations (idempotent — see Phase 1)
bin/rails bibles:seed_refs    # seed TSK cross-references
bin/rubocop                   # lint (omakase)
bin/brakeman                  # security scan
```

When adding a gem, also update `Gemfile.lock` (`bundle install`). When adding JS deps, use yarn.

---

## Architecture rules (non-negotiable)

1. **Hotwire-first.** Anything that feels "live" is a **Turbo Frame + Stimulus**, never a JS
   framework. Concretely:
   - Each pane is a Turbo Frame (`pane_<pane.id>`). Submitting a pane's form re-renders
     **only that frame**.
   - Translation switch = a `<select>` whose `data-action` triggers a small Stimulus controller
     that submits the pane form.
   - Cross-reference panel = a Turbo Frame inside a right slide-over drawer.
   - Notes auto-save = Stimulus controller, **debounced** `PATCH /studies/:id/panes/:id`.
   - Sync-scroll = pure Stimulus, propagates `scrollTop` ratio to sibling panes when toggled on.
2. **Fat models / thin controllers.** Non-trivial logic goes in **service objects** under
   `app/services/` (parsing, seeding). Controllers orchestrate, render frames.
3. **Stimulus controllers stay small and single-purpose.** One responsibility each.
4. **Tailwind for all styling. No inline styles.**
5. **Tests for every service object and every model scope.** Minitest.

## Data model (see brief §5 for exact columns)

Reference data (seeded once, read-mostly): `Translation`, `Book`, `Verse`, `CrossReference`.
User data: `User` (Rails 8 auth), `Study`, `Pane`, `Highlight`.

- `Verse` unique on `(translation_id, book_id, chapter, verse_number)`; index `(book_id, chapter)`.
- `CrossReference` index on `(from_book_id, from_chapter, from_verse)`, ordered by `votes`.
- `Study` holds `pane_count`, `sync_scroll`, `last_opened_at`; `Pane` holds `position`,
  `translation_id`, `reference` string, `notes`.

## Routes (target — see brief §6.2)

```ruby
resources :studies do
  resources :panes, only: [:update]
  post :duplicate, on: :member
end
resources :highlights, only: [:create, :destroy]
get '/verses/lookup',                  to: 'verses#lookup'          # returns a Turbo Frame
get '/verses/:id/cross_references',    to: 'verses#cross_references'
get '/api/translations',               to: 'translations#index'
get '/api/books',                      to: 'books#index'
root 'studies#index'
```

---

## Build phases — work in order, do NOT skip ahead

Each phase is a checkpoint. Don't start a phase until the previous one passes its acceptance check.
Pause for the user's go-ahead at the gate marked **STOP**.

- **Phase 0 — Setup.** Confirm Rails 8 + Postgres boots. Add custom font (Source Serif Pro) + warm
  palette as Tailwind v4 `@theme` tokens in `application.tailwind.css`. Confirm Minitest baseline
  green. Generate Rails 8 auth: `bin/rails generate authentication`.
- **Phase 1 — Data foundation.** Models `Translation/Book/Verse/CrossReference`. Idempotent
  `bibles:seed` (BSB + KJV first). `ReferenceParser` service **with tests written first**. Seed TSK.
  **STOP** and show: (1) seed task output, (2) ReferenceParser tests passing, (3) console lookup of
  John 3:16 across 4 translations.
- **Phase 2 — Single pane.** `Study` + `Pane` (hardcode `user_id = 1` for now). `studies#show` with
  ONE pane loading a verse. Search form + translation dropdown re-render only the pane's Turbo Frame.
  Style: serif body, generous spacing, muted superscript verse numbers.
- **Phase 3 — Multi-pane.** CSS Grid for 1/2/3/4 panes (4 = 2×2, 3 = top-2 + bottom-1 centered).
  Pane-count selector re-renders the grid. Acceptance: 4 independent verses in 4 panes.
- **Phase 4 — Cross-refs + Notes.** Right slide-over drawer (Turbo Frame), TSK refs ordered by
  votes, "Load in pane N" buttons. Per-pane notes textarea with debounced auto-save.
- **Phase 5 — Highlights + Save Study.** `Highlight` model + selection popover (Stimulus on
  `selectionchange`, 4 pastel colors). Studies sidebar (rename, delete, sort by `last_opened_at`).
  Global keyboard-shortcuts Stimulus controller.
- **Phase 6 — Polish + Auth.** Wire Studies to the real authenticated `User`. Sync-scroll. Empty
  states (no studies, empty pane, verse not found). Loading skeletons during frame nav.
- **Phase 7 — Deploy.** Deploy (Kamal is configured), run seeds in prod once, hand login to pastor.

### Keyboard shortcuts (build in MVP, Phase 5)
`Cmd/Ctrl+K` focus active pane's reference input · `1–4` switch active pane · `Cmd/Ctrl+S` save ·
`Cmd/Ctrl+D` duplicate active pane reference into next empty pane · `X` open cross-ref drawer ·
`Esc` close drawer / unfocus.

---

## Gotchas — these cause the most pain (brief §9)

- **Never depend on a live Bible API in production.** All translations are self-hosted in Postgres.
  External APIs (wldeh, bible-api.com, HelloAO) are one-time seed sources only — they go down and
  rate-limit. On-demand API fallback for un-seeded translations is **Phase 2+, not now**.
- **Copyright is real.** Only public-domain translations may be seeded: **KJV, ASV, BSB, WEB**
  (plus Darby/YLT bonus). **NIV/ESV/NLT/NKJV/MSG are copyrighted — never seed them.** Tell the
  pastor upfront so expectations are aligned.
- **Book naming is a swamp.** Use **OSIS codes internally** (`Gen, Exod, …, Rev`) and maintain a
  single alias map. Different translations abbreviate differently (`Ps`/`Psa`, `Song`/`SS`).
- **The reference parser is the heart.** If it misreads input the whole UX feels broken. **Write
  its tests FIRST.** Cover at least: `Jn 3:16`, `jn 3`, `John 3:16-18`, `1 Cor 1:1`, `1cor1:1`,
  `Song 2:1`, `Psalm 23`, `Ps 23`, `romans 5:1`, plus invalid input.
- **Never fetch verse-by-verse.** Load a chapter in one query:
  `Verse.where(translation:, book:, chapter:).order(:verse_number)`. With proper indexing a
  50-verse chapter is <10ms.

## UI feel — modern reader, YouVersion-style (owner's choice, Oct 2026; supersedes the "Ancient Epistle" parchment look)

The owner found the parchment UI cluttered, hard to navigate and bad on phones, and chose a
**YouVersion-like reader**. Phones matter now (pastors and congregants read on them).

- **Layout**: one passage in a centred column (`.rd-column`, ~36rem), app bar on top
  (`studies/_app_bar`: ☰ · brand · [Passage ▾] [Version ▾] · search; Aa / Compare / Preach / More
  from 1024px), floating prev/next chapter, a phone tab bar (Bible · Notes · Plans · More).
  Compare (2–4 panes) is opt-in; studies default to `pane_count` 1.
- **Sheets** (`sheet` controller per sheet, `sheets` on `<body>` turns clicks into a window
  `sheet:open {id, paneId}`): menu, passage picker, versions, reading settings, More. Bottom sheets
  on a phone, centred cards from 768px.
- **Verse tap → action bar** (`verse_select` on `.ps-workspace`, `verse_actions`): highlight,
  note, compare, copy, share, cross-refs, word study, commentary, Rabbi. Word-selection still goes
  through the highlighter's `.ps-hl-popover`.
- **Design tokens** in `app/assets/stylesheets/ui/tokens.css` (`--ui-*`), themes light / dark /
  sepia / auto on `<body data-theme>` (cookie `ps_theme`, rendered server-side). Fonts: Inter (UI),
  Source Serif 4 (Scripture), EB Garamond (sepia theme), Cinzel only for preach/projector.
- **CSS layout**: `ui/*.css` is the modern layer. Reading-mode rules are scoped to
  `.ps-root:not(.is-presenting, .is-output)`, so **preach / projector / stage keep their legacy
  look** (`preach*.css`, `live.css`, `legacy/*`). New chrome is marked `[data-chrome]` and hidden
  while presenting. The contract preach mode relies on is pinned by
  `test/integration/preach_contract_test.rb` — keep it green.
- Icons: inline SVG via `icon(:name)` (`ReaderHelper::ICONS`, drawn after Lucide, ISC).
- Leaving preach mode never ends a live session (no `preach:exit` relay); "End live" does.

## Beyond-MVP features added (by user request)

- **Passage picker** — the passage sheet (`passage_picker` controller, `studies/_passage_sheet`):
  OT/NT tabs, filter, chapter grid, or type a reference; ⌘K / "/" open it. Browsing is client-side
  (chapter counts from `Bible::Canon`), loading reuses the pane's own Turbo Frame form.
- **AI "Find a Verse"** — describe a thought → the LLM returns *references only*, which we validate
  via `ReferenceParser` and load from our DB (`ScriptureSuggester`, now routed through `AiChat`:
  Gemini first, Abacus RouteLLM fail-over — see `app/services/ai_chat.rb` for keys). The LLM
  never supplies verse text — words always come from our vetted public-domain translations. UI:
  `ai_search` Stimulus controller + `studies/_ai_search` / `_ai_results`; endpoint `GET
  /studies/:id/suggest`. Missing key degrades gracefully to a "configure your key" notice.
  The same service powers the preach-mode **AI quick search**: `GET /studies/:id/quick_find`
  (JSON) — the Go box falls back to it when the reference can't be parsed, and lists
  the results (`_quickFind` in `presentation_controller`). **Results (AI and offline keyword)
  always go to Preview** — the row click / Enter previews; only the row's Go live,
  double-click, Shift+Enter, or L / Go live on Preview change the projector.
- **Offline-first preach** — preach mode parses references on the device (`lib/offline/local_pane`,
  JS port of `ReferenceParser`) and renders passages in a downloaded Bible straight from IndexedDB
  into the pane frame (operator *and* projector/stage), saving the reference in the background
  (outbox when offline). Server calls go through `lib/offline/network.js` (2 s timeout; a timeout
  marks the network "slow" for 3 min, shared with the service worker). AI quick find falls back to
  an on-device keyword search after 3 s ("Offline search (keywords)"). Entering preach auto-downloads
  the study's translations for signed-in users; `preach_offline` badge shows "Ready offline".
- **Start presenting offline (Quick Present)** — each user has one `studies.quick_present` study
  (`QuickPresent.ensure!`, `POST /offline/prepare`, unique per user). `lib/offline/ready.js`, on
  any page load when online (once a day, meta `offlinePreparedAt`), makes it, saves its study /
  `?output=1` / `?stage=1` pages, downloads its Bible and saves the 5 most recent studies (none on
  Data Saver). "Present offline" (home, More sheet, /more, Offline Bibles — `quick_present`
  controller) and offline "New study" open `/studies/:id?present=1&saved=1`: the service worker
  serves the saved copy at once (`saved=1`), the presentation controller enters preach with the Go
  box open. `offline_studies` marks lists "Available offline" / "Needs internet to open". Bible
  search runs on the device offline (`search` controller + `keyword_search`). Precache requests
  carry `X-Offline-Precache` so they don't touch `last_opened_at`.
- **Live follow-along ("Go Live")** — congregants follow the pulpit on their phones in real time.
  Operator: "Go Live" in the preach bar (`live` Stimulus controller) creates a `LiveSession`
  (short join code + QR via `rqrcode`) and PATCHes preach state to `/studies/:id/live`; the server
  rebroadcasts over Action Cable (`LiveSessionChannel`, one stream per code). Followers:
  `/live/:code` (public, anonymous — `ApplicationCable::Connection` allows guests) with
  `live_follow` Stimulus controller: emphasised current verse, auto-scroll, "Jump to live" pill,
  ended overlay linking to `/p/:slug/open`. Preach mode emits `preach:state` / `preach:exit`
  window events that the live controller relays; the dual-screen output window
  (`?output=1`, BroadcastChannel) is same-device only and unrelated to cable.
  `LiveSession#passages` (jsonb) logs each chapter preached (`log_passage!`, consecutive dedup);
  the ended overlay fetches `/live/:code/recap` — "tonight's scriptures" with `/p/:slug/open` links.
- **Preach queue ("setlist")** — `SetlistItem` (study-scoped; kind enum scripture/song/thought;
  scripture validates through `ReferenceParser`, song/thought split `body` into stanzas on blank
  lines). **Local-first** (Nov 2026): the `setlist` controller keeps the queue on the device
  (IndexedDB meta `setlist:<study>`), renders it itself and syncs through the outbox
  (`setlist-create/-update/-destroy/-order` ops; items carry a `client_id`, so replays are
  idempotent and URLs may name `tmp-…` ids; `PATCH /studies/:id/setlist/order` takes the whole
  order). On load the frame's `data-items` + device copy + pending ops merge
  (`lib/offline/setlist_state.js`, node-tested). Several references at once are parsed on the
  device. Pictures still upload through the Turbo Frame form. In preach mode the queue docks as
  a column ≥1100px (`is-queue-open`), topped by the operator console (`preview` controller):
  red LIVE · amber PREVIEW (+ Go live, `L`) · NEXT · chapter verse list (`GET /verse_chapter`
  only when the Bible isn't downloaded). Click previews, double-click / Enter-on-preview goes
  live; Go box Shift+Enter previews. What goes live is auto-added (setting, default on).
  Keys: `?` card in preach (`data-preach-keys`). Clicking an item dispatches
  `setlist:present`; the presentation controller chases scriptures or projects **content slides**
  (`is-slide`, `[data-preach-slide]` layer, next/prev walk stanzas). Slides flow to the output
  window (BroadcastChannel `slide` field) and to live followers (`kind=slide` + `slide_*` columns
  on `live_sessions`; the follower page renders stanzas client-side).
- **Song bank** (Nov 2026) — songs carry EasyWorship-style section labels (`[Verse 1]`, `[Chorus]`,
  `Chorus:` …) and an optional `setlist_items.arrangement` ("V1 C V2 C B C"); `SongSheet`
  (Ruby) and `lib/song_sheet.js` (device) turn words + order into slides with the same rules
  (shared cases in `test/fixtures/files/song_sheet_cases.json`). No labels = stanza by stanza as
  before; verses + one chorus = the chorus after every verse. Labels show to the operator/stage,
  never on the projector; live followers get the projected words (`projectedBody`). The built-in
  public-domain hymnal is `config/hymnal.yml` (`Hymnal::HYMNS`, copyright rule + `BLOCKLIST` in
  `app/services/hymnal.rb`). `song_bank` controller = the searchable picker (on-device search over
  the cached `GET /studies/:id/setlist/library`, also saved by "Get ready for Sunday");
  `song_editor` controller = paste/.txt tidy (`lib/song_import.js`), flow line, "Save to my songs"
  (`Song` model, `POST /songs` upsert by title, via the outbox so it works offline).
- **Slide tools** (Nov 2026, phase 2B) — a tool strip in the queue (`studies/_queue_tools`) opens
  self-contained dialogs (`studies/_slide_tools`, one Stimulus controller each, window event
  `queue-tool:open {tool, item?}`; meant to become library tabs later). New `SetlistItem` kinds
  carry structured `data` (jsonb, cleaned by `SlideData`): **scripture_set** (`scripture_set`
  controller — "Col 2:2; Matt 28:19 BSB" → several references, each in its own Bible, on one slide;
  words from the downloaded Bible or `GET /verse_passage`, stored in the item so it projects
  offline; `lib/slides/scripture_set.js` lays out / auto-splits), **presentation**
  (`presentation_import` — PDF via vendored pdf.js `public/vendor/pdfjs-4.10.38/`, or pictures;
  pages are JPEGs in the device's own IndexedDB `ps-slides` (`lib/slides/deck_store.js`), never
  uploaded; the item only holds the deck key + page count) and **seminar** (`seminar_builder` —
  title / points / picture / quote / section layouts, speaker notes, reveal points one by one;
  "Seminar mode" hides the verse-only preach tools and makes the stage a presenter view with notes
  + timer). All three project through the normal slide path as `rich = {type, data}`
  (`lib/slides/rich_slides.js`), so screen looks apply. **Song collections** (`SongCollection`,
  titles by name, `PUT /song_collections/:client_id`) live in the song bank sidebar; **service
  templates** (`ServiceTemplate`, `PUT /service_templates/:client_id`, `POST …/start` makes a new
  study) and the **order of service** (copy for WhatsApp / share / print, built on the device).
  Collections and templates are cached on the device and saved through the outbox
  (`queueRecordSave`), so they work offline. Pure logic is node-tested (`test/javascript/slides_test.mjs`).
- **Root word projection** (Nov 2026) — "the Greek word here is agapē…" on the big screen. Preach
  mode: `W` / bar's ℵ Root word (live verse), `Shift+W` / ℵ in the Preview row (previewed verse) open
  the `root_words` card (self-contained popover, `studies/_root_words`): the verse's Strong's-tagged
  KJV words (other translations map through the KJV verse), lemma in Hebrew/Greek, transliteration,
  say-it guide, Strong's no., short meaning (`GLOSSES` + derived from Open Scriptures text —
  `lib/root_words.js`, node-tested), count. Project = a word-study **slide** (`slide.word`, body =
  the study as JSON) through `presentation#_presentSlide`, so projector/stage/phones get it
  (`live_sessions.slide_word`); queue items are `setlist_items.kind = word` (enum 7, word study JSON in `body`). Ask Rabbi:
  `POST /root_words/explain` (`RootWordExplainer`, cached, editable, labelled AI). Data:
  `GET /root_words/:osis/:ch/:v`; offline = `RootWordPack` (`/root_words/pack`, ~2.3 MB gz, KJV
  tokens + lexicon) in IndexedDB (`lib/offline/word_pack.js`, books store code `~strongs`),
  saved on entering preach. Fonts: bundled OFL subsets in `app/assets/fonts/root_words/`.
- **Stage display** — `?stage=1` window (`⌗ Stage` button): NOW small / NEXT big / clock, painted
  by `_paintStage()` from the same BroadcastChannel state; hello role `"stage"` so it never flips
  the operator into console mode.
- **Projection screen prefs** — `✦ Screen` panel: theme (vellum/ink/paper → `out-theme-*` classes
  on the output root) + text scale (`--ps-out-scale`), persisted in localStorage, broadcast as
  `{type:"screen"}` and re-sent on output hello.
- **Phone remote** — `☎ Remote` mints a secret 6-char pairing code + QR (`RemotesController#create`,
  nothing persisted); phone opens `/remote/:code` (`remote_pad` Stimulus controller) and both ends
  join `RemoteChannel` (pure relay with presence ping). Pad commands (next/prev/chase) reach the
  presentation controller as `preach:command` window events. The code is never shown on the
  projector — only the holder of the QR can drive the screen.
- **Admin ("Overseer")** — `/admin`, `users.admin` flag (`bin/rails admin:grant EMAIL=...`),
  read-only overview: totals, live-now sessions, recent accounts/studies/live services.

## Access model — open app, gated saves (by user request)

The workspace is **open to guests**; only *saving* requires an account.
- **Guests** get a session-scoped study (`Study.user_id` is nullable; the id lives in
  `session[:guest_study_id]`). They can create studies, look up verses, switch translations,
  use cross-references, AI find, and the book browser — all without logging in.
- **Gated (require an account)**: notes auto-save (`panes#update` with `autosave` → 401 for
  guests), highlights (`highlights#*` → 401 for guests). The front-end listens for a 401 and
  dispatches a `auth:required` window event; `auth_gate` Stimulus controller opens a
  "create an account to save" modal.
- **Registration**: `RegistrationsController` (`resource :registration`) + a styled sign-up page.
  On sign-in *or* sign-up, `claim_guest_study` adopts the guest's session study into the new
  account and redirects there, so guests never lose work.
- `current_study(id)` in `ApplicationController` resolves owner-or-guest and 404s otherwise.
  Controllers use `allow_unauthenticated_access` for read paths; writes check `authenticated?`.

## Out of scope (don't build)

Real-time collaboration · native apps (the web reader is responsive down to phones) ·
audio/video · social/sharing · copyrighted translations.
