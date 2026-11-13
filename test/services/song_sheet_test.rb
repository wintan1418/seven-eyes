require "test_helper"

# Songs → slides on the server (stanza counts in the queue, the hymnal's own
# checks). The same cases run against the device's copy in
# test/javascript/song_sheet_test.mjs, so the two can't drift apart.
class SongSheetTest < ActiveSupport::TestCase
  CASES = JSON.parse(File.read(Rails.root.join("test/fixtures/files/song_sheet_cases.json")))

  CASES.each do |c|
    test "song sheet: #{c["name"]}" do
      sheet = SongSheet.new(c["body"], c["arrangement"])
      assert_equal c["slides"], sheet.slides.map { |s| [ s.label, s.text ] } if c["slides"]
      assert_equal c["flow"], sheet.flow_codes if c["flow"]
      assert_equal c["unknown"] || [], sheet.unknown
    end
  end

  test "projected_body is the slides' words in order, without labels" do
    assert_equal "a\n\nc\n\nb\n\nc", SongSheet.new("[Verse 1]\na\n\n[Chorus]\nc\n\n[Verse 2]\nb").projected_body
    assert_equal "one\n\ntwo", SongSheet.new("one\n\ntwo").projected_body
  end

  test "labelled? only when the words carry a section label" do
    assert SongSheet.new("[Chorus]\nla").labelled?
    refute SongSheet.new("Chorus of angels\nsinging").labelled?
    refute SongSheet.new(nil).labelled?
    assert_empty SongSheet.new("").slides
  end
end
