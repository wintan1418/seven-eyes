# The signed-in user's own account: a JSON export of everything they've saved,
# and permanent, password-confirmed deletion.
class AccountsController < ApplicationController
  rate_limit to: 5, within: 10.minutes, only: :destroy, name: "account-delete",
             with: -> { redirect_to account_path, alert: "Too many attempts. Try again later." }

  def show
    @user = current_user
    @counts = {
      "Studies" => @user.studies.count,
      "Highlights" => @user.highlights.count,
      "Reading plans" => @user.reading_plans.count
    }
  end

  def export
    data = AccountExport.call(current_user)
    send_data JSON.pretty_generate(data),
              filename: "bibliorata-export-#{Date.current.iso8601}.json",
              type: "application/json", disposition: "attachment"
  end

  def destroy
    user = current_user
    unless user.authenticate(params[:password].to_s)
      return redirect_to account_path, alert: "That password didn't match — your account was not deleted."
    end

    AccountDeletion.call(user)
    cookies.delete(:session_id)
    reset_session
    redirect_to root_path, notice: "Your account and everything in it have been deleted.", status: :see_other
  end
end
