require "test_helper"

# The built-in hymnal ships to every church: it must be public domain, readable
# by the song sheet, and free of duplicates.
class HymnalTest < ActiveSupport::TestCase
  test "is a real hymnal, not a starter set" do
    assert_operator Hymnal::HYMNS.size, :>=, 80
  end

  test "every hymn has a title, an author and at least one stanza" do
    Hymnal::HYMNS.each do |h|
      assert h[:title].present?, "a hymn without a title: #{h.inspect.truncate(80)}"
      assert h[:author].present?, "#{h[:title]} has no author"
      assert_operator SongSheet.new(h[:body]).slides.size, :>=, 1, "#{h[:title]} has no stanzas"
    end
  end

  test "titles are unique" do
    titles = Hymnal::HYMNS.map { |h| h[:title].downcase.strip }
    assert_equal titles.uniq.size, titles.size, "duplicate titles: #{titles.tally.select { |_, n| n > 1 }.keys}"
  end

  test "no copyrighted song ever ships" do
    titles = Hymnal::HYMNS.map { |h| h[:title].downcase.strip }
    assert_empty titles & Hymnal::BLOCKLIST
    %w[how\ great\ thou\ art great\ is\ thy\ faithfulness in\ christ\ alone].each do |t|
      refute titles.any? { |title| title.include?(t) }, "#{t} is under copyright"
    end
  end

  test "dates, where known, are before 1929" do
    Hymnal::HYMNS.each do |h|
      assert_operator h[:year], :<, 1929, "#{h[:title]} (#{h[:year]}) may still be under copyright" if h[:year]
    end
  end

  test "every hymn is labelled into verses, and a refrain repeats after each verse" do
    Hymnal::HYMNS.each do |h|
      sheet = SongSheet.new(h[:body])
      assert sheet.labelled?, "#{h[:title]} has no [Verse] labels"
      assert sheet.unknown.empty?
      codes = sheet.slides.map(&:code)
      verses = codes.count { |c| c.start_with?("V") }
      next unless codes.include?("C")
      assert_equal verses, codes.count("C"), "#{h[:title]}: the refrain should follow every verse (#{codes.join(" ")})"
    end
  end

  test "Blessed Assurance sings its refrain after every verse" do
    hymn = Hymnal::HYMNS.find { |h| h[:title] == "Blessed Assurance" }
    assert hymn, "Blessed Assurance should be in the hymnal"
    assert_match(/\AV1 C V2 C V3 C/, SongSheet.new(hymn[:body]).flow_codes)
  end
end
