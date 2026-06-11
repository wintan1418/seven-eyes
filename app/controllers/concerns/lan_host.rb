require "socket"

# QR codes are scanned by phones. In development the console runs on
# "localhost", which a phone can't reach — swap the loopback host for this
# machine's LAN address (same port) so the QR actually works on the same Wi-Fi.
# In production the real domain passes through untouched.
module LanHost
  private

  def lan_visible_url(url)
    return url unless Rails.env.development?
    uri = URI(url)
    return url unless %w[localhost 127.0.0.1].include?(uri.host)
    lan = Socket.ip_address_list.find { |a| a.ipv4_private? }&.ip_address
    return url unless lan
    uri.host = lan
    uri.to_s
  end
end
