class StudiesController < ApplicationController
  # The workspace is open to everyone; only saving (notes/highlights/account) needs auth.
  allow_unauthenticated_access only: %i[ index show create update destroy cross_references suggest quick_find search commentary lexicon rabbi rabbi_diagram rabbi_illustration sermon share_card prayer ]

  before_action :set_study, only: %i[ show update destroy suggest quick_find search cross_references commentary lexicon rabbi rabbi_diagram rabbi_illustration sermon share share_card prayer ]

  # Every action below calls a paid AI provider. They need a (free) account, a
  # per-user burst limit, and a per-user daily allowance (AiBudget); AiChat and
  # OpenaiImage add a global daily backstop on top. Guests get a 401 that the
  # Turbo Frame (or JSON caller) renders as a "create an account" prompt.
  AI_ACTIONS = %i[ suggest quick_find rabbi rabbi_diagram rabbi_illustration prayer ].freeze
  AI_FRAMES = {
    suggest: "ai_results", rabbi: "rabbi_drawer",
    rabbi_diagram: "rabbi_diagram_frame", rabbi_illustration: "rabbi_illustration_frame"
  }.freeze
  AI_QUERY_LIMIT = 500 # chars of user-typed text we'll forward to a model

  before_action :require_account_for_ai, only: AI_ACTIONS
  rate_limit to: 20, within: 1.minute, only: AI_ACTIONS, name: "ai-burst",
             by: -> { Current.user&.id || request.remote_ip }, with: -> { ai_refused(:rate, :too_many_requests) }
  before_action :charge_daily_ai_allowance, only: AI_ACTIONS

  # Guests can create studies without an account — keep that from being a
  # free way to fill the database.
  rate_limit to: 30, within: 10.minutes, only: :create, name: "study-create",
             with: -> { redirect_to root_path, alert: "You're creating studies very quickly — please wait a moment." }

  def index
    @studies = authenticated? ? current_user.studies.recent.includes(:panes) : []
    @verse_of_day = DailyVerse.for
    @show_guide = !authenticated? || current_user.guide_dismissed_at.blank?
    @canon_stats = Rails.cache.fetch("home_canon_stats_v1", expires_in: 12.hours) do
      { translations: Translation.count, verses: Verse.count, cross_references: CrossReference.count }
    end
    @testimonials = Testimonials::Testimonial.publishable.featured_first.limit(6)
    if authenticated?
      @active_plan = current_user.reading_plans.recent.first
      @plan_today = @active_plan&.todays_day
    else
      # Visitors get the landing page; the workspace welcome is for keepers.
      render :landing
    end
  end

  def show
    @study.touch_opened!
    @studies = authenticated? ? current_user.studies.recent : []
    # A returning reader with a shelf of studies is a happy one — offer the
    # testimonial widget (the gem throttles: max 2 auto-prompts, 180 days apart).
    testimonial_prompt! if authenticated? && @studies.size >= 2
  end

  def create
    study =
      if authenticated?
        current_user.studies.create!(name: study_name, pane_count: pane_count_param)
      else
        Study.create!(user: nil, name: study_name, pane_count: pane_count_param).tap do |s|
          session[:guest_study_id] = s.id
        end
      end
    # Quick-open from the welcome page: drop the typed reference straight into
    # pane I. Even an unparseable string goes in — the pane renders its own
    # gentle "not found" state, which beats bouncing the visitor back.
    if params[:reference].present?
      study.panes.first&.update(reference: params[:reference].to_s.strip)
    end
    redirect_to study
  end

  def update
    @study.update(study_params)
    @study.sync_panes! if @study.saved_change_to_pane_count?
    redirect_to @study
  end

  def destroy
    @study.destroy
    redirect_to root_path, status: :see_other
  end

  def suggest
    @query = ai_query
    @result = ScriptureSuggester.call(@query)
    render partial: "studies/ai_results", locals: { study: @study, query: @query, result: @result }
  end

  # Preach-mode quick search (JSON): the projection volunteer types anything
  # the preacher mentioned — "the walls of jericho", "azusa street", "the
  # crusaders" — and gets a short projectable explanation card plus validated
  # Scripture references. Verse text still comes only from our own DB.
  def quick_find
    result = PulpitSearch.call(ai_query)
    return render json: { ok: false, error: result.error } unless result.ok?

    render json: {
      ok: true,
      # Model-written prose is reduced to plain text (no injected markup/links).
      topic: PlainText.call(result.topic, limit: 120),
      summary: PlainText.call(result.summary),
      suggestions: result.suggestions.map do |s|
        book = Bible::Canon.find(s.osis)
        {
          reference: s.reference,
          chapter_reference: "#{book&.name || s.osis} #{s.chapter}",
          verse_start: s.verse_start,
          preview: s.preview.to_s.truncate(140)
        }
      end
    }
  end

  def search
    @query = params[:q].to_s
    @translation = Translation.find_by(id: params[:translation_id]) ||
                   Translation.find_by(code: "KJV") || Translation.first
    @results = @translation ? Verse.search(@query, translation: @translation) : Verse.none
    render partial: "studies/search_results",
           locals: { study: @study, query: @query, results: @results, translation: @translation }
  end

  def commentary
    book = Book.find_by_osis(params[:osis])
    return head(:not_found) unless book

    @book = book
    @chapter = params[:chapter].to_i
    @entries = Commentary.for_chapter(book, @chapter)
    render partial: "studies/commentary_results",
           locals: { book:, chapter: @chapter, entries: @entries }
  end

  def lexicon
    @strongs = params[:strongs].to_s.upcase
    @entry = LexiconEntry.lookup(@strongs)
    occurrences = Verse.with_strongs(@strongs)
    @count = occurrences.count
    @samples = occurrences.includes(:book).joins(:book)
                          .order("books.position", "verses.chapter", "verses.verse_number").limit(8)
    render partial: "studies/lexicon_results",
           locals: { study: @study, strongs: @strongs, entry: @entry, count: @count, samples: @samples }
  end

  def share
    return head(:forbidden) unless authenticated? && @study.user_id == current_user.id
    token = @study.ensure_share_token!
    respond_to do |format|
      format.json { render json: { url: shared_study_url(token), token: token } }
    end
  end

  def sermon
    @manuscript = SermonManuscript.new(@study, current_user: authenticated? ? current_user : nil)
    respond_to do |format|
      format.html
      format.md do
        filename = @study.name.to_s.parameterize.presence || "study"
        send_data @manuscript.to_markdown,
                  filename: "#{filename}.md",
                  type: "text/markdown",
                  disposition: "attachment"
      end
    end
  end

  # The "AI Rabbi": explain a highlighted span of Scripture with full-chapter
  # context + cross-references, under strict interpretive guardrails.
  def rabbi
    verses = rabbi_verses
    verse = verses.first
    @selection = ai_query
    @result = RabbiExposition.call(verse:, verses:, selection: @selection, study: @study)
    render partial: "studies/rabbi_results",
           locals: { study: @study, result: @result,
                     verse_id: verse&.id, verse_ids: verses.map(&:id).join(",") }
  end

  # On-demand "Draw this": render just the diagram frame for the Rabbi drawer.
  def rabbi_diagram
    verse = Verse.includes(:book, :translation).find_by(id: params[:verse_id])
    diagram = RabbiDiagram.call(verse:, selection: ai_query, study: @study)
    render partial: "studies/rabbi_diagram", locals: {
      study: @study, verse_id: params[:verse_id], selection: ai_query,
      svg: (diagram.ok? ? diagram.svg : nil), state: (diagram.ok? ? :ready : diagram.error)
    }
  end

  # On-demand "Illustrate this passage": render just the illustration frame with
  # a real, painted picture of the scene (illuminated-manuscript style). Capped at
  # a few generations per user per day so it can't run up an OpenAI bill. The
  # slot is reserved atomically BEFORE the paid call and handed back on failure,
  # so parallel clicks can't overshoot the cap.
  def rabbi_illustration
    verses = rabbi_verses
    quota = IllustrationQuota.for(IllustrationQuota.key_for(current_user))

    unless quota.reserve!
      return render_rabbi_illustration(verses, state: :quota, remaining: 0)
    end

    illustration = RabbiIllustration.call(verse: verses.first, verses:, selection: ai_query,
                                          study: @study, style: params[:style])
    quota.release! unless illustration.ok?

    render_rabbi_illustration(verses,
      image:       (illustration.ok? ? illustration.image : nil),
      caption:     (illustration.ok? ? illustration.caption : nil),
      annotations: (illustration.ok? ? illustration.annotations : nil),
      state:       (illustration.ok? ? :ready : illustration.error),
      style:       illustration.style,
      remaining:   quota.remaining)
  end

  # Metadata for the share modal: the canonical reference, the text to render on
  # the card, and the public share URL. Resolves from either a single verse
  # (verse_id, from the highlight popover) or a passage (osis + chapter [+ range]).
  def share_card
    data = build_share_card
    return head(:not_found) unless data
    render json: data
  end

  # The shareable chapter prayer (AI-composed, cached). Open to everyone; degrades
  # gracefully to ok:false when no provider key is configured.
  def prayer
    book = Book.find_by_osis(params[:osis])
    return head(:not_found) unless book

    chapter = params[:chapter].to_i
    translation = Translation.find_by(code: params[:translation].presence)
    result = ChapterPrayer.call(book:, chapter:, translation:)
    render json: {
      ok: result.ok?, reference: result.reference, prayer: PlainText.call(result.prayer), error: result.error,
      url: passage_url(PassageSlug.slug_for(osis: book.osis_code, chapter:), prayer: 1)
    }
  end

  def cross_references
    book = Book.find_by_osis(params[:osis])
    return head(:not_found) unless book

    translation = Translation.find_by(code: params[:translation].presence) || Translation.find_by(code: "KJV")
    @origin = "#{book.name} #{params[:chapter]}:#{params[:verse]}"
    @rows = CrossReferenceLookup.for_verse(
      book:, chapter: params[:chapter].to_i, verse: params[:verse].to_i, translation:
    )
    @backlinks = authenticated? ? BacklinksLookup.for(
      user: current_user, book: book,
      chapter: params[:chapter].to_i, verse: params[:verse].to_i
    ) : []
    render partial: "studies/xref_results",
           locals: { study: @study, origin: @origin, rows: @rows, backlinks: @backlinks }
  end

  private

  # The highlight popover sends every verse the selection touched (verse_ids),
  # falling back to a single verse_id. Load them all, ordered, same chapter.
  def rabbi_verses
    ids = Array(params[:verse_ids].presence || params[:verse_id]).flat_map { |v| v.to_s.split(",") }
              .map { |s| s.strip.to_i }.reject(&:zero?).uniq
    return [] if ids.empty?
    Verse.includes(:book, :translation).where(id: ids)
         .sort_by { |v| [ v.chapter, v.verse_number ] }
  end

  def ai_query = params[:q].to_s.strip[0, AI_QUERY_LIMIT]

  def require_account_for_ai
    ai_refused(:auth, :unauthorized) unless authenticated?
  end

  def charge_daily_ai_allowance
    ai_refused(:daily, :too_many_requests) unless AiBudget.charge_user(current_user.id)
  end

  # Refuse an AI request in the shape its caller understands: the matching Turbo
  # Frame for the drawer/search UIs (Turbo renders a frame from a 4xx response),
  # JSON for the fetch()-based quick find and prayer.
  def ai_refused(reason, status)
    frame = AI_FRAMES[action_name.to_sym]
    if frame && !request.format.json?
      render partial: "studies/ai_gate", locals: { frame_id: frame, reason: reason }, status: status
    else
      error = { auth: "auth_required", rate: "rate_limited", daily: "daily_limit" }.fetch(reason)
      render json: { ok: false, error: error }, status: status
    end
  end

  def render_rabbi_illustration(verses, image: nil, caption: nil, annotations: nil, state: nil, remaining: nil, style: nil)
    render partial: "studies/rabbi_illustration", locals: {
      study: @study, verse_id: verses.first&.id, verse_ids: verses.map(&:id).join(","),
      selection: ai_query, image:, caption:, annotations:, state:, remaining:,
      style: (style || params[:style])
    }
  end

  def build_share_card
    verse = params[:verse_id].present? &&
            Verse.includes(:book, :translation).find_by(id: params[:verse_id])

    if verse
      book, chapter = verse.book, verse.chapter
      v_start = v_end = verse.verse_number
      translation = verse.translation
      reference = "#{book.name} #{chapter}:#{v_start}"
      text = params[:q].presence || verse.text
    else
      book = Book.find_by_osis(params[:osis])
      return nil unless book

      chapter = params[:chapter].to_i
      v_start = params[:verse_start].presence&.to_i
      v_end   = params[:verse_end].presence&.to_i
      translation = Translation.find_by(code: params[:translation].presence) ||
                    Translation.find_by(code: "KJV")
      verses = Verse.passage(translation:, book:, chapter:, verse_start: v_start, verse_end: v_end)
      return nil if verses.empty?
      reference = passage_reference_label(book, chapter, v_start, v_end)
      text = params[:q].presence || verses.map(&:text).join(" ")
    end

    slug = PassageSlug.slug_for(osis: book.osis_code, chapter:, verse_start: v_start, verse_end: v_end)
    {
      reference:, translation: translation&.name, translation_code: translation&.code,
      osis: book.osis_code, chapter:, text: text.to_s, slug:,
      url: passage_url(slug, t: translation&.code)
    }
  end

  def passage_reference_label(book, chapter, v_start, v_end)
    return "#{book.name} #{chapter}" if v_start.blank?
    label = "#{book.name} #{chapter}:#{v_start}"
    label += "-#{v_end}" if v_end && v_end != v_start
    label
  end

  def set_study
    @study = current_study(params[:id])
  end

  def study_name
    return params[:name] if params[:name].present?
    # Quick-open studies name themselves after the passage ("John 3:16").
    if params[:reference].present?
      parsed = ReferenceParser.call(params[:reference].to_s)
      return parsed.label if parsed.valid?
    end
    "Untitled Study"
  end

  def study_params
    permitted = params.require(:study).permit(:name, :pane_count, :sync_scroll)
    permitted[:pane_count] = permitted[:pane_count].to_i.clamp(1, 4) if permitted[:pane_count].present?
    permitted
  end

  def pane_count_param
    return 4 if params[:pane_count].blank?
    params[:pane_count].to_i.clamp(1, 4)
  end
end
