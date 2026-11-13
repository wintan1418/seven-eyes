require "test_helper"

# Glossary of the Faith: the public sees reviewed terms only; admins and
# reviewers see drafts (badged) and use the review desk at /admin/faith.
class FaithTermsTest < ActionDispatch::IntegrationTest
  setup do
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    eph = Book.create!(osis_code: "Eph", name: "Ephesians", testament: :new, position: 49, chapter_count: 6)
    Verse.create!(translation: @kjv, book: eph, chapter: 2, verse_number: 8, text: "For by grace are ye saved through faith",
                  tokens: [ { "w" => "For", "s" => "G1063" }, { "w" => " by grace", "s" => "G5485" } ])
    LexiconEntry.create!(strongs: "G5485", language: "greek", lemma: "χάρις", translit: "cháris",
                         definition: "graciousness", kjv_def: "grace, favour")

    @grace = FaithTerm.create!(name: "Grace", short_definition: "God's undeserved favour.",
                               new_believer: "It is a gift.", explanation: "Grace is God's free gift.",
                               root_strongs: [ "G5485" ], key_references: [ "Ephesians 2:8" ],
                               related_slugs: [ "faith", "mercy" ], status: :reviewed, reviewed_by: "Pastor", reviewed_at: Time.current)
    @faith = FaithTerm.create!(name: "Faith", short_definition: "Trusting God.", position: 2)
    @mercy = FaithTerm.create!(name: "Mercy", short_definition: "Compassion.", position: 3, status: :reviewed)
  end

  test "the public glossary lists reviewed terms only" do
    get faith_terms_path
    assert_response :success
    assert_select ".ft-item-name", text: /Grace/
    assert_select ".ft-item-name", text: /Mercy/
    assert_select ".ft-item-name", text: /Faith/, count: 0
    assert_select ".ft-draft", count: 0
  end

  test "signed-out visitors get the glossary slider on the landing page: reviewed words, each linking to its page" do
    get root_path
    assert_response :success
    assert_select ".ld-glossary .hm-glossary.is-everywhere"
    assert_select ".hm-gl-slide[href=?]", faith_term_path(@grace)
    assert_select ".hm-gl-slide[href=?]", faith_term_path(@mercy)
    assert_select ".hm-gl-slide[href=?]", faith_term_path(@faith), count: 0
    assert_select ".hm-gl-slide.is-more[href=?]", faith_terms_path
    assert_select ".hm-gl-root", text: /χάρις/
    assert_select ".ld-foot-links a[href=?]", faith_terms_path
  end

  test "readers' testimonials are a slider on the landing page, not a stack" do
    3.times do |i|
      Testimonials::Testimonial.create!(kind: "text", status: "approved", source: "page", consent_given: true,
                                        name: "Reader #{i}", body: "It helps me prepare. #{i}")
    end
    get root_path
    assert_select ".ld-voices-slider[data-controller='shatter-slider'] .ld-voices-grid[data-shatter-slider-target='track']"
    assert_select ".ld-voice[data-shatter-slider-target='slide']", 3
    assert_select ".ld-voices-slider .hm-gl-dot", 3
  end

  test "no reviewed words: no slider or link on the landing page" do
    FaithTerm.update_all(status: FaithTerm.statuses[:draft])
    get root_path
    assert_response :success
    assert_select ".hm-glossary", count: 0
    assert_select ".ld-foot-links a[href=?]", faith_terms_path, count: 0
  end

  test "a term page: definition, root word from the lexicon, verse text linking into the reader, visible related terms" do
    get faith_term_path(@grace)
    assert_response :success
    assert_select "h1", "Grace"
    assert_select ".ft-term-def", "God's undeserved favour."
    assert_select ".ft-newbeliever", /It is a gift/
    assert_select ".ft-root .ft-lemma", "χάρις"
    assert_select ".ft-root .ft-translit", "cháris"
    assert_select ".ft-root-count", /In 1 verse of the KJV/
    assert_select ".ft-verses a[href=?]", open_passage_path("ephesians-2-8", t: "KJV"), text: /For by grace are ye saved/
    assert_select ".ft-related a", text: "Mercy"
    assert_select ".ft-related a", text: "Faith", count: 0
    assert_select ".ft-draft", count: 0
  end

  test "the explanation keeps the pastor's paragraphs" do
    @grace.update!(explanation: "Grace is a gift.\n\nIt keeps carrying us.\r\n\r\nIt is never a licence to sin.",
                   new_believer: "It is a gift.\n\nYou cannot earn it.")
    get faith_term_path(@grace)
    assert_select ".ft-explanation p", 3
    assert_select ".ft-explanation p", text: "It keeps carrying us."
    assert_select ".ft-newbeliever p", 2
  end

  test "the term page and the glossary show Bible art, credited, with a small and a large file" do
    get faith_term_path(@grace)
    art = FaithArt.for(@grace)
    assert_select ".ft-hero picture.ft-art[data-art=?]", art.key do
      assert_select "source[type='image/webp'][srcset*='-800'][srcset*='-1600']"
      assert_select "img[srcset*='-800'][srcset*='-1600'][alt='']"
    end
    assert_select ".ft-hero .ft-art-credit", text: art.credit

    get faith_terms_path
    assert_select ".ft-welcome picture.ft-art"
    assert_select ".ft-side .ft-item", 2

    get credits_path
    assert_select "#art li", FaithArt.all.size
  end

  test "a frame request gets the term without the side pane's list" do
    get faith_term_path(@grace), headers: { "Turbo-Frame" => "ft-content" }
    assert_response :success
    assert_select "turbo-frame#ft-content .ft-hero h1", "Grace"
    assert_select ".ft-side", count: 0
  end

  test "the public cannot open a draft, even by its URL" do
    get faith_term_path(@faith)
    assert_response :not_found

    sign_in_as users(:one)
    get faith_term_path(@faith)
    assert_response :not_found
  end

  test "with no reviewed terms the glossary doesn't exist yet and no menu link shows" do
    FaithTerm.update_all(status: FaithTerm.statuses[:draft])
    get faith_terms_path
    assert_response :not_found

    get more_path
    assert_select "a[href=?]", faith_terms_path, count: 0
  end

  test "the menu links to the glossary once a term is reviewed" do
    get more_path
    assert_select "a[href=?]", faith_terms_path
  end

  test "admins see drafts, badged" do
    users(:one).update!(admin: true)
    sign_in_as users(:one)
    get faith_terms_path
    assert_select ".ft-item-name", text: /Faith/
    assert_select ".ft-item .ft-draft", count: 1

    get faith_term_path(@faith)
    assert_response :success
    assert_select ".ft-draft", /Draft — awaiting pastor review/
  end

  test "reviewers (not admins) see drafts too" do
    users(:two).update!(reviewer: true)
    sign_in_as users(:two)
    get faith_term_path(@faith)
    assert_response :success
    get admin_faith_terms_path
    assert_response :success
  end

  test "the home card shows today's reviewed term to a signed-in user" do
    sign_in_as users(:one)
    get root_path
    assert_select ".ft-card" do
      assert_select ".ft-card-term a[href=?]", faith_term_path(FaithTerm.of_the_day)
      assert_select ".ft-card-actions a[href=?]", faith_terms_path
    end
    assert_select ".ft-card .ft-draft", count: 0
  end

  test "no reviewed terms, no home card" do
    FaithTerm.update_all(status: FaithTerm.statuses[:draft])
    sign_in_as users(:one)
    get root_path
    assert_response :success
    assert_select ".ft-card", count: 0
  end

  test "the review desk is closed to guests and ordinary users" do
    get admin_faith_terms_path
    assert_redirected_to new_session_path

    sign_in_as users(:one)
    get admin_faith_terms_path
    assert_redirected_to root_path
    post review_admin_faith_term_path(@faith)
    assert_redirected_to root_path
    assert @faith.reload.draft?
  end

  test "an admin marks a draft reviewed (who + when) and it goes public; sending back hides it" do
    users(:one).update!(admin: true)
    sign_in_as users(:one)
    get admin_faith_terms_path
    assert_response :success
    assert_select "##{@faith.slug} .ft-status", "Draft"

    post review_admin_faith_term_path(@faith), params: { reviewed_by: "Pastor Ade" }
    assert_redirected_to admin_faith_terms_path(anchor: "faith")
    @faith.reload
    assert @faith.reviewed?
    assert_equal "Pastor Ade", @faith.reviewed_by
    assert_not_nil @faith.reviewed_at

    sign_out
    get faith_term_path(@faith)
    assert_response :success

    sign_in_as users(:one)
    delete review_admin_faith_term_path(@faith)
    assert @faith.reload.draft?
    sign_out
    get faith_term_path(@faith)
    assert_response :not_found
  end

  test "editing a reviewed term's words sends it back to draft; 'Save and mark reviewed' keeps it public" do
    users(:one).update!(admin: true)
    sign_in_as users(:one)

    patch admin_faith_term_path(@grace), params: { faith_term: { short_definition: "Undeserved kindness.",
                                                                  key_references: "Ephesians 2:8\nRomans 3:24",
                                                                  root_strongs: "G5485, h2580" } }
    assert_redirected_to admin_faith_terms_path(anchor: "grace")
    @grace.reload
    assert @grace.draft?
    assert_equal "Undeserved kindness.", @grace.short_definition
    assert_equal [ "Ephesians 2:8", "Romans 3:24" ], @grace.key_references
    assert_equal %w[ G5485 H2580 ], @grace.root_strongs
    assert_not_nil @grace.edited_at

    patch admin_faith_term_path(@grace), params: { faith_term: { explanation: "Reworded." },
                                                   mark_reviewed: "1", reviewed_by: "Pastor Ade" }
    @grace.reload
    assert @grace.reviewed?
    assert_equal "Pastor Ade", @grace.reviewed_by
  end

  test "a bad reference is refused with the form shown again" do
    users(:one).update!(admin: true)
    sign_in_as users(:one)
    patch admin_faith_term_path(@grace), params: { faith_term: { key_references: "Hezekiah 4:1" } }
    assert_response :unprocessable_entity
    assert_select ".ft-review-errors", /Hezekiah 4:1/
    assert @grace.reload.reviewed?
  end
end
