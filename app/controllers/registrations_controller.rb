class RegistrationsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  rate_limit to: 5, within: 1.hour, only: :create, name: "registration",
             with: -> { redirect_to new_registration_path, alert: "Too many sign-ups from here. Try again later." }

  def new
    @user = User.new
  end

  def create
    @user = User.new(registration_params)
    if @user.save
      start_new_session_for(@user)
      claimed = claim_guest_study(@user)
      redirect_to(claimed || after_authentication_url, notice: "Welcome to the Scriptorium.")
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def registration_params
    params.permit(:email_address, :password, :password_confirmation)
  end
end
