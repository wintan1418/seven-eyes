require "test_helper"

# Root word projection's services: the lexicon seed keeps Strong's Hebrew
# pronunciation, the offline pack's verse encoding, and the Ask-Rabbi
# explainer's guard rails (plain text, cached, graceful without a key).
class RootWordsServicesTest < ActiveSupport::TestCase
  test "the lexicon seeder keeps Hebrew pronunciation (its ' marks the stress)" do
    body = 'var strongsHebrewDictionary = {"H1254":{"lemma":"בָּרָא","xlit":"bârâʼ","pron":"baw-raw\'",' \
           '"derivation":"a primitive root;","strongs_def":"(absolutely) to create","kjv_def":"create"}}; module.exports = x;'
    seeder = LexiconSeeder.new("hebrew", "http://example.invalid", force: true)
    seeder.define_singleton_method(:download) { body }
    seeder.define_singleton_method(:say) { |_| }
    seeder.run
    entry = LexiconEntry.lookup("H1254")
    assert_equal "baw-raw'", entry.pron
    assert_equal "bârâʼ", entry.translit
  end

  test "pack verses: tagged words carry @number, untagged text stays, @ in text is dropped" do
    tokens = [ { "w" => "In the beginning", "s" => "H7225" }, { "w" => " God", "s" => "H430" }, { "w" => " a@b" }, { "w" => "." } ]
    assert_equal "In the beginning@7225 God@430 ab.", RootWordPack.encode_verse(tokens)
    assert_equal "", RootWordPack.encode_verse(nil)
  end

  test "RootWords.verse is nil without the KJV or the verse" do
    assert_nil RootWords.verse(osis: "John", chapter: 3, verse: 16)
  end

  test "the explainer refuses without an entry or verse, and reports a missing key" do
    assert_equal :not_found, RootWordExplainer.call(entry: nil, verse: nil, word: "x").error

    kjv = Translation.create!(code: "KJV", name: "King James Version")
    john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    verse = Verse.create!(translation: kjv, book: john, chapter: 3, verse_number: 16, text: "For God so loved the world")
    entry = LexiconEntry.create!(strongs: "G25", language: "greek", lemma: "ἀγαπάω", translit: "agapáō")
    explainer = RootWordExplainer.new(entry:, verse:, word: "loved")
    explainer.define_singleton_method(:chat_completion) { AiChat::Result.new(ok: false, error: :no_key) }
    assert_equal :no_key, explainer.call.error

    explainer.define_singleton_method(:chat_completion) { AiChat::Result.new(ok: true, content: "not json, just words", provider: :x) }
    assert_equal "not json, just words", explainer.call.text
  end
end
