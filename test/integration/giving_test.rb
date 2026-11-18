require "test_helper"

class GivingTest < ActionDispatch::IntegrationTest
  SECRET = "sk_test_giving_secret"

  setup do
    @admin = users(:one)
    @admin.update!(admin: true)
    @saved_env = ENV.to_h.slice("PAYSTACK_SECRET_KEY", "DONATIONS_PUBLIC")
    ENV.delete("PAYSTACK_SECRET_KEY")
    ENV.delete("DONATIONS_PUBLIC")
  end

  teardown do
    %w[PAYSTACK_SECRET_KEY DONATIONS_PUBLIC].each { |k| @saved_env.key?(k) ? ENV[k] = @saved_env[k] : ENV.delete(k) }
  end

  def give_params(**over)
    { donation: { currency: "NGN", frequency: "one_time", amount_ngn: "5000", amount_custom: "",
                  name: "Grace Ade", email: "grace@example.com", anonymous: "0", message: "Bless you" }.merge(over) }
  end

  # Swap one Paystack call for the block (no network in tests).
  def stub_paystack(name, impl)
    original = Paystack.method(name)
    Paystack.define_singleton_method(name, &impl)
    yield
  ensure
    Paystack.define_singleton_method(name, original)
  end

  def signed(body) = OpenSSL::HMAC.hexdigest("SHA512", SECRET, body)

  test "guests and ordinary accounts can't see the page yet" do
    get give_path
    assert_redirected_to root_path
    sign_in_as users(:two)
    get give_path
    assert_redirected_to root_path
    post give_path, params: give_params
    assert_redirected_to root_path
    assert_equal 0, Donation.count
  end

  test "admins see the page with the preview banner and a disabled button without keys" do
    sign_in_as @admin
    get give_path
    assert_response :success
    assert_select ".give-preview", text: /only admins can see this page/
    assert_select "button.give-submit[disabled]", text: /Giving opens soon/
    assert_select "input[name='donation[email]'][value=?]", @admin.email_address
    assert_select ".give-amount", 8
  end

  test "everyone can see it once DONATIONS_PUBLIC=1, without the banner" do
    ENV["DONATIONS_PUBLIC"] = "1"
    get give_path
    assert_response :success
    assert_select ".give-preview", 0
  end

  test "giving without Paystack keys goes back to the page saying it opens soon" do
    sign_in_as @admin
    post give_path, params: give_params
    assert_redirected_to give_path
    assert_match "opens soon", flash[:notice]
    assert_equal 0, Donation.count
  end

  test "a one-time gift starts a Paystack checkout" do
    ENV["PAYSTACK_SECRET_KEY"] = SECRET
    sign_in_as @admin
    sent = nil
    stub_paystack(:post, ->(path, body) { sent = [ path, body ]; { "authorization_url" => "https://checkout.paystack.com/abc" } }) do
      post give_path, params: give_params
    end
    assert_redirected_to "https://checkout.paystack.com/abc"
    donation = Donation.last
    assert_equal [ 500_000, "NGN", "one_time", "pending" ], [ donation.amount_minor, donation.currency, donation.frequency, donation.status ]
    assert_equal "/transaction/initialize", sent[0]
    assert_equal 500_000, sent[1][:amount]
    assert_equal donation.reference, sent[1][:reference]
    assert_nil sent[1][:plan]
  end

  test "a monthly custom USD gift creates a plan first" do
    ENV["PAYSTACK_SECRET_KEY"] = SECRET
    sign_in_as @admin
    calls = []
    fake = ->(path, body) { calls << [ path, body ]; path == "/plan" ? { "plan_code" => "PLN_123" } : { "authorization_url" => "https://checkout.paystack.com/m" } }
    stub_paystack(:post, fake) do
      post give_path, params: give_params(currency: "USD", frequency: "monthly", amount_custom: "12.50")
    end
    assert_redirected_to "https://checkout.paystack.com/m"
    assert_equal [ "/plan", "/transaction/initialize" ], calls.map(&:first)
    assert_equal({ name: "BiblioRata monthly gift $12.50", interval: "monthly", amount: 1250, currency: "USD" }, calls[0][1])
    assert_equal "PLN_123", calls[1][1][:plan]
    assert_equal "PLN_123", Donation.last.paystack_plan_code
  end

  test "gifts below the minimum are refused" do
    ENV["PAYSTACK_SECRET_KEY"] = SECRET
    sign_in_as @admin
    post give_path, params: give_params(amount_custom: "100")
    assert_response :unprocessable_entity
    assert_match "smallest gift", response.body
    assert_equal 0, Donation.count
  end

  test "an expired form token shows the form again with the gift kept" do
    ENV["PAYSTACK_SECRET_KEY"] = SECRET
    sign_in_as @admin
    ActionController::Base.allow_forgery_protection = true
    post give_path, params: give_params(amount_custom: "7500")
    assert_response :unprocessable_entity
    assert_match "press Give again", response.body
    assert_select "input[name='donation[amount_custom]'][value='7500']"
    assert_equal 0, Donation.count
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  test "the thanks page verifies the payment with Paystack" do
    ENV["PAYSTACK_SECRET_KEY"] = SECRET
    donation = Donation.create!(amount_major: 5000, currency: "NGN", email: "grace@example.com", name: "Grace Ade")
    sign_in_as @admin
    stub_paystack(:get, ->(_path) { { "status" => "success", "amount" => 500_000, "currency" => "NGN" } }) do
      get give_thanks_path(reference: donation.reference)
    end
    assert_response :success
    assert donation.reload.paid?
    assert_match "Thank you, Grace", response.body
  end

  test "the webhook rejects a bad signature" do
    ENV["PAYSTACK_SECRET_KEY"] = SECRET
    donation = Donation.create!(amount_major: 5000, currency: "NGN", email: "g@example.com")
    body = { event: "charge.success", data: { reference: donation.reference, status: "success", amount: 500_000, currency: "NGN" } }.to_json
    post give_webhook_path, params: body, headers: { "Content-Type" => "application/json", "X-Paystack-Signature" => "nope" }
    assert_response :unauthorized
    assert donation.reload.pending?
  end

  test "the webhook marks a gift paid once, even if Paystack sends it twice" do
    ENV["PAYSTACK_SECRET_KEY"] = SECRET
    donation = Donation.create!(amount_major: 5000, currency: "NGN", email: "g@example.com")
    body = { event: "charge.success", data: { reference: donation.reference, status: "success", amount: 500_000, currency: "NGN", paid_at: "2026-11-18T10:00:00Z" } }.to_json
    2.times do
      post give_webhook_path, params: body, headers: { "Content-Type" => "application/json", "X-Paystack-Signature" => signed(body) }
      assert_response :ok
    end
    assert donation.reload.paid?
    assert_equal Time.utc(2026, 11, 18, 10), donation.paid_at
    assert_equal 1, Donation.count
  end

  test "a monthly renewal is recorded as a new paid gift, once" do
    ENV["PAYSTACK_SECRET_KEY"] = SECRET
    Donation.create!(amount_major: 10, currency: "USD", frequency: :monthly, email: "g@example.com", paystack_plan_code: "PLN_9", status: :paid)
    body = { event: "charge.success", data: { reference: "renewal-1", status: "success", amount: 1000, currency: "USD",
                                              plan: { plan_code: "PLN_9" }, customer: { email: "G@example.com" } } }.to_json
    2.times { post give_webhook_path, params: body, headers: { "Content-Type" => "application/json", "X-Paystack-Signature" => signed(body) } }
    assert_equal 2, Donation.count
    assert Donation.find_by(reference: "renewal-1").paid?
  end
end
