class SharedStudiesController < ApplicationController
  allow_unauthenticated_access only: :show

  def show
    @study = Study.find_by(share_token: params[:token])
    return render "not_found", status: :not_found unless @study

    @panes = @study.panes.order(:position)
  end
end
