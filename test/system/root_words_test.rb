require "application_system_test_case"

# Root word projection. A church media tester: e-Sword shows the Hebrew and
# Greek behind a word, but nothing projects it — and preachers say "the Greek
# word here is agapē…" every Sunday. Here the operator picks the word on the
# verse in Preview (or live), and one click puts a Word Study slide on the
# projector, the stage display and the phones — offline too.
class RootWordsSystemTest < ApplicationSystemTestCase
  include OfflineTestHelper

  JOHN_3_16 = [ [ "For", "G1063" ], [ " God", "G2316" ], [ " so", "G3779" ], [ " loved", "G25" ], [ " the world", "G2889" ],
                [ ", that", "G5620" ], [ " he gave", "G1325" ], [ " his", "G846" ], [ " only begotten", "G3439" ], [ " Son", "G5207" ],
                [ ", that", "G2443" ], [ " whosoever", "G3956" ], [ " believeth", "G4100" ], [ " in", "G1519" ], [ " him", "G846" ],
                [ " should", "G622" ], [ " not", "G3361" ], [ " perish", "G622" ], [ ", but", "G235" ], [ " have", "G2192" ],
                [ " everlasting", "G166" ], [ " life", "G2222" ], [ "." ] ]
  KJV_TEXT = "For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should " \
             "not perish, but have everlasting life."
  WEB_TEXT = "For God so loved the world, that he gave his only born Son, that whoever believes in him should not " \
             "perish, but have eternal life."

  setup do
    clear_offline_data
    @user = users(:one)
    @user.update!(tour_completed_at: Time.current)
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    @web = Translation.create!(code: "WEB", name: "World English Bible")
    john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    gen = Book.create!(osis_code: "Gen", name: "Genesis", testament: :old, position: 1, chapter_count: 50)
    tokens = JOHN_3_16.map { |w, s| s ? { "w" => w, "s" => s } : { "w" => w } }
    Verse.create!(translation: @kjv, book: john, chapter: 3, verse_number: 15, text: "That whosoever believeth in him should not perish.")
    Verse.create!(translation: @kjv, book: john, chapter: 3, verse_number: 16, text: KJV_TEXT, tokens:)
    Verse.create!(translation: @kjv, book: john, chapter: 3, verse_number: 17, text: "For God sent not his Son into the world.")
    Verse.create!(translation: @web, book: john, chapter: 3, verse_number: 15, text: "that whoever believes in him should not perish.")
    Verse.create!(translation: @web, book: john, chapter: 3, verse_number: 16, text: WEB_TEXT)
    Verse.create!(translation: @kjv, book: gen, chapter: 1, verse_number: 1, text: "In the beginning God created the heaven and the earth.",
                  tokens: [ { "w" => "In the beginning", "s" => "H7225" }, { "w" => " God", "s" => "H430" },
                            { "w" => " created", "s" => "H1254" }, { "w" => " the heaven and the earth." } ])
    LexiconEntry.create!(strongs: "G25", language: "greek", lemma: "ἀγαπάω", translit: "agapáō",
                         definition: "to love (in a social or moral sense)", kjv_def: "(be-)love(-ed)")
    LexiconEntry.create!(strongs: "G2316", language: "greek", lemma: "θεός", translit: "theós",
                         definition: "figuratively, a magistrate", kjv_def: "God")
    LexiconEntry.create!(strongs: "H1254", language: "hebrew", lemma: "בָּרָא", translit: "bârâʼ", pron: "baw-raw'",
                         definition: "(absolutely) to create", kjv_def: "create")
    @study = @user.studies.create!(name: "Sunday", pane_count: 1)
    @study.panes.first.update!(reference: "John 3", translation: @kjv)
  end

  teardown do
    go_online
    clear_offline_data
  end

  test "preview KJV John 3:16 → click “loved” → project: the word study is on the projector and the stage" do
    start_preaching
    projector = open_screen("output")
    stage = open_screen("stage")

    # Stage John 3:16 in Preview (the projector doesn't move)…
    press_preach_key "g"
    find(".ps-preach-jump input").fill_in with: "John 3:16"
    find(".ps-preach-jump-preview").click
    assert_selector "[data-preview-target='previewLabel']", text: "John 3:16"

    # …open its root words from the Preview row and pick "loved".
    find(".ps-console-row.is-preview [data-root-words-open='preview']").click
    within(".rw-card") do
      assert_text(/John 3:16 · KJV/i)
      find(".rw-chip", text: "loved", exact_text: true).click
      assert_selector ".rw-detail-lemma", text: "ἀγαπάω"
      assert_text "Strong’s G25"
      assert_text "agapáō"
      assert_text "ah-gah-PAH-oh"
      assert_equal "to love; to cherish and seek the good of another", find(".rw-gloss-input").value
      click_on "Project"
    end
    assert_no_selector ".rw-card"

    assert_selector ".ps-preach-slide .rw-slide .rw-lemma", text: "ἀγαπάω"
    within_window(projector) do
      within(".ps-preach-slide .rw-slide") do
        assert_selector ".rw-lemma[lang='grc']", text: "ἀγαπάω"
        assert_selector ".rw-mark", text: "loved"
        assert_text(/Strong’s G25/i)
        assert_text "agapáō"
      end
      # The bundled Greek face is what draws it — no internet font needed.
      assert page.evaluate_async_script(<<~JS)
        const done = arguments[0]
        document.fonts.ready.then(() => done(document.fonts.check("48px 'RW Greek'", "ἀγαπάω")))
      JS
    end
    within_window(stage) do
      assert_selector ".ps-stage-now .rw-stage-lemma", text: "ἀγαπάω"
      assert_selector ".ps-stage-next .rw-mark", text: "loved"
    end

    # Esc returns to the verse, on every screen.
    press_preach_key :escape
    assert_no_selector ".ps-root.is-slide"
    within_window(projector) { assert_no_selector ".rw-slide" }
  end

  test "Hebrew, word only, queued for later: Genesis 1:1 “created” → bara, right to left" do
    start_preaching
    press_preach_key "g"
    find(".ps-preach-jump input").fill_in(with: "Gen 1:1").send_keys(:enter)
    assert_selector ".ps-verse.is-preach-current", text: "In the beginning"
    press_preach_key "w"
    within(".rw-card") do
      find(".rw-chip", text: "created", exact_text: true).click
      assert_selector ".rw-detail-lemma[dir='rtl']", text: "בָּרָא"
      assert_text "bah-RAH"
      click_on "+ Queue"
    end
    assert_selector ".ps-setlist-item.kind-word .lbl", text: "Word study: bara — Genesis 1:1"
    wait_until { @study.setlist_items.word.exists? }
    assert_equal "H1254", @study.setlist_items.word.last.word_study["s"]

    within(".rw-card") do
      click_on "Word only"
      find(".rw-project").click
    end
    within(".ps-preach-slide .rw-slide.is-word") do
      assert_selector ".rw-lemma[dir='rtl'][lang='he']", text: "בָּרָא"
      assert_no_selector ".rw-verse"
      assert_text(/“created” — Genesis 1:1/i)
    end

    # Back to the verse, then the queued study goes live from the queue.
    press_preach_key "b"
    assert_no_selector ".ps-root.is-slide"
    find(".ps-setlist-item.kind-word .present").double_click
    assert_selector ".ps-preach-slide .rw-slide .rw-lemma", text: "בָּרָא"
  end

  test "another translation maps through the KJV: tap the word on the live WEB verse" do
    @study.panes.first.update!(reference: "John 3:16", translation: @web)
    start_preaching
    assert_selector ".ps-verse.is-preach-current", text: "only born Son"
    press_preach_key "w"
    within(".rw-card") do
      assert_text(/John 3:16 · WEB/i)
      assert_text "Words from the KJV"
      assert_selector ".rw-chip", text: "only begotten"
    end
    # Pick by tapping the word on the live verse itself.
    tap_word_on_verse("loved")
    within(".rw-card") { assert_selector ".rw-chip.is-on", text: "loved" }
    within(".rw-card") { find(".rw-project").click }
    within(".ps-preach-slide .rw-slide") do
      assert_text(/John 3:16 · WEB/i)
      assert_selector ".rw-verse", text: "only born Son"
      assert_selector ".rw-mark", text: "loved"
      assert_selector ".rw-lemma", text: "ἀγαπάω"
    end
  end

  test "Ask Rabbi: a short explanation, editable, labelled AI on the slide" do
    original = AiChat.method(:call)
    reply = AiChat::Result.new(ok: true, provider: :gemini,
                               content: { explanation: "Agapaō is love that chooses another's good, whatever it costs." }.to_json)
    AiChat.singleton_class.define_method(:call) { |*, **| reply }
    start_preaching
    press_preach_key "g"
    find(".ps-preach-jump input").fill_in(with: "John 3:16").send_keys(:enter)
    assert_selector ".ps-verse.is-preach-current", text: "only begotten"
    press_preach_key "w"
    within(".rw-card") do
      find(".rw-chip", text: "loved", exact_text: true).click
      click_on "Ask Rabbi"
      assert_equal "Agapaō is love that chooses another's good, whatever it costs.", find(".rw-rabbi-text").value
      assert find(".rw-include input").checked?
      find(".rw-rabbi-text").fill_in with: "Agapaō: love that chooses another's good."
      find(".rw-project").click
    end
    within(".ps-preach-slide .rw-note") do
      assert_text(/AI-assisted/i)
      assert_text "Agapaō: love that chooses another's good."
    end
  ensure
    AiChat.singleton_class.define_method(:call, original) if original
  end

  test "offline: the word pack is saved on entering preach, root words work with a dead network" do
    start_preaching
    wait_until(timeout: 30) do
      page.evaluate_async_script(<<~JS)
        const done = arguments[0]
        const req = indexedDB.open("bibliorata-offline")
        req.onsuccess = () => {
          const tx = req.result.transaction("meta")
          const get = tx.objectStore("meta").get("rootWordPack")
          get.onsuccess = () => done(!!get.result)
          get.onerror = () => done(false)
        }
        req.onerror = () => done(false)
      JS
    end
    press_preach_key "g"
    find(".ps-preach-jump input").fill_in(with: "John 3:16").send_keys(:enter)
    assert_selector ".ps-verse.is-preach-current", text: "only begotten"
    go_dead_network
    press_preach_key "w"
    within(".rw-card") do
      assert_text(/Word data saved on this device/i)
      find(".rw-chip", text: "loved", exact_text: true).click
      assert_selector ".rw-detail-lemma", text: "ἀγαπάω"
      find(".rw-project").click
    end
    assert_selector ".ps-preach-slide .rw-slide .rw-lemma", text: "ἀγαπάω"
  end

  private

  def sign_in
    visit new_session_path
    fill_in "email_address", with: @user.email_address
    fill_in "password", with: "password"
    click_on "Sign In"
    assert_no_current_path new_session_path
  end

  def start_preaching
    sign_in
    visit study_path(@study)
    wait_for_service_worker
    wait_for_reader_js
    find(".ui-appbar button[data-action~='presentation#start']").click
    assert_selector ".ps-root.is-preaching"
    assert_selector ".ps-preach-offline[data-state='ready']", wait: 20
  end

  def open_screen(param)
    operator = current_window
    win = open_new_window
    within_window(win) do
      visit "#{study_path(@study)}?#{param}=1&pane=0"
      assert_selector ".ps-root.is-output"
    end
    switch_to_window(operator)
    win
  end

  def press_preach_key(key)
    find("body").send_keys(key)
  end

  # A real click on the word's own text in the live verse.
  def tap_word_on_verse(word)
    point = page.evaluate_script(<<~JS, word)
      (() => {
        const word = arguments[0]
        const verse = document.querySelector(".ps-pane.is-presented .ps-verse.is-preach-current .ps-verse-text")
        const walker = document.createTreeWalker(verse, NodeFilter.SHOW_TEXT)
        let node
        while ((node = walker.nextNode())) {
          const at = node.textContent.indexOf(word)
          if (at < 0) continue
          const range = document.createRange()
          range.setStart(node, at + 1); range.setEnd(node, at + 2)
          const r = range.getBoundingClientRect()
          return [ r.left + r.width / 2, r.top + r.height / 2 ]
        }
        return null
      })()
    JS
    assert point, "#{word} not on the live verse"
    page.driver.browser.action.move_to_location(point[0].round, point[1].round).click.perform
  end

  def wait_until(timeout: 15)
    Timeout.timeout(timeout) { sleep 0.2 until yield }
  end
end
