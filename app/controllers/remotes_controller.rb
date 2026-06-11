# The phone remote ("clicker"). `create` mints a pairing code + QR for the
# operator console (must be able to open the study); `show` is the public pad
# page the phone lands on. No record is stored — the code only lives in the
# two subscribed cable clients.
class RemotesController < ApplicationController
  allow_unauthenticated_access

  CODE_LENGTH = 6

  # POST /studies/:study_id/remote — mint a pairing code for this console
  def create
    current_study(params[:study_id]) # authorization: only someone who can open the study may pair
    code = Array.new(CODE_LENGTH) { LiveSession::CODE_ALPHABET.sample }.join
    url = remote_pad_url(code)
    render json: {
      code: code,
      url: url,
      qr_svg: RQRCode::QRCode.new(url).as_svg(module_size: 4, viewbox: true, use_path: true)
    }
  end

  # GET /remote/:code — the phone's pad
  def show
    @code = params[:code].to_s.upcase
    head :not_found unless @code.match?(RemoteChannel::CODE_FORMAT)
  end
end
