require "test_helper"

# GET /search — Bible search as its own page (the apps' Search tab), and
# /read?ref=… which its results open: the whole chapter, the verse marked.
class SearchPageTest < ActionDispatch::IntegrationTest
  ANDROID = { "User-Agent" => "BiblioRata/1.0.3; NativeBridge; Hotwire Native Android; Turbo Native Android; Mozilla/5.0 (Linux; Android 16; wv)" }.freeze

  setup do
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    @bsb = Translation.create!(code: "BSB", name: "Berean Standard Bible")
    @deut = Book.create!(osis_code: "Deut", name: "Deuteronomy", testament: :old, position: 5, chapter_count: 34)
    @job = Book.create!(osis_code: "Job", name: "Job", testament: :old, position: 18, chapter_count: 42)
    (1..4).each do |v|
      Verse.create!(translation: @kjv, book: @deut, chapter: 32, verse_number: v,
                    text: v == 2 ? "My doctrine shall drop as the rain, my speech shall distil as the dew" : "Deut 32 verse #{v}.")
    end
    Verse.create!(translation: @kjv, book: @job, chapter: 38, verse_number: 28, text: "Hath the rain a father? or who hath begotten the drops of dew?")
    Verse.create!(translation: @kjv, book: @job, chapter: 38, verse_number: 26, text: "To cause it to rain on the earth")
  end

  test "the empty page: a search box, the book filter and the translation" do
    get search_path
    assert_response :success
    assert_select "title", text: "Search · BiblioRata"
    assert_select "form.sr-form[action=?][method=get]", search_path
    assert_select "input[name=q][autofocus]"
    assert_select "select[name=in] option[value=all][selected]"
    assert_select "select[name=in] option[value=ot]"
    assert_select "select[name=in] option[value=Deut]", text: "Deuteronomy"
    assert_select "select[name=t] option[selected]", text: "KJV"
    assert_select ".sr-empty"
    assert_select "[data-controller~=search-page]"
    assert_select ".ui-tabbar a.ui-tab.is-current[href=?]", search_path
  end

  test "results: every word first in Bible order, words marked, count, links into the reader" do
    get search_path(q: "dew rain")
    assert_response :success
    assert_select ".sr-summary", text: /Showing 2 verses containing dew and rain · KJV/
    refs = css_select(".sr-hit .sr-ref").map(&:text)
    assert_equal [ "Deuteronomy 32:2", "Job 38:28", "Job 38:26" ], refs
    assert_select ".sr-divider", text: "With some of the words"
    assert_select ".sr-hit .sr-text mark", minimum: 4
    assert_select "a.sr-open[href=?][data-open-ref='Deuteronomy 32:2'][data-turbo-frame=_top]",
                  read_path(ref: "Deuteronomy 32:2", t: "KJV")
  end

  test "the book filter and translation narrow the search" do
    get search_path(q: "rain", in: "Job")
    assert_equal [ "Job 38:26", "Job 38:28" ], css_select(".sr-hit .sr-ref").map(&:text)
    get search_path(q: "rain", in: "nt")
    assert_select ".sr-hit", 0
    assert_select ".sr-summary", text: /No verses containing rain/
  end

  test "inside the apps the native bar shows the title Search and no web tab bar is drawn over it" do
    get search_path, headers: ANDROID
    assert_select "body.hotwire-native"
    assert_select "title", text: "Search"
  end

  test "/read?ref= opens the reader at the whole chapter with the verse marked" do
    get read_path(ref: "Deuteronomy 32:2", t: "KJV")
    study = Study.where(user_id: nil).last
    assert_redirected_to study_path(study, verse: "2")
    assert_equal "Deuteronomy 32", study.panes.first.reference
    assert_equal @kjv.id, study.panes.first.translation_id

    follow_redirect!
    assert_select ".ps-verses[data-verse-focus='2']"
    assert_select ".ps-verse[data-verse-num]", 4 # the whole chapter, not only verse 2
  end

  test "a signed-in reader's /read?ref= reuses their latest study; a range marks every verse" do
    sign_in_as users(:one)
    study = users(:one).studies.create!(name: "Sunday", pane_count: 1)
    assert_no_difference -> { Study.count } do
      get read_path(ref: "Deut 32:2-4")
    end
    assert_redirected_to study_path(study, verse: "2-4")
    assert_equal "Deuteronomy 32", study.reload.panes.first.reference
  end

  test "a study page ignores a ?verse= that isn't verse numbers" do
    sign_in_as users(:one)
    study = users(:one).studies.create!(name: "Sunday", pane_count: 1)
    study.panes.first.update!(reference: "Deuteronomy 32")
    get study_path(study, verse: "2\"><script>")
    assert_response :success
    assert_select ".ps-verses[data-verse-focus]", 0
  end

  test "a reference typed into search opens the reader there; words and frame searches stay searches" do
    get search_path(q: "John 3:16")
    assert_redirected_to read_path(ref: "John 3:16")
    get search_path(q: "Job") # a book name without a number is a word search
    assert_response :success
    get search_path(q: "John 3:16"), headers: { "Turbo-Frame" => "search_results" }
    assert_response :success
  end

  # Hovering a result must not open it in the background: Turbo's prefetch of
  # /read?ref= moved the reader's latest study to that passage.
  test "search results are never prefetched" do
    get search_path(q: "dew rain")
    assert_response :success
    links = css_select("a.sr-open")
    assert_not_empty links
    links.each { |a| assert_equal "false", a["data-turbo-prefetch"] }
  end

end
