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
end
