class StudiesController < ApplicationController
  # The workspace is open to everyone; only saving (notes/highlights/account) needs auth.
  allow_unauthenticated_access only: %i[ index show create update destroy cross_references suggest search commentary lexicon ]

  before_action :set_study, only: %i[ show update destroy suggest search cross_references commentary lexicon ]

  def index
    @studies = authenticated? ? current_user.studies.recent : []
    @verse_of_day = DailyVerse.for
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

  def cross_references
    book = Book.find_by_osis(params[:osis])
    return head(:not_found) unless book

    translation = Translation.find_by(code: params[:translation].presence) || Translation.find_by(code: "KJV")
    @origin = "#{book.name} #{params[:chapter]}:#{params[:verse]}"
    @rows = CrossReferenceLookup.for_verse(
      book:, chapter: params[:chapter].to_i, verse: params[:verse].to_i, translation:
    )
    render partial: "studies/xref_results", locals: { study: @study, origin: @origin, rows: @rows }
  end

  private

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
