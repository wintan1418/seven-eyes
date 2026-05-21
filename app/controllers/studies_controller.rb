class StudiesController < ApplicationController
  before_action :set_study, only: %i[ show destroy ]

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

  def destroy
    @study.destroy
    redirect_to root_path, status: :see_other
  end

  private

  def set_study
    @study = current_user.studies.find(params[:id])
  end

  def pane_count_param
    return 4 if params[:pane_count].blank?
    params[:pane_count].to_i.clamp(1, 4)
  end
end
