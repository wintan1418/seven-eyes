require "test_helper"

class OfflineBundleTest < ActiveSupport::TestCase
  setup do
    FileUtils.rm_rf(OfflineBundle::CACHE_DIR)
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    @bsb = Translation.create!(code: "BSB", name: "Berean Standard Bible")
    @john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    @gen = Book.create!(osis_code: "Gen", name: "Genesis", testament: :old, position: 1, chapter_count: 50)
    (1..3).each { |v| Verse.create!(translation: @kjv, book: @john, chapter: 3, verse_number: v, text: "John 3:#{v}") }
    Verse.create!(translation: @kjv, book: @gen, chapter: 1, verse_number: 1, text: "In the beginning")
    # BSB leaves out verse 2 of the chapter (as it does Matt 18:11).
    [ 1, 3 ].each { |v| Verse.create!(translation: @bsb, book: @john, chapter: 3, verse_number: v, text: "BSB 3:#{v}") }
  end

  teardown { FileUtils.rm_rf(OfflineBundle::CACHE_DIR) }

  test "books come in canonical order with chapters indexed by number" do
    data = OfflineBundle.new(@kjv).to_h
    assert_equal %w[Gen John], data[:books].map { |b| b[:osis] }
    john = data[:books].last
    assert_nil john[:chapters][0], "chapters the translation lacks are empty slots"
    assert_equal [ "John 3:1", "John 3:2", "John 3:3" ], john[:chapters][2][:t]
  end

  test "consecutive verse ids collapse to the first id; numbers are implicit when 1..N" do
    chapter = OfflineBundle.new(@kjv).to_h[:books].last[:chapters][2]
    assert_equal Verse.where(translation: @kjv, book: @john, chapter: 3).order(:verse_number).first.id, chapter[:i]
    assert_nil chapter[:n]
  end

  test "an omitted verse keeps the real verse numbers and ids" do
    chapter = OfflineBundle.new(@bsb).to_h[:books].first[:chapters][2]
    assert_equal [ 1, 3 ], chapter[:n]
    assert_equal Verse.where(translation: @bsb, chapter: 3).order(:verse_number).pluck(:id), Array(chapter[:i]).then { |i| i.size == 1 ? [ i.first, i.first + 1 ] : i }
  end

  test "the version changes when the text changes, and the gzip is cached on disk" do
    bundle = OfflineBundle.new(@kjv)
    before = bundle.version
    assert_equal before, JSON.parse(ActiveSupport::Gzip.decompress(bundle.gzip))["version"]
    assert OfflineBundle::CACHE_DIR.join("KJV-#{before}.json.gz").exist?

    travel 1.minute do
      Verse.where(translation: @kjv).first.update!(text: "Corrected")
      Rails.cache.clear
      after = OfflineBundle.new(@kjv).version
      assert_not_equal before, after
    end
  end

  test "the manifest lists only translations readers may use" do
    Translation.create!(code: "NET", name: "NET Bible")
    codes = OfflineBundle.manifest.map { |t| t[:code] }
    assert_includes codes, "KJV"
    assert_not_includes codes, "NET"
    kjv = OfflineBundle.manifest.find { |t| t[:code] == "KJV" }
    assert kjv[:size].positive?
    assert kjv[:bytes] >= kjv[:size]
  end
end
