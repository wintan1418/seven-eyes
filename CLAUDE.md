# Parallel Scripture

Don't co-author wwith me when you giot commit.

A desktop-first, multi-pane Bible study workspace. The pastor lays out up to 4 Scripture
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
   - Each pane is a Turbo Frame (`pane_0`…`pane_3`). Submitting a pane's search form re-renders
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

## UI feel — "Ancient Epistle" design system (supersedes brief §7)

The approved design is a **vellum / illuminated-manuscript aesthetic**, not the brief's plain
off-white. The canonical design lives in `design/` (HTML + JSX artboards + `scripture-styles.css`).
The CSS system is ported verbatim into `app/assets/stylesheets/scripture.css` and is the **styling
layer** — markup uses the `.ps-*` component classes (`.ps-root`, `.ps-topbar`, `.ps-pane`,
`.ps-verses`, `.ps-drawer`, etc.). Tailwind utilities are available for incidental layout and the
palette/fonts are also exposed as `@theme` tokens in `application.tailwind.css`.

- **Fonts** (loaded via Google Fonts in the layout): verse + body **EB Garamond** (serif, 18px,
  line-height 1.72); UI chrome / labels **Cinzel** (uppercase, wide tracking); illuminated drop caps
  **UnifrakturMaguntia**.
- **Palette** (CSS vars in `scripture.css :root`): vellum backgrounds `--vellum-0..2`, ink `--ink`,
  sepia text, **rubric red** `--rubric (#8a2418)` for verse numbers/accents, **gold** `--gold`
  hairlines. Highlights are 4 soft over-vellum tints: ochre, sage, cobalt, rose (`.hl-*`).
- **Signature touches**: vellum fiber texture (layered gradients on `.ps-root`), gold hairline frame
  inside each pane, Roman-numeral pane indices (I–IV), rubric drop cap on the first verse, dashed
  sepia rules. Keep it calm and scholarly — "an ancient epistle," generous spacing, never cram.
- Six artboards in `design/scripture-artboards.jsx` show every state: Scriptorium welcome, New Codex
  modal, 4-translation compare, cross-ref drawer, the Justification florilegium, sync-scroll +
  shortcut hint. **Match these when building each phase's UI.**

## Out of scope (don't build)

Real-time collaboration · mobile-first (desktop-first; tablet-landscape responsive is enough) ·
audio/video · social/sharing · copyrighted translations.
