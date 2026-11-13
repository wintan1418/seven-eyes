# One entry in a study's preach queue (the service "setlist"): the planned
# order of what goes on the big screen. Four kinds:
#   scripture — a reference, chased through the presented pane like the Go box
#   song      — title + lyrics; blank lines split the body into stanza slides,
#               which may carry section labels ([Verse 1], [Chorus]…) and an
#               arrangement ("V1 C V2 C") — see SongSheet
#   thought   — a freeform note/announcement projected as a single slide
#   picture   — a Cloudinary-hosted image (announcement slide, sermon graphic)
class SetlistItem < ApplicationRecord
  belongs_to :study

  enum :kind, { scripture: 0, song: 1, thought: 2, picture: 3 }

  # Cloudinary-hosted pictures are capped per study so one queue can't be used
  # to park unlimited images on our hosting account.
  PICTURE_LIMIT = 30

  validates :position, presence: true
  validates :arrangement, length: { maximum: 200 }
  validates :client_id, length: { maximum: 64 }, format: { with: /\A[\w-]+\z/ }, allow_nil: true
  validate :picture_limit, on: :create, if: :picture?
  validates :reference, presence: true, if: :scripture?
  validates :media_url, presence: true, if: :picture?
  validate :reference_must_parse, if: :scripture?
  validate :slide_must_have_content, if: -> { song? || thought? }

  scope :in_order, -> { order(:position, :id) }

  before_create :assign_position

  # The song bank: songs the pastor can drop into the queue without retyping the
  # lyrics. First the account's saved songs ("Save to my songs"), then the ones
  # it has queued before (most-recent first), then the public-domain hymnal. A
  # signed-in owner sees songs from all their studies; a guest only sees their
  # own session study. Deduped by title (the operator's own version wins over
  # the hymnal default, since they may have tweaked it).
  PAST_SONG_LIMIT = 300

  def self.song_library_for(study)
    saved = study.user ? study.user.songs.recent_first.limit(Song::LIMIT).map(&:as_library_json) : []
    scope = study.user_id ? where(study: Study.where(user_id: study.user_id)) : where(study: study)
    used = scope.song.where.not(body: [ nil, "" ])
                .order(updated_at: :desc).limit(PAST_SONG_LIMIT)
                .map { |s| { title: s.title.to_s, body: s.body.to_s, arrangement: s.arrangement.to_s, source: "yours" } }
    hymns = Hymnal::HYMNS.map do |h|
      { title: h[:title], body: h[:body], arrangement: "", author: h[:author], year: h[:year],
        copyright: "Public domain", source: "hymnal" }.compact
    end

    seen = {}
    (saved + used + hymns).each do |song|
      key = song[:title].downcase.strip
      next if key.blank?
      seen[key] ||= song
    end
    seen.values
  end

  # What the queue list shows for this item.
  def label
    return parsed&.label || reference if scripture?
    return title.presence || "Picture" if picture?
    title.presence || body.to_s.strip.lines.first.to_s.strip.truncate(60)
  end

  def parsed
    return nil unless scripture? && reference.present?
    @parsed ||= ReferenceParser.call(reference)
  end

  # The slides' words in projection order: the body split on blank lines, with
  # section labels taken off and the arrangement (or a hymn's refrain) applied.
  def stanzas
    song_sheet.slides.map(&:text)
  end

  def song_sheet
    SongSheet.new(body, arrangement)
  end

  # The queue as the device-side controller holds it (setlist_controller.js).
  def as_queue_json
    {
      id: id, client_id: client_id, kind: kind, reference: reference, label: label,
      title: title, body: body, arrangement: arrangement, image: media_url,
      stanzas: (song? || thought?) ? stanzas.size : 0
    }
  end

  # Find by server id ("42") or by the id the device gave it ("tmp-…").
  def self.find_by_any_id!(key)
    key.to_s.match?(/\A\d+\z/) ? find(key) : find_by!(client_id: key.to_s)
  end

  # Put the queue in the given order. `keys` are server ids or client ids
  # (an item made offline may not know its server id yet); anything not named
  # keeps its relative order after them. Positions are renumbered densely.
  def self.arrange!(study, keys)
    items = study.setlist_items.in_order.to_a
    rank = {}
    Array(keys).each_with_index { |k, i| rank[k.to_s] ||= i }
    ordered = items.each_with_index.sort_by do |item, i|
      r = rank[item.id.to_s] || (item.client_id && rank[item.client_id])
      r ? [ 0, r, i ] : [ 1, 0, i ]
    end.map(&:first)
    renumber!(ordered)
  end

  # Move this item to index `position` (clamped) in its study's queue.
  def place_at!(position)
    items = study.setlist_items.in_order.to_a.reject { |s| s.id == id }
    index = position.to_i.clamp(0, items.size)
    self.class.renumber!(items.insert(index, self))
  end

  def self.renumber!(items)
    transaction do
      items.each_with_index { |s, i| s.update_column(:position, i) unless s.position == i }
    end
  end

  # Swap with the neighbour above/below, renumbering the whole list so
  # positions stay dense no matter what was deleted in between.
  def move!(direction)
    siblings = study.setlist_items.in_order.to_a
    idx = siblings.index { |s| s.id == id }
    other = direction.to_s == "up" ? idx - 1 : idx + 1
    return if idx.nil? || other.negative? || other >= siblings.size
    siblings[idx], siblings[other] = siblings[other], siblings[idx]
    transaction do
      siblings.each_with_index { |s, i| s.update_column(:position, i) }
    end
  end

  private

  def assign_position
    self.position = (study.setlist_items.maximum(:position) || -1) + 1
  end

  def reference_must_parse
    return if reference.blank?
    parsed_ref = ReferenceParser.call(reference)
    unless parsed_ref.valid? && Book.find_by_osis(parsed_ref.osis)
      errors.add(:reference, "couldn't be read — try something like John 3:16")
    end
  end

  def picture_limit
    return unless study && study.setlist_items.picture.where.not(id: id).count >= PICTURE_LIMIT
    errors.add(:base, "A queue can hold at most #{PICTURE_LIMIT} pictures")
  end

  def slide_must_have_content
    errors.add(:base, "Give it a title or some words") if title.blank? && body.blank?
  end
end
