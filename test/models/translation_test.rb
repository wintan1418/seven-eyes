require "test_helper"

class TranslationTest < ActiveSupport::TestCase
  test "available excludes licence-restricted and incomplete translations" do
    kjv = Translation.create!(code: "KJV", name: "King James Version", verse_count: 31_102)
    uncounted = Translation.create!(code: "BSB", name: "Berean Standard Bible")
    partial = Translation.create!(code: "WEB", name: "World English Bible", verse_count: 4_000)
    net = Translation.create!(code: "NET", name: "NET Bible", verse_count: 31_085)

    available = Translation.available.to_a
    assert_includes available, kjv
    assert_includes available, uncounted, "never-counted rows (made by hand) are trusted"
    refute_includes available, partial
    refute_includes available, net
    assert net.reload.persisted?, "restricted rows are hidden, not deleted"
  end

  test "default prefers the KJV, else the first available" do
    bsb = Translation.create!(code: "BSB", name: "Berean Standard Bible")
    assert_equal bsb, Translation.default
    kjv = Translation.create!(code: "KJV", name: "King James Version")
    assert_equal kjv, Translation.default
    kjv.update!(verse_count: 10)
    assert_equal bsb, Translation.default
  end

  test "Douay-Rheims is labelled with its Vulgate numbering" do
    dra = Translation.new(code: "DRA", name: "Douay-Rheims (1899)")
    assert dra.vulgate_numbering?
    assert_equal "Douay-Rheims (1899) (Vulgate numbering)", dra.display_name
    assert_equal "King James Version", Translation.new(code: "KJV", name: "King James Version").display_name
  end
end
