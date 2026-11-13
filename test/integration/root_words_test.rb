require "test_helper"

# Root word projection (preach mode): a verse's Strong's words, the offline
# word pack, Ask Rabbi, word-study queue items and live phones.
class RootWordsTest < ActionDispatch::IntegrationTest
  setup do
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    @gen = Book.create!(osis_code: "Gen", name: "Genesis", testament: :old, position: 1, chapter_count: 50)
    @john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    @v16 = Verse.create!(translation: @kjv, book: @john, chapter: 3, verse_number: 16,
                         text: "For God so loved the world, that he gave",
                         tokens: [ { "w" => "For", "s" => "G1063" }, { "w" => " God", "s" => "G2316" }, { "w" => " so", "s" => "G3779" },
                                   { "w" => " loved", "s" => "G25" }, { "w" => " the world", "s" => "G2889" },
                                   { "w" => ", that", "s" => "G3754" }, { "w" => " he gave", "s" => "G1325" } ])
    Verse.create!(translation: @kjv, book: @john, chapter: 3, verse_number: 35, text: "The Father loveth the Son",
                  tokens: [ { "w" => "The Father", "s" => "G3962" }, { "w" => " loveth", "s" => "G25" }, { "w" => " the Son", "s" => "G5207" } ])
    @gen1 = Verse.create!(translation: @kjv, book: @gen, chapter: 1, verse_number: 1, text: "In the beginning God created",
                          tokens: [ { "w" => "In the beginning", "s" => "H7225" }, { "w" => " God", "s" => "H430" },
                                    { "w" => " created", "s" => "H1254" } ])
    LexiconEntry.create!(strongs: "G25", language: "greek", lemma: "ἀγαπάω", translit: "agapáō",
                         definition: "to love (in a social or moral sense)", kjv_def: "(be-)love(-ed)",
                         derivation: "perhaps from ἄγαν (much)")
    LexiconEntry.create!(strongs: "H1254", language: "hebrew", lemma: "בָּרָא", translit: "bârâʼ", pron: "baw-raw'",
                         definition: "(absolutely) to create", kjv_def: "choose, create (creator)", derivation: "a primitive root;")
    Rails.cache.clear
  end

  def with_ai_result(result)
    original = AiChat.method(:call)
    AiChat.singleton_class.define_method(:call) { |*, **| result }
    yield
  ensure
    AiChat.singleton_class.define_method(:call, original)
  end

  test "a verse's root words: every token, the entries they name, how often each occurs" do
    get root_words_verse_path("John", 3, 16)
    assert_response :success
    body = response.parsed_body
    assert_equal "John 3:16", body["reference"]
    assert_equal "For God so loved the world, that he gave", body["tokens"].map { |t| t["w"] }.join
    entry = body["entries"]["G25"]
    assert_equal "ἀγαπάω", entry["lemma"]
    assert_equal "agapáō", entry["translit"]
    assert_equal 2, entry["n"], "loved (3:16) + loveth (3:35)"
    assert_nil body["entries"]["G2316"], "no lexicon row, no entry"
    assert_match "public", response.headers["Cache-Control"]
  end

  test "Hebrew entries carry Strong's pronunciation for the stress" do
    get root_words_verse_path("Gen", 1, 1)
    assert_equal "baw-raw'", response.parsed_body.dig("entries", "H1254", "pron")
  end

  test "an unknown verse is a 404" do
    get root_words_verse_path("John", 3, 99)
    assert_response :not_found
    get root_words_verse_path("Nope", 1, 1)
    assert_response :not_found
  end

  test "the offline word pack: versioned, gzipped, verses encoded with @numbers" do
    get root_words_pack_info_path
    info = response.parsed_body
    assert info["version"].present?
    assert_operator info["size"], :>, 0

    get info["url"], headers: { "Accept-Encoding" => "gzip" }
    assert_response :success
    assert_equal "gzip", response.headers["Content-Encoding"]
    assert_match "immutable", response.headers["Cache-Control"]
    pack = JSON.parse(ActiveSupport::Gzip.decompress(response.body))
    john = pack["books"].find { |b| b["osis"] == "John" }
    assert_equal "G", john["prefix"]
    assert_equal "For@1063 God@2316 so@3779 loved@25 the world@2889, that@3754 he gave@1325", john["chapters"][2][15]
    assert_equal "", john["chapters"][2][0], "verses the KJV has no row for stay as empty strings"
    assert_equal "H", pack["books"].find { |b| b["osis"] == "Gen" }["prefix"]
    assert_equal %w[ lemma translit pron def kjv deriv n ], pack["fields"]
    assert_equal [ "ἀγαπάω", "agapáō", nil, "to love (in a social or moral sense)", "(be-)love(-ed)", "perhaps from ἄγαν (much)", 2 ],
                 pack["lexicon"]["G25"]

    get root_words_pack_path, headers: { "If-None-Match" => response.headers["ETag"] }
    assert_response :not_modified
  end

  test "the pack's version moves when a verse's tokens change" do
    before = RootWordPack.new.version
    Rails.cache.clear
    @v16.update!(tokens: [ { "w" => "For God so loved the world, that he gave" } ])
    refute_equal before, RootWordPack.new.version
  end

  test "Ask Rabbi needs an account" do
    post root_words_explain_path, params: { strongs: "G25", osis: "John", chapter: 3, verse: 16, word: "loved" }, as: :json
    assert_response :unauthorized
    assert_equal "auth_required", response.parsed_body["error"]
  end

  test "Ask Rabbi: one or two sentences, plain text, cached" do
    sign_in_as users(:one)
    calls = 0
    reply = AiChat::Result.new(ok: true, content: { explanation: "<b>Agapaō</b> is love that acts for another's good." }.to_json, provider: :gemini)
    original = AiChat.method(:call)
    cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new # test env has a null store
    AiChat.singleton_class.define_method(:call) { |*, **| calls += 1; reply }
    2.times do
      post root_words_explain_path, params: { strongs: "G25", osis: "John", chapter: 3, verse: 16, word: "loved" }, as: :json
      assert_response :success
    end
    assert_equal({ "ok" => true, "text" => "Agapaō is love that acts for another's good.", "error" => nil }, response.parsed_body)
    assert_equal 1, calls, "the second ask is served from the cache"
  ensure
    AiChat.singleton_class.define_method(:call, original) if original
    Rails.cache = cache if cache
  end

  test "Ask Rabbi degrades gracefully without a key" do
    sign_in_as users(:one)
    with_ai_result(AiChat::Result.new(ok: false, error: :no_key)) do
      post root_words_explain_path, params: { strongs: "G25", osis: "John", chapter: 3, verse: 16, word: "loved" }, as: :json
    end
    assert_equal({ "ok" => false, "text" => nil, "error" => "no_key" }, response.parsed_body)
  end

  test "a word study goes in the queue and stays a word study" do
    sign_in_as users(:one)
    study = users(:one).studies.create!(name: "Sunday", pane_count: 1)
    word = { v: 1, s: "G25", lemma: "ἀγαπάω", translit: "agapáō", english: "loved", reference: "John 3:16" }.to_json
    post study_setlist_items_path(study), params: { setlist_item: { kind: "word", title: "Word study: agapáō — John 3:16",
                                                                   body: word, client_id: "tmp-w1" } }, as: :json
    assert_response :created
    item = study.setlist_items.last
    assert item.word?
    assert_equal "Word study: agapáō — John 3:16", item.label
    assert_equal "G25", item.word_study["s"]

    post study_setlist_items_path(study), params: { setlist_item: { kind: "word", title: "x", body: "not json" } }, as: :json
    assert_response :unprocessable_entity
  end

  test "live phones get the word study, cleaned" do
    sign_in_as users(:one)
    study = users(:one).studies.create!(name: "Sunday", pane_count: 1)
    post study_live_path(study), params: { reference: "John 3", translation_id: @kjv.id }, as: :json
    patch study_live_path(study), params: {
      kind: "slide", slide_title: "Word study: agapáō — John 3:16", slide_body: "ἀγαπάω (agapáō) G25",
      slide_word: { s: "g25", lemma: "ἀγαπάω", translit: "agapáō", gloss: "to love", evil: "<script>", note: "x" * 900 }
    }, as: :json
    assert_response :success
    live = study.live_session.reload
    state = live.live_state
    assert_equal "G25", state[:slide_word]["s"]
    assert_equal "greek", state[:slide_word]["lang"]
    assert_nil state[:slide_word]["evil"]
    assert_equal 400, state[:slide_word]["note"].length
  end
end
