require "test_helper"

class ScriptureScenesTest < ActiveSupport::TestCase
  test "every scene has its picture, a real book and chapter, and a public-domain licence" do
    assert ScriptureScenes.all.size > 50
    keys = ScriptureScenes.all.map(&:key)
    assert_equal keys.uniq, keys, "keys are unique"
    ScriptureScenes.all.each do |s|
      assert File.exist?(ScriptureScenes::DIR.join("#{s.key}.webp")), "#{s.key}.webp is missing"
      count = Bible::Canon.find(s.osis)&.chapter_count
      assert count, "#{s.key}: #{s.osis} is not a book"
      assert s.chapter.between?(1, count), "#{s.key}: #{s.osis} has no chapter #{s.chapter}"
      assert_match(/public domain/i, s.licence, s.key)
      assert_match %r{\Ahttps://commons\.wikimedia\.org/wiki/File:}, s.commons_url, s.key
    end
  end

  test "no stray picture files" do
    files = Dir[ScriptureScenes::DIR.join("*.webp")].map { |f| File.basename(f, ".webp") }.sort
    assert_equal ScriptureScenes.all.map(&:key).sort, files
  end

  test "the reader's bundled copy matches the list (run bin/rails scenes:json after editing it)" do
    assert_equal ScriptureScenes.bundle_json, File.read(ScriptureScenes::BUNDLE)
  end
end
