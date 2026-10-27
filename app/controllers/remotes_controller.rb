# The phone remote ("clicker"). `create` mints a pairing code + QR for the
# operator console (must be able to open the study); `show` is the public pad
# page the phone lands on. No record is stored — the code and its signed,
# expiring pairing tokens (RemotePairing) only live in the two cable clients.
class RemotesController < ApplicationController
  include LanHost
  allow_unauthenticated_access

  CODE_LENGTH = 6

  # POST /studies/:study_id/remote — mint a pairing code for this console
  def create
    study = current_study(params[:study_id]) # authorization: only someone who can open the study may pair
    code = LiveSession.random_code(CODE_LENGTH)
    pad_token = RemotePairing.issue(code: code, study: study, role: RemotePairing::PAD)
    url = lan_visible_url(remote_pad_url(code, t: pad_token))
    render json: {
      code: code,
      token: RemotePairing.issue(code: code, study: study, role: RemotePairing::CONSOLE),
      url: url,
      qr_svg: RQRCode::QRCode.new(url).as_svg(module_size: 4, viewbox: true, use_path: true)
    }
  end

  # GET /remote/:code?t=TOKEN — the phone's pad. A missing/expired token shows
  # a "scan again" notice instead of a pad that could never connect.
  def show
    @code = params[:code].to_s.upcase
    return head :not_found unless @code.match?(RemoteChannel::CODE_FORMAT)
    @token = params[:t].to_s
    @paired = RemotePairing.verify(@token, code: @code)&.dig(:role) == RemotePairing::PAD
    render :show, status: (@paired ? :ok : :forbidden)
  end
end
