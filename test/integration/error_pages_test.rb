require "test_helper"

class ErrorPagesTest < ActionDispatch::IntegrationTest
  # The static error pages live under public/ and are served by the web server
  # (or Rails' static middleware) when something goes wrong. They must be
  # self-contained and stay branded — these tests catch accidental clobbers.

  test "public/404.html exists and is styled with the vellum theme" do
    body = Rails.root.join("public/404.html").read
    assert_includes body, "Parallel · Scripture"
    assert_includes body, "EB Garamond"
    assert_match(/not in the book/i, body)
  end

  test "public/500.html exists and is styled with the vellum theme" do
    body = Rails.root.join("public/500.html").read
    assert_includes body, "Parallel · Scripture"
    assert_includes body, "Something stumbled"
  end

  test "public/422.html exists and is styled with the vellum theme" do
    body = Rails.root.join("public/422.html").read
    assert_includes body, "Parallel · Scripture"
    assert_includes body, "couldn't be completed"
  end
end
