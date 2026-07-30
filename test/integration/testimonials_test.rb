require "test_helper"

class TestimonialsTest < ActionDispatch::IntegrationTest
  test "the public collection page is open to guests" do
    get "/testimonials/new"
    assert_response :success
  end

  test "the triage dashboard is closed to guests and non-admins" do
    get "/testimonials"
    assert_response :forbidden

    sign_in_as users(:one) # fixture user is not an admin
    get "/testimonials"
    assert_response :forbidden
  end

  test "the triage dashboard opens for an admin" do
    users(:one).update!(admin: true)
    sign_in_as users(:one)
    get "/testimonials"
    assert_response :success
  end

  test "publishable testimonials appear as marginalia on the welcome" do
    Testimonials::Testimonial.create!(
      body: "This desk carried our whole revival week.", rating: 5,
      name: "Pastor A.", status: "approved", consent_given: true
    )
    Testimonials::Testimonial.create!(
      body: "Pending one, must stay hidden.", rating: 4,
      name: "Hidden", status: "pending"
    )
    get root_path
    assert_select ".ps-scroll blockquote", text: /revival week/
    assert_select ".ps-scroll", count: 1
    assert_select ".ps-scroll .scroll-avatar", text: "P" # circular initial medallion
  end

  test "the welcome shows no marginalia section when nothing is publishable" do
    get root_path
    assert_select ".ps-marginalia", count: 0
    # ...but still invites the first testimonial.
    assert_select ".ps-marginalia-invite a[href=?]", "/testimonials/new"
  end

  # Regression: after a visitor submits, testimonials_tag re-renders their
  # existing entry — which touches the (optional) video attachment. Without
  # the Active Storage tables that 500'd every subsequent page for them.
  test "a visitor who has submitted can still browse the app" do
    post "/testimonials", params: {
      testimonial: { body: "A quiet desk indeed — my sermon prep is transformed.", rating: 5, consent_given: "1", source: "page" }
    }, as: :json
    assert_response :created

    get "/" # literal — after an engine request, root_path resolves to the engine's root
    assert_response :success
    assert_select ".ps-welcome"
  end
end
