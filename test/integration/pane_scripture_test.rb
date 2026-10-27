require "test_helper"

# The production sweep's empty/misleading panes, one by one: each must render
# the right verses or a clear, actionable message — never a blank frame.
class PaneScriptureTest < ActionDispatch::IntegrationTest
  setup do
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    @bsb = Translation.create!(code: "BSB", name: "Berean Standard Bible")
    @web = Translation.create!(code: "WEB", name: "World English Bible")
    @net = Translation.create!(code: "NET", name: "NET Bible")
    @dra = Translation.create!(code: "DRA", name: "Douay-Rheims (1899)")

    @matt = book("Matt", "Matthew", 40, 28)
    @john = book("John", "John", 43, 21)
    @rom = book("Rom", "Romans", 45, 16)
    @john3 = book("3John", "3 John", 64, 1)
    @jude = book("Jude", "Jude", 65, 1)
    @ps = book("Ps", "Psalms", 19, 150, :old)

    [ @kjv, @bsb ].each do |t|
      (14..36).each { |v| verse(t, @john, 3, v) }
      (1..3).each { |v| verse(t, @john, 4, v) }
      (1..14).each { |v| verse(t, @john3, 1, v) }
      (1..25).each { |v| verse(t, @jude, 1, v) }
      (5..7).each { |c| (1..3).each { |v| verse(t, @matt, c, v) } }
    end
    (1..35).each { |v| verse(@kjv, @matt, 18, v) }
    (1..35).each { |v| verse(@bsb, @matt, 18, v) unless v == 11 }
    (1..35).each { |v| verse(@net, @matt, 18, v) unless v == 11 }
    (1..27).each { |v| verse(@kjv, @rom, 16, v) }
    (1..24).each { |v| verse(@web, @rom, 16, v) }
    (1..6).each { |v| verse(@kjv, @ps, 23, v) }
    (1..6).each { |v| verse(@dra, @ps, 23, v) }

    sign_in_as users(:one)
    @study = users(:one).studies.create!(name: "S", pane_count: 1)
    @pane = @study.panes.first
  end

  def book(osis, name, position, chapters, testament = :new)
    Book.create!(osis_code: osis, name:, testament:, position:, chapter_count: chapters)
  end

  def verse(t, b, c, v)
    Verse.create!(translation: t, book: b, chapter: c, verse_number: v, text: "#{t.code} #{b.osis_code} #{c}:#{v} text")
  end

  def show(reference, translation)
    patch study_pane_path(@study, @pane), params: { pane: { reference:, translation_id: translation.id } }
    assert_response :success
    assert_select "turbo-frame##{@pane.frame_id}"
  end

  def shown_verses = css_select(".ps-verse").map { |n| [ n["data-chapter"].to_i, n["data-verse-num"].to_i ] }

  test "Jn 3:16-4:2 in the BSB loads across the chapter boundary with a heading per chapter" do
    show("Jn 3:16-4:2", @bsb)
    assert_equal (16..36).map { |v| [ 3, v ] } + [ [ 4, 1 ], [ 4, 2 ] ], shown_verses
    assert_select ".ps-chapter-break", count: 2
    assert_select ".ref-title span", text: "John III–IV"
    assert_select "button.ps-ch-nav.next[title*='John 5']"
    assert_select "button.ps-ch-nav.prev[title*='John 2']"
  end

  test "Matthew 18:11 in the BSB explains the omission and offers the KJV" do
    show("Matthew 18:11", @bsb)
    assert_empty shown_verses
    assert_includes response.body, "Matthew 18:11 isn&rsquo;t in the BSB"
    assert_includes response.body, "Many modern translations omit or move it"
    assert_select "button", text: "Show in KJV"
    assert_select "input[name='pane[translation_id]'][value='#{@kjv.id}']"
    refute_includes response.body, "Try a verse up to"
  end

  test "Matthew 18:10-12 in the BSB shows 10 and 12 and names the missing verse" do
    show("Matthew 18:10-12", @bsb)
    assert_equal [ [ 18, 10 ], [ 18, 12 ] ], shown_verses
    assert_select ".ps-pane-notice", text: /Matthew 18:11\s+isn’t in the BSB/
    assert_select "button", text: "Show in KJV"
  end

  test "a pane saved with the restricted NET falls back to the KJV instead of rendering NET" do
    @pane.update!(reference: "Matthew 18:11", translation: @net)
    get study_path(@study)
    assert_response :success
    assert_includes response.body, "KJV Matt 18:11 text"
    assert_select "select.ps-trans-select option", text: "NET", count: 0
  end

  test "Romans 16:25 in the WEB points to the KJV rather than a verse count" do
    show("Romans 16:25", @web)
    assert_includes response.body, "Romans 16:25 isn&rsquo;t in the WEB"
    assert_select "button", text: "Show in KJV"
  end

  test "3 John 15 where the letter ends at 14 says so and offers verse 14" do
    show("3 John 15", @bsb)
    assert_includes response.body, "3 John 1 has 14 verses"
    assert_select "button", text: "Show 3 John 1:14"
    assert_select "input[name='pane[reference]'][value='3 John 1:14']"
  end

  test "Matt 5-7 loads all three chapters" do
    show("Matt 5-7", @kjv)
    assert_equal [ 5, 6, 7 ], shown_verses.map(&:first).uniq
    assert_select ".ref-title span", text: "Matthew V–VII"
    assert_select "button.ps-ch-nav.next[title*='Matthew 8']"
  end

  test "Jude 1-3 loads verses 1 to 3, not the whole chapter" do
    show("Jude 1-3", @kjv)
    assert_equal [ [ 1, 1 ], [ 1, 2 ], [ 1, 3 ] ], shown_verses
  end

  test "Psalm 23 in the DRA carries a Vulgate-numbering notice" do
    show("Psalm 23", @dra)
    assert_select ".ps-pane-notice", text: /Latin Vulgate/
    assert_select ".ref-title .tag", text: /Vulgate numbering/
  end

  test "a chapter the translation lacks says so and offers one that has it" do
    show("Romans 16", @bsb)
    assert_includes response.body, "This chapter isn&rsquo;t available in the Berean Standard Bible yet"
    assert_select "button", text: /Show in (KJV|WEB)/
  end

  test "the translation menu lists only available translations" do
    @web.update!(verse_count: 12) # a broken partial seed
    show("John 3:16", @kjv)
    options = css_select("select.ps-trans-select option").map(&:text)
    assert_includes options, "KJV"
    assert_includes options, "BSB"
    refute_includes options, "WEB"
    refute_includes options, "NET"
  end
end
