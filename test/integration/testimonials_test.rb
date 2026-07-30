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
    assert_select ".ps-marginalia-card blockquote", text: /revival week/
    assert_select ".ps-marginalia-card", count: 1
  end

  test "the welcome shows no marginalia section when nothing is publishable" do
    get root_path
    assert_select ".ps-marginalia", count: 0
  end
end
