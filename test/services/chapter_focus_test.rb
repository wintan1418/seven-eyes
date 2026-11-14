require "test_helper"

class ChapterFocusTest < ActiveSupport::TestCase
  test "a verse or a range inside one chapter opens the chapter with the verses marked" do
    assert_equal [ "Deuteronomy 32", "2" ], ChapterFocus.call("Deut 32:2").to_a
    assert_equal [ "Deuteronomy 32", "2-4" ], ChapterFocus.call("Deuteronomy 32:2-4").to_a
  end

  test "whole chapters, spans across chapters and nonsense open as they are" do
    assert_equal [ "John 3", nil ], ChapterFocus.call("jn 3").to_a
    assert_not ChapterFocus.call("John 3:16-4:2").focus?
    assert_equal [ "nonsense", nil ], ChapterFocus.call("nonsense").to_a
  end

  test "clean only lets verse numbers through" do
    assert_equal "2-4", ChapterFocus.clean("2-4")
    assert_nil ChapterFocus.clean("2<script>")
    assert_nil ChapterFocus.clean(nil)
  end
end
