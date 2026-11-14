require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "downcases and strips email_address" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")
    assert_equal("downcased@example.com", user.email_address)
  end

  test "greeting_name reads a first name from the email when it looks like one" do
    { "grace.okafor@example.com" => "Grace", "wintan1418@example.com" => "Wintan", "JOHN_doe@x.org" => "John",
      "info@church.org" => nil, "a1@x.org" => nil, "pastor@example.com" => nil, "12345@x.org" => nil }.each do |email, name|
      got = User.new(email_address: email).greeting_name
      name ? assert_equal(name, got, email) : assert_nil(got, email)
    end
  end

  test "pastor mode follows what the account does until the reader chooses" do
    user = users(:one)
    assert_not user.pastor_mode?, "a reader who has never lined up a service"

    study = user.studies.create!(name: "Sunday", pane_count: 1)
    study.setlist_items.create!(kind: :song, title: "Amazing Grace", body: "Amazing grace")
    assert User.find(user.id).pastor_mode?, "a service queue makes a preacher"

    user.update!(pastor_mode: false)
    assert_not User.find(user.id).pastor_mode?, "their own choice wins"

    other = users(:two)
    other.update!(pastor_mode: true)
    assert other.pastor_mode?
  end

  test "having gone live makes a preacher too" do
    user = users(:two)
    study = user.studies.create!(name: "Live", pane_count: 1)
    LiveSession.create!(study:, code: "ABC123")
    assert User.find(user.id).pastor_mode?
  end
end
