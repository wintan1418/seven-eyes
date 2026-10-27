# Everything a user has saved, as a plain Hash ready for JSON: their account
# details, studies (panes with notes, preach queue), highlights with notes, and
# reading plans with reflections. Verse references are spelled out ("John 3:16
# KJV") so the export stays meaningful outside BiblioRata.
class AccountExport
  FORMAT_VERSION = 1

  def self.call(user) = new(user).call

  def initialize(user)
    @user = user
  end

  def call
    {
      format: "bibliorata-export", version: FORMAT_VERSION, exported_at: Time.current.iso8601,
      account: { email_address: @user.email_address, created_at: @user.created_at.iso8601 },
      studies: studies,
      highlights: highlights,
      reading_plans: reading_plans
    }
  end

  private

  def studies
    @user.studies.includes(panes: :translation, setlist_items: []).order(:created_at).map do |study|
      {
        name: study.name, created_at: study.created_at.iso8601, updated_at: study.updated_at.iso8601,
        panes: study.panes.map do |pane|
          { position: pane.position, reference: pane.reference,
            translation: pane.translation&.code, notes: pane.notes }
        end,
        preach_queue: study.setlist_items.in_order.map do |item|
          { kind: item.kind, title: item.title, reference: item.reference,
            body: item.body, media_url: item.media_url }
        end
      }
    end
  end

  def highlights
    @user.highlights.includes(verse: %i[ book translation ]).order(:created_at).map do |h|
      verse = h.verse
      {
        reference: "#{verse.book.name} #{verse.chapter}:#{verse.verse_number}",
        translation: verse.translation.code, color: h.color,
        char_start: h.char_start, char_end: h.char_end,
        highlighted_text: verse.text.to_s[h.char_start...h.char_end],
        note: h.note, created_at: h.created_at.iso8601
      }
    end
  end

  def reading_plans
    @user.reading_plans.includes(plan_days: :completion).order(:created_at).map do |plan|
      {
        name: plan.name, description: plan.description, start_date: plan.start_date.iso8601,
        days: plan.plan_days.map do |day|
          { day: day.day_number, refs: day.refs, completed_at: day.completion&.completed_at&.iso8601,
            reflection: day.completion&.reflection }
        end
      }
    end
  end
end
