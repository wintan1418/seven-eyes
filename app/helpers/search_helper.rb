# Wording for Bible search results (the /search page and the reader's search
# sheet), from a ScriptureSearch::Result.
module SearchHelper
  # "Showing 4 verses containing dew and rain"
  def search_summary(result, translation)
    words = result.terms_label.presence || result.query
    shown = result.all_hits.size
    if result.all_count.positive?
      count = shown < result.all_count ? "#{shown} of #{result.all_count}" : result.all_count.to_s
      "Showing #{count} #{'verse'.pluralize(result.all_count)} containing #{words} · #{translation&.code}"
    elsif result.any?
      "No verse has #{words} together · #{pluralize(result.any_count, 'verse')} with some of the words · #{translation&.code}"
    else
      "No verses containing #{words} in the #{translation&.code}"
    end
  end

  # Book filter choices: All, Old / New Testament, then every book.
  def search_scope_options(selected)
    selected = selected.presence || "all"
    books = Book.all.to_a
    groups = [
      [ "Old Testament books", books.select(&:testament_old?).map { |b| [ b.name, b.osis_code ] } ],
      [ "New Testament books", books.select(&:testament_new?).map { |b| [ b.name, b.osis_code ] } ]
    ]
    safe_join([
      options_for_select([ [ "All books", "all" ], [ "Old Testament", "ot" ], [ "New Testament", "nt" ] ], selected),
      grouped_options_for_select(groups, selected)
    ])
  end
end
