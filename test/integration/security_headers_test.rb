require "test_helper"

class SecurityHeadersTest < ActionDispatch::IntegrationTest
  def csp_header
    response.headers["Content-Security-Policy-Report-Only"] || response.headers["Content-Security-Policy"]
  end

  test "pages carry a Content-Security-Policy (report-only until CSP_ENFORCE)" do
    get root_path
    assert_response :success
    assert csp_header, "a CSP header is sent"
    assert_includes csp_header, "object-src 'none'"
    assert_match(/script-src 'self' 'nonce-[^']+'/, csp_header)
    assert_includes csp_header, "https://fonts.gstatic.com"
  end

  test "the bundle script tag carries the CSP nonce" do
    get root_path
    nonce = csp_header[/'nonce-([^']+)'/, 1]
    assert_select "script[src*='application'][nonce=?]", nonce
  end
end
