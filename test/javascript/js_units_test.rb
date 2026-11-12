require "test_helper"
require "open3"

# Runs the plain-JavaScript unit tests (node:test) for the offline modules that
# have no DOM: the network circuit breaker and the offline keyword search.
class JsUnitsTest < ActiveSupport::TestCase
  FILES = Dir[Rails.root.join("test/javascript/*_test.mjs")].sort

  setup do
    skip "node is not installed" unless system("node", "--version", out: File::NULL, err: File::NULL)
  end

  test "node:test suites pass" do
    assert FILES.any?, "no test/javascript/*_test.mjs files found"
    out, status = Open3.capture2e("node", "--no-warnings", "--test", *FILES)
    assert status.success?, "node --test failed:\n#{out}"
  end
end
