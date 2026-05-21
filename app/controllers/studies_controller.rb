class StudiesController < ApplicationController
  before_action :set_study, only: %i[ show update destroy suggest cross_references ]

  def index
    @studies = current_user.studies.recent
  end

  def show
    @study.touch_opened!
    @studies = current_user.studies.recent
  end

  def create
    study = current_user.studies.create!(
      name: params[:name].presence || "Untitled Study",
      pane_count: pane_count_param
    )
    redirect_to study
  end

  def update
    @study.update(study_params)
    @study.sync_panes! if @study.saved_change_to_pane_count?
    redirect_to @study
  end

  def suggest
    @query = params[:q].to_s
    @result = ScriptureSuggester.call(@query)
    render partial: "studies/ai_results", locals: { study: @study, query: @query, result: @result }
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

  def destroy
    @study.destroy
    redirect_to root_path, status: :see_other
  end

  private

  def set_study
    @study = current_user.studies.find(params[:id])
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
