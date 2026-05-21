# Project Brief — Parallel Scripture

A multi-pane Bible study tool for verse comparison and cross-reference exploration.

- **Stakeholder:** Juwon Oluwadare Joshua — building for his pastor (primary user).
- **Stack:** Rails 8 + Hotwire (Turbo/Stimulus) + Tailwind CSS + PostgreSQL.
- **Starting point:** existing Rails boilerplate (Juwon's standard setup).
- **Target handover:** Claude Code (terminal-based agentic execution).
- **Build estimate:** MVP 5–7 days focused work · Full v1: 2–3 weeks.

## 1. Core concept

The pastor needs a workspace to lay out multiple Scripture views side by side and compare them
at a glance — like four Bibles open on a desk, but faster, searchable, with cross-references one
click away. Two comparison modes drive the UX:

- **Same verse, different translations** — John 3:16 in KJV, NIV, ESV, Greek interlinear side by side.
- **Different verses, same/mixed translation** — Romans 5:1 next to Galatians 2:16 next to Ephesians 2:8.

**Why it matters:** existing tools (YouVersion, Logos, Blue Letter Bible) either don't do clean
4-pane comparison, are paid/heavy, or have clunky web UIs. A focused Hotwire app with crisp,
keyboard-driven controls fills a real niche for sermon prep.

## 2. The pastor's workflow

**Scenario — Sunday sermon prep on "justified by faith":**

1. Opens app → empty workspace with a "New Study" button.
2. New Study → 2×2 grid of empty panes, each with a search bar.
3. Pane 1: types "Romans 5:1" + ESV → loads.
4. Pane 2: same reference, switch to KJV → compares wording.
5. Pane 3: clicks "cross-references" on Romans 5:1 → picks Galatians 2:16 → loads.
6. Pane 4: types "Ephesians 2:8-9" + ESV → loads vv. 8–9.
7. Save Study → names it "Justification — Sept 14 sermon" → pinned to sidebar.
8. Next morning reopens it, same layout, adds highlighted notes per pane.

**Design principle:** every action above reachable in **two clicks or fewer**. The pastor is
studying Scripture, not learning the UI.

## 3. Feature scope

### 3.1 MVP (must ship)

| Feature | Details |
|---|---|
| Multi-pane workspace | 1/2/3/4 panes, default 4 (2×2). Each pane independent — own verse, translation, scroll. |
| Verse lookup | Per-pane search accepting natural refs: `Jn 3:16`, `John 3:16-18`, `Rom 5`. |
| Translation switcher | Per-pane dropdown. Min 4: KJV, ASV, BSB, WEB. Interlinear later. |
| Synchronized scroll | Toolbar toggle. When ON + same reference, scrolling one scrolls all. Default OFF. |
| Cross-references | Click verse → side panel with TSK refs → click loads into chosen pane. |
| Save Study | Persists pane config (count, references, translations) under a name. Restorable from sidebar. |
| Notes per pane | Textarea below each pane, auto-saves to Study. Markdown-light (bold, lists). |
| Highlighting | Select text → mini popover → 4 colors. Persists per user per verse. |
| Auth | Rails 8 built-in `generate authentication`. Single-user account. |

### 3.2 Post-MVP (v1.1+)

Word study (Strong's), full-text Bible search, PDF export (Prawn/Grover), reading plans,
public-domain commentaries (Matthew Henry, JFB via HelloAO), Study tags + search, dark mode.

### 3.3 Explicitly NOT in scope

Real-time multi-user collaboration · mobile-first design (desktop-first; tablet-landscape only) ·
audio/video · social/sharing/comments · copyrighted modern translations (NIV/ESV).

## 4. Bible API strategy

**The single most important architectural decision.**

### 4.1 Recommendation
Self-host Bible text in PostgreSQL; fetch cross-references from a static dataset. **Do NOT depend
on a live API for verse lookups.** Bible text is finite (~31,000 verses/translation), public-domain
translations are free to embed, data is read-mostly. Seeding the DB once gives instant lookups,
full-text search, no rate limits, no outages.

### 4.2 Translation sources (free, redistributable)

| Translation | Status | Source | Why |
|---|---|---|---|
| KJV | Public domain | wldeh/bible-api (jsDelivr) or scrollmapper | Most likely already known |
| ASV | Public domain | scrollmapper, wldeh | Classic, literal |
| BSB (Berean Standard) | Public domain (2023) | HelloAO (bible.helloao.org) | Flagship modern free translation |
| WEB | Public domain | HelloAO, bible-api.com | Modern update of ASV |
| Darby, YLT | Public domain | scrollmapper, dailybible.ca | Bonus literal translations |
| Greek (TR/SBLGNT) | PD / CC | STEPBible, scrollmapper | NT word study — Phase 2 |
| NIV/ESV/NLT/NKJV | **COPYRIGHTED — skip** | — | Require licensing |

### 4.3 Cross-reference data
Treasury of Scripture Knowledge (TSK) — public domain, ~340,000 verse-to-verse refs. Cleanest
digitization: OpenBible.info → `cross_references.txt` (TSV). Format: `FromVerse | ToVerse(s) | Votes`.
Filter votes ≥ 0 in the seed.

### 4.4 Seeding strategy
1. Download raw text per translation (scrollmapper/bible_databases or wldeh/bible-api). Commit
   sources into `db/seeds/bibles/`.
2. Single Rake task `bibles:seed` ingests JSON/CSV. Idempotent (skips already-seeded translations).
3. Download TSK file. Seed via `bibles:seed_refs`.
4. PostgreSQL `pg_trgm` + GIN index on verse text for fast full-text search later.

**API fallback:** if the pastor later wants e.g. a Yoruba translation not held locally, build a thin
Rails service fetching from HelloAO on demand and caching into the DB. **Phase 2 — not now.**

## 5. Data model

```
# Reference data (read-mostly, seeded once)
Translation: code[unique] (KJV/ASV/BSB/WEB), name, language, license
Book:        osis_code[unique], name, testament(:old/:new), position(1..66), chapter_count
Verse:       translation_id, book_id, chapter, verse_number, text
             [unique: translation_id+book_id+chapter+verse_number] [index: book_id+chapter]
CrossReference: from_book_id, from_chapter, from_verse,
                to_book_id, to_chapter_start, to_verse_start, to_chapter_end?, to_verse_end?,
                votes  [index: from_book_id+from_chapter+from_verse]

# User data
User (Rails 8 auth): email_address, password_digest
Study:     user, name, pane_count(1..4), sync_scroll(default false), last_opened_at
Pane:      study, position(0..3), translation_id, reference("Romans 5:1-11"), notes
Highlight: user, verse, color(:yellow/:green/:blue/:pink), char_start, char_end, created_at
```

## 6. Architecture & Rails decisions

### 6.1 Hotwire-first, no SPA
- Each pane is a Turbo Frame (`pane_0`…). Pane search submit re-renders only that frame.
- Translation switch = `<select>` `data-action` → Stimulus submits the pane form.
- Cross-ref panel = Turbo Frame in a slide-over drawer.
- Auto-save notes = debounced Stimulus `PATCH /panes/:id`.
- Sync-scroll = Stimulus propagating `scrollTop` ratio to siblings when toggle is on.

### 6.2 Routes
```ruby
resources :studies do
  resources :panes, only: [:update]
  post :duplicate, on: :member
end
resources :highlights, only: [:create, :destroy]
get '/verses/lookup',               to: 'verses#lookup'
get '/verses/:id/cross_references', to: 'verses#cross_references'
get '/api/translations',            to: 'translations#index'
get '/api/books',                   to: 'books#index'
root 'studies#index'
```

### 6.3 Gems
solid_queue + solid_cache (Rails 8 defaults) · `pg_search` (Postgres tsvector full-text) ·
`annotate_rb` (schema docs) · `dotenv-rails` (dev env) · **Minitest + Capybara** (boilerplate
default — stay consistent; do not add RSpec).

### 6.4 Reference parser (custom service)
```ruby
# app/services/reference_parser.rb
class ReferenceParser
  Result = Struct.new(:book, :chapter, :verse_start, :verse_end, :valid?)
  def initialize(input) = @input = input.to_s.strip
  def call
    # 1. Normalize: lowercase, collapse whitespace, handle '1 cor', 'jn'
    # 2. Match against regex with named captures
    # 3. Resolve book abbreviation to a Book record (fixed alias map)
    # 4. Return Result struct
  end
end
```

## 7. UI / UX spec

### 7.1 Layout
Single-page workspace: **Top bar** (h-12: app name | editable Study name | pane-count selector,
sync toggle, save, menu) · **Sidebar** (w-64 collapsible: saved Studies + New Study) · **Main grid**
(CSS Grid, 1/2/3/4 panes; 4 = 2×2; 3 = top-2 + bottom-1 centered) · **Each pane** (search + dropdown
on top, scrollable verses middle, collapsible notes bottom) · **Cross-ref drawer** (w-80 slide-in
from right, closes on Esc / click-outside).

### 7.2 Visual style
Calm, scholarly — "desk reading lamp, not SaaS dashboard." Verse text serif (Source Serif Pro /
Lora / Crimson Pro), 18px, line-height 1.7; UI chrome Inter. Palette: bg `#FAF7F2`, headings
`#1B3A5C`, accent `#9A6E47`. Verse numbers muted-grey sticky superscript. Highlights soft pastels
~40% opacity (yellow/mint/sky/rose), never saturated. Generous spacing, pane padding p-6.

### 7.3 Keyboard shortcuts (MVP)
`Cmd/Ctrl+K` focus reference input · `1–4` switch active pane · `Cmd/Ctrl+S` save ·
`Cmd/Ctrl+D` duplicate active pane reference into next empty pane · `X` open cross-ref drawer ·
`Esc` close drawer / unfocus.

## 8. Build phases (do in order — clean checkpoints)

- **Phase 0 — Setup (30 min):** confirm Rails 8 + Postgres; Tailwind theme (font + warm palette);
  confirm Minitest baseline green; `bin/rails generate authentication`.
- **Phase 1 — Data foundation (1 day):** models; idempotent `bibles:seed` (BSB + KJV first);
  console lookup < 50ms; seed TSK; `ReferenceParser` with tests first.
- **Phase 2 — Single pane (1 day):** `Study` + `Pane` (hardcode user_id=1); `studies#show` one pane;
  search + translation dropdown re-renders only the pane frame; Tailwind serif styling.
- **Phase 3 — Multi-pane (1 day):** `pane_count` (1..4); CSS Grid N panes; pane-count selector
  re-renders grid. Acceptance: 4 independent verses.
- **Phase 4 — Cross-refs + Notes (1 day):** slide-over drawer Turbo Frame; TSK refs by votes;
  "Load in pane" buttons; debounced notes auto-save.
- **Phase 5 — Highlights + Save (1 day):** Highlight model + selection popover; Studies sidebar
  (rename/delete/sort by last_opened_at); global keyboard-shortcuts controller.
- **Phase 6 — Polish + Auth (½ day):** real authenticated User; sync-scroll; empty states; skeletons.
- **Phase 7 — Deploy:** deploy (Kamal configured); run seeds in prod once; hand login to pastor.

## 9. Things to watch out for

- **Don't depend on a live Bible API in production.** Seed everything; APIs are seed-time / fallback only.
- **Copyright is real.** NIV/ESV/NLT/NKJV/MSG cannot be seeded. Stick to BSB/KJV/ASV/WEB for MVP and
  set the pastor's expectations upfront.
- **Book naming is a swamp.** Use OSIS internally (`Gen, Exod, …, Rev`); maintain one alias map.
- **The reference parser is the heart.** Write its tests FIRST. Cover `Jn 3:16`, `jn 3`, `1 Cor 1:1`,
  `1cor1:1`, `Song 2:1`, `Psalm 23`, `Ps 23`, invalid input.
- **Performance:** load a chapter in one query
  (`Verse.where(translation:, book:, chapter:).order(:verse_number)`), never verse-by-verse.

## 10. Initial prompt for Claude Code

> We are building "Parallel Scripture", a Rails 8 + Hotwire Bible study app for my pastor. He needs
> to view up to 4 verses side-by-side and compare translations + cross-references in a calm, focused
> workspace. Full spec is in `PROJECT_BRIEF.md`. Read it end-to-end before starting. Pay particular
> attention to §4 (Bible API — self-host in Postgres), §5 (data model), §6 (Hotwire-first, no SPA),
> §8 (build phases — in order). Start with Phase 0 and Phase 1. Do NOT skip ahead. After Phase 1,
> stop and show me: (1) seed Rake task output, (2) ReferenceParser tests passing, (3) a console
> session looking up John 3:16 across 4 translations. Then wait for go-ahead on Phase 2.
> Style: Rails conventions, fat models / thin controllers, service objects for non-trivial logic.
> Tailwind for all styling, no inline styles. Small single-purpose Stimulus controllers. Tests for
> every service object and model scope.
