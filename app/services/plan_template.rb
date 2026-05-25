# Generates a starting set of {day_number, refs} pairs for a new reading plan.
# Templates are just convenient defaults — every day's references can be edited
# afterwards, days added, days removed.
class PlanTemplate
  KINDS = %w[empty book new_testament bible_year].freeze

  def self.build(kind, options = {})
    case kind.to_s
    when "empty"          then []
    when "book"           then book(options)
    when "new_testament"  then segment_evenly(testament: :new, days: (options[:days].presence || 60).to_i)
    when "bible_year"     then segment_evenly(testament: nil,  days: (options[:days].presence || 365).to_i)
    else []
    end
  end

  # Pace one book at N chapters per day.
  def self.book(options)
    book = Book.find_by(osis_code: options[:book])
    return [] unless book

    per_day = [ options[:chapters_per_day].to_i, 1 ].max
    chapters = (1..book.chapter_count).to_a
    chapters.each_slice(per_day).map.with_index(1) do |slice, day_number|
      refs = slice.map { |c| "#{book.name} #{c}" }.join(", ")
      { day_number:, refs: }
    end
  end

  # Spread all chapters of (the whole Bible, or one testament) across N days,
  # roughly evenly.
  def self.segment_evenly(testament:, days:)
    return [] if days <= 0

    scope = Book.order(:position)
    scope = scope.where(testament:) if testament
    book_chapters = scope.flat_map { |b| (1..b.chapter_count).map { |c| [ b.name, c ] } }
    total = book_chapters.size
    return [] if total.zero?

    days.times.map do |i|
      from = (i * total) / days
      to   = ((i + 1) * total) / days
      slice = book_chapters[from...to] || []
      { day_number: i + 1, refs: slice.map { |bn, c| "#{bn} #{c}" }.join(", ") }
    end
  end
end
