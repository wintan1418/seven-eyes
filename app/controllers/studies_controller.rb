class StudiesController < ApplicationController
  # The workspace is open to everyone; only saving (notes/highlights/account) needs auth.
  allow_unauthenticated_access only: %i[ index show create update destroy cross_references suggest quick_find search commentary lexicon rabbi sermon share_card prayer ]

  before_action :set_study, only: %i[ show update destroy suggest quick_find search cross_references commentary lexicon rabbi sermon share share_card prayer ]

  def index
    @studies = authenticated? ? current_user.studies.recent : []
    @verse_of_day = DailyVerse.for
    @show_guide = !authenticated? || current_user.guide_dismissed_at.blank?
    if authenticated?
      @active_plan = current_user.reading_plans.recent.first
      @plan_today = @active_plan&.todays_day
    end
  end

  def show
    @study.touch_opened!
    @studies = authenticated? ? current_user.studies.recent : []
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
    @query = params[:q].to_s
    @result = ScriptureSuggester.call(@query)
    render partial: "studies/ai_results", locals: { study: @study, query: @query, result: @result }
  end

  # Preach-mode quick search (JSON): the projection volunteer types a described
  # thought or event ("the walls of Jericho falling") and gets back validated
  # references to chase. The AI returns references only — the projected words
  # still come from our own DB.
  def quick_find
    result = ScriptureSuggester.call(params[:q].to_s)
    return render json: { ok: false, error: result.error } unless result.ok?

    render json: {
      ok: true,
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
    verse = Verse.includes(:book, :translation).find_by(id: params[:verse_id])
    @selection = params[:q].to_s
    @result = RabbiExposition.call(verse:, selection: @selection, study: @study)
    render partial: "studies/rabbi_results", locals: { study: @study, result: @result }
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
      ok: result.ok?, reference: result.reference, prayer: result.prayer, error: result.error,
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
    params[:name].presence || "Untitled Study"
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
