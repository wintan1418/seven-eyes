require "application_system_test_case"

# "Rewrite with AI" on the review desk: Rewrite → Use all fills the edit form
# without saving; Save persists it and the term stays a draft. AiChat stubbed.
class FaithTermRewriterSystemTest < ApplicationSystemTestCase
  REPLY = {
    short_definition: "Righteousness is God's way of right, given to us on the account of faith and lived out by doing right.",
    new_believer: "Through faith God makes you right with Him, and His life in you does what is right.",
    explanation: "Righteousness is not a title but a function. \"He that doeth righteousness is righteous\" (1 John 3:7).\n\n" \
                 "It must first be revealed: \"therein is the righteousness of God revealed from faith to faith\" (Romans 1:17).",
    key_references: [ "1 John 3:7", "Romans 1:17", "Romans 3:22", "Galatians 9:99" ]
  }.to_json

  setup do
    kjv = Translation.create!(code: "KJV", name: "King James Version")
    john1 = Book.create!(osis_code: "1John", name: "1 John", testament: :new, position: 62, chapter_count: 5)
    rom = Book.create!(osis_code: "Rom", name: "Romans", testament: :new, position: 45, chapter_count: 16)
    Verse.create!(translation: kjv, book: john1, chapter: 3, verse_number: 7,
                  text: "Little children, let no man deceive you: he that doeth righteousness is righteous, even as he is righteous.")
    Verse.create!(translation: kjv, book: rom, chapter: 1, verse_number: 17,
                  text: "For therein is the righteousness of God revealed from faith to faith: as it is written, The just shall live by faith.")
    Verse.create!(translation: kjv, book: rom, chapter: 3, verse_number: 22,
                  text: "Even the righteousness of God which is by faith of Jesus Christ unto all and upon all them that believe: for there is no difference:")
    @term = FaithTerm.create!(name: "Righteousness", short_definition: "Being right with God.", explanation: "An older draft.")
    users(:one).update!(admin: true)

    @original = AiChat.method(:call)
    reply = AiChat::Result.new(ok: true, content: REPLY, provider: :openai)
    AiChat.singleton_class.define_method(:call) { |*, **| reply }
  end

  teardown { AiChat.singleton_class.define_method(:call, @original) }

  def sign_in
    visit new_session_path
    fill_in "email_address", with: users(:one).email_address
    fill_in "password", with: "password"
    click_on "Sign In"
    assert_no_current_path new_session_path
  end

  test "Rewrite → Use all fills the form; Save keeps it and the term stays a draft" do
    sign_in
    visit edit_admin_faith_term_path(@term)
    assert_selector "h2", text: /Rewrite with AI/i

    fill_in "Your words", with: "righteousness is not just u been seen somehow by jesus it is God way of right"
    find(".fr-chip", text: "Keep my wording").click
    click_on "Rewrite"

    within "#faith_rewrite" do
      assert_selector ".fr-new", text: "God's way of right"
      assert_selector ".fr-ok", text: "2 quotations checked"
      assert_text "Galatians 9:99"
      click_on "Use all"
      assert_text "press Save to keep it"
    end

    assert_field "faith_term_short_definition", with: /God's way of right/
    assert_field "faith_term_explanation", with: /not a title but a function/
    assert_field "faith_term_key_references", with: "1 John 3:7\nRomans 1:17\nRomans 3:22"
    assert_equal "Being right with God.", @term.reload.short_definition # nothing saved yet

    # A follow-up round carries the conversation (the history rides in the frame).
    within "#faith_rewrite" do
      fill_in "fr-follow-up", with: "make it shorter"
      click_on "Ask for changes"
      assert_selector "#fr-history", visible: false do |history|
        history.value.include?("make it shorter")
      end
    end
    assert_field "faith_term_short_definition", with: /God's way of right/ # the form keeps what was used

    click_on "Save"
    assert_text "saved"
    @term.reload
    assert_match(/God's way of right/, @term.short_definition)
    assert_equal [ "1 John 3:7", "Romans 1:17", "Romans 3:22" ], @term.key_references
    assert @term.draft?
  end
end
