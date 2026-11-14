# Home's "For you": two or three small cards drawn from what the reader has
# actually been doing — never filler. A card with nothing real behind it is
# left out, and with no cards the section doesn't render.
#
#   :term  — "You've been reading Romans → Righteousness": the first recently
#            read book that a glossary word cites in its key verses (reviewed
#            words only, unless the viewer reviews them).
#   :xrefs — "Psalm 23 is linked to 112 passages": the TSK cross-references
#            out of the last chapter read (one COUNT).
#   :plan  — no reading plan yet: one tap starts a plan through the book
#            they've been reading, a chapter a day (or John in 21 days).
#
# `studies` are the home's recent studies, already loaded with their panes;
# `terms` the glossary words the viewer may see, already loaded for the slider.
class ForYou
  Card = Data.define(:kind, :eyebrow, :title, :body, :href, :cta, :plan_params, :term)
  MAX_BOOKS = 4
  FALLBACK_PLAN_BOOK = "John"

  def self.call(...) = new(...).cards

  def initialize(studies:, terms:, active_plan: nil, skip_term: nil)
    @studies = Array(studies).reject(&:quick_present?)
    @terms = Array(terms)
    @active_plan = active_plan
    @skip_term = skip_term
  end

  def cards
    [ term_card, xrefs_card, plan_card ].compact
  end

  # Recently read passages, newest first, one per book.
  def recent_readings
    @recent_readings ||= @studies.filter_map do |study|
      ref = study.panes.min_by(&:position)&.reference.presence
      parsed = ref && ReferenceParser.call(ref)
      parsed if parsed&.valid?
    end.uniq(&:osis).first(MAX_BOOKS)
  end

  private

  def term_card
    recent_readings.each do |reading|
      term = term_for_book(reading.osis)
      next unless term

      return Card.new(
        kind: :term, eyebrow: "You’ve been reading #{reading.book_name}", title: term.name,
        body: term.short_definition.truncate(120, separator: " "),
        href: "/faith/#{term.slug}", cta: "Read about #{term.name.downcase}", plan_params: nil, term:
      )
    end
    nil
  end

  # A glossary word whose key verses are in this book (the same chapter wins
  # only by order — terms are already in glossary order).
  def term_for_book(osis)
    candidates = @terms.select { |t| term_books(t).include?(osis) }
    candidates.find { |t| t != @skip_term } || candidates.first
  end

  def book_for(osis)
    (@books ||= {}).fetch(osis) { @books[osis] = Book.find_by_osis(osis) }
  end

  def term_books(term)
    (@term_books ||= {})[term.id] ||= term.key_references.filter_map do |ref|
      parsed = ReferenceParser.call(ref)
      parsed.osis if parsed.valid?
    end.to_set
  end

  def xrefs_card
    reading = recent_readings.first
    return nil unless reading

    book = book_for(reading.osis)
    return nil unless book

    count = CrossReference.where(from_book_id: book.id, from_chapter: reading.chapter).count
    return nil if count.zero?

    chapter = "#{reading.book_name} #{reading.chapter}"
    Card.new(
      kind: :xrefs, eyebrow: "Go deeper", title: "#{chapter} is linked to #{ActiveSupport::NumberHelper.number_to_delimited(count)} passages",
      body: "Tap any verse in #{chapter}, then Cross-references, to follow where Scripture echoes it.",
      href: "/read?ref=#{ERB::Util.url_encode(chapter)}", cta: "Open #{chapter}", plan_params: nil, term: nil
    )
  end

  def plan_card
    return nil if @active_plan

    reading = recent_readings.first
    book = book_for(reading&.osis || FALLBACK_PLAN_BOOK)
    return nil unless book

    days = book.chapter_count
    Card.new(
      kind: :plan, eyebrow: "A daily rhythm",
      title: "#{book.name}, a chapter a day",
      body: reading ? "You’ve been in #{book.name}. Read it through in #{days} #{'day'.pluralize(days)}, one chapter each morning." :
                      "Begin with the Gospel of John: #{days} days, one chapter each morning.",
      href: nil, cta: "Start this plan",
      plan_params: { name: "#{book.name} in #{days} #{'day'.pluralize(days)}", template: "book", book: book.osis_code, chapters_per_day: 1 },
      term: nil
    )
  end
end
