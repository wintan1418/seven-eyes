# Loads the Glossary of the Faith from config/faith_terms.yml (bin/rails
# faith_terms:seed, also run by db:seed). Idempotent and safe on production:
#
# - a term not in the database yet is created as a DRAFT;
# - a draft nobody has touched on the site is refreshed from the file;
# - a reviewed term, or one edited on /admin/faith, is never changed.
#
# Nothing is ever deleted. Returns counts: { created:, updated:, kept: }.
class FaithTermSeeder
  SOURCE = Rails.root.join("config/faith_terms.yml")

  def self.call(source = SOURCE)
    new(source).call
  end

  def initialize(source)
    @source = source
  end

  def call
    counts = { created: 0, updated: 0, kept: 0 }
    entries.each_with_index do |entry, index|
      term = FaithTerm.find_or_initialize_by(slug: entry.fetch("slug"))
      if term.new_record?
        term.assign_attributes(attributes(entry, index))
        term.save!
        counts[:created] += 1
      elsif term.draft? && term.edited_at.nil?
        term.assign_attributes(attributes(entry, index))
        counts[term.changed? ? :updated : :kept] += 1
        term.save! if term.changed?
      else
        counts[:kept] += 1
      end
    end
    counts
  end

  private

  def entries
    YAML.safe_load_file(@source)
  end

  def attributes(entry, index)
    {
      name: entry.fetch("name"),
      aliases: Array(entry["aliases"]),
      short_definition: entry.fetch("short").to_s.squish,
      new_believer: entry["new_believer"].to_s.squish.presence,
      explanation: entry["explanation"].to_s.squish.presence,
      root_strongs: Array(entry["roots"]),
      key_references: Array(entry["verses"]),
      related_slugs: Array(entry["related"]),
      position: index + 1
    }
  end
end
