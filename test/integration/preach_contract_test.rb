require "test_helper"

# The study page is driven LIVE in church: preach mode, the projector/stage
# windows, phone followers, the phone remote and the setlist all find their way
# around the page through the class names, data hooks and form fields pinned
# here. A redesign may move things and restyle them, but every hook below must
# survive — if one of these assertions fails, a pastor's Sunday breaks.
class PreachContractTest < ActionDispatch::IntegrationTest
  ROOT_CONTROLLERS = %w[presentation live setlist remote font-size diff interlinear].freeze

  PREACH_HOOKS = %w[
    data-preach-counter data-preach-group data-preach-anchor-pin data-preach-anchor-home
    data-preach-back data-preach-parallel data-preach-split data-preach-emph data-preach-project
    data-preach-blank data-preach-next data-preach-ref data-preach-slide data-preach-hold
    data-preach-join data-preach-finds data-stage-ref data-stage-clock data-stage-now data-stage-next
  ].freeze

  # Root classes the presentation/live/diff/interlinear controllers toggle and
  # the preach CSS hangs off.
  ROOT_STATE_CLASSES = %w[
    is-presenting is-preaching is-parallel is-split split-2 split-3 split-4 is-slide is-blank
    is-joining is-emphasising is-output is-stage is-projecting out-theme-ink out-theme-paper
    is-live-session is-diff is-interlinear
  ].freeze

  WINDOW_EVENTS = %w[
    setlist:present preach:command preach:join preach:state preach:notice auth:required
    notes:flush lexicon:open rabbi:ask share:open
  ].freeze

  setup do
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    @bsb = Translation.create!(code: "BSB", name: "Berean Standard Bible")
    @john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    tokens = [ { "w" => "For", "s" => "G1063" }, { "w" => " God so loved the world." } ]
    (15..17).each do |v|
      Verse.create!(translation: @kjv, book: @john, chapter: 3, verse_number: v,
                    text: v == 16 ? "For God so loved the world." : "Verse #{v} text.",
                    tokens: (tokens if v == 16))
      Verse.create!(translation: @bsb, book: @john, chapter: 3, verse_number: v, text: "BSB #{v}.")
    end
    sign_in_as users(:one)
    @study = users(:one).studies.create!(name: "Sunday", pane_count: 2)
    @study.panes.each { |p| p.update!(reference: "John 3", translation: @kjv) }
  end

  test "the workspace root carries every controller preach mode cooperates with" do
    get_study
    root = css_select(".ps-root").sole
    controllers = root["data-controller"].split
    ROOT_CONTROLLERS.each { |c| assert_includes controllers, c, "#{c} must live on .ps-root" }
    assert root["data-font-size"].present?
    assert root["data-live-url-value"].present?
    assert root["data-remote-url-value"].present?
    assert root["data-setlist-library-url-value"].present?
    assert root["data-presentation-quick-find-url-value"].present?
  end

  test "preach chrome hooks are all on the page" do
    get_study
    PREACH_HOOKS.each { |hook| assert_select ".ps-root [#{hook}]", { minimum: 1 }, "missing [#{hook}]" }
    assert_select "[data-preach-group]", 3
    assert_select ".ps-screen-panel"
    assert_select ".ps-preach-bar"
    assert_select ".ps-preach-enter[data-action~='presentation#enterPreach']"
    assert_select ".ps-preach-jump input[data-presentation-target='jumpInput']"
    assert_select "[data-action~='setlist#toggle']", minimum: 1
    assert_select "[data-live-target='button'][data-action~='live#toggle']"
    assert_select "[data-live-target='chip'] [data-live-target='count']"
    assert_select "[data-remote-target='button'][data-action~='remote#toggle']"
  end

  test "a way into preach mode is always on the page" do
    get_study
    assert_select "[data-action~='presentation#start'], [data-action~='presentation#enter']", minimum: 1
  end

  test "panes are frames in the workspace, in position order, with the form fields preach mode drives" do
    get_study
    panes = css_select(".ps-workspace .ps-pane")
    assert_equal @study.panes.map(&:frame_id), panes.map { |p| p["id"] }
    assert_equal @study.panes.map { |p| "pane_#{p.id}" }, panes.map { |p| p["id"] }
    panes.each do |pane|
      # presentation_controller reads the FIRST pane[reference] input in the
      # pane (prev/next chapter buttons carry their own) — it must be the
      # pane's own form, the one that also holds the translation select.
      input = css_select(pane, "input[name='pane[reference]']").first
      form = input.ancestors("form").first
      assert form, "the reference field must sit in a form"
      assert_equal 1, css_select(form, "select[name='pane[translation_id]']").size,
                   "reference and translation share one form"
      select = css_select(pane, "select[name='pane[translation_id]']").sole
      codes = css_select(select, "option").map { |o| o.text.strip }
      assert_includes codes, "KJV", "option text must be the bare translation code"
      assert_equal "KJV", css_select(select, "option[selected]").sole.text.strip
    end
    assert_select ".ps-workspace[data-controller~='sync-scroll']"
  end

  test "verse DOM keeps the attributes highlights, preach and followers read" do
    get_study
    verse = css_select(".ps-pane .ps-verse[data-verse-num='16']").first
    assert verse, "verse 16 should render"
    assert_equal "John", verse["data-osis"]
    assert_equal "3", verse["data-chapter"]
    assert_select verse, ".ps-vnum", 1
    text = css_select(verse, ".ps-verse-text").sole
    assert text["data-verse-id"].present?
    assert text["data-offset-base"].present?
    assert_select ".ps-pane .ps-verses .ps-verse-body[data-controller~='highlighter'] .ps-verse", minimum: 3
    assert_select ".ps-pane .ref-title", minimum: 1
    assert_select ".ps-pane .ps-word", minimum: 1
  end

  test "notes form keeps its field, controller and class" do
    get_study
    assert_select ".ps-pane form.ps-notes-form[data-controller~='notes'] textarea[name='pane[notes]'].ps-notes-area", 2
  end

  test "drawers and their frames stay reachable" do
    get_study
    %w[xref_drawer commentary_drawer lexicon_drawer rabbi_drawer setlist].each do |frame|
      assert_select "turbo-frame##{frame}", { count: 1 }, "frame #{frame}"
    end
    assert_select "[data-setlist-target='host']"
    assert_select "[data-live-target='panel']"
    assert_select "[data-remote-target='panel']"
  end

  test "the projector and stage windows render the same page, marked server-side" do
    get study_path(@study, output: 1, pane: 1)
    assert_response :success
    assert_select ".ps-root.is-output"
    assert_select ".ps-workspace .ps-pane", 2
    assert_select ".ps-root[data-controller~='tour']", 0

    get study_path(@study, stage: 1)
    assert_select ".ps-root.is-output"
    assert_select ".ps-stage [data-stage-now]"
  end

  test "new page chrome is marked so preach and output hide it" do
    get_study
    css = Rails.root.join("app/assets/stylesheets").glob("**/*.css").map(&:read).join("\n")
    assert css.match?(/\.ps-root\.is-presenting \[data-chrome\]/), "presenting must hide [data-chrome]"
    assert css.match?(/\.ps-root\.is-output \[data-chrome\]/), "output must hide [data-chrome]"
    # The reading column must not narrow the projected verse.
    assert css.match?(/\.ps-root:is\(\.is-presenting, \.is-output\) \.rd-column \{ display: contents; \}/),
           "the reading column steps aside while presenting"
  end

  test "the JS side of the contract: channel name, window events, root state classes" do
    js = Rails.root.join("app/javascript/controllers").glob("*.js").map(&:read).join("\n")
    presentation = Rails.root.join("app/javascript/controllers/presentation_controller.js").read
    assert_includes presentation, "ps-preach:${window.location.pathname}"
    assert_includes presentation, ".ps-workspace .ps-pane"
    WINDOW_EVENTS.each { |name| assert_includes js, %("#{name}"), "window event #{name}" }
    css = Rails.root.join("app/assets/stylesheets").glob("**/*.css").map(&:read).join("\n")
    ROOT_STATE_CLASSES.each do |klass|
      assert js.include?(%("#{klass}")) || css.match?(/\.ps-root[.\w-]*\.#{klass}\b/),
             "root state class #{klass} lost from JS and CSS"
    end
    %w[is-presenting is-preaching is-output is-stage is-split is-blank is-slide].each do |klass|
      assert css.match?(/\.ps-root[.\w-]*\.#{klass}\b/), "preach CSS for .ps-root.#{klass}"
    end
  end

  private

  def get_study
    get study_path(@study)
    assert_response :success
  end
end
