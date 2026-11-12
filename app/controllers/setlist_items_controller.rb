# The preach queue ("setlist"): scripture references, songs, and thoughts the
# operator lines up before the service and walks through from the preach bar.
# Every action re-renders the queue's Turbo Frame; guests can build a queue on
# their session study (current_study resolves owner-or-guest). Pictures are
# hosted on Cloudinary, so uploading one needs an account and is capped per
# study (SetlistItem::PICTURE_LIMIT).
#
# The preach-mode queue is local-first: the device changes its own copy at once
# and replays each change here as JSON through the offline outbox. Those
# requests carry the device's id for the item (client_id, "tmp-…"), so a create
# replayed after a dropped connection returns the row it made the first time,
# and later updates / deletes / reorders can name an item whose server id the
# device hasn't heard yet. The HTML (Turbo Frame) responses stay for pictures
# and for a page without JavaScript.
class SetlistItemsController < ApplicationController
  allow_unauthenticated_access

  before_action :set_study

  # GET /studies/:study_id/setlist (JSON) — the queue as the server has it.
  def index
    render json: queue_json
  end

  def create
    return create_json if request.format.json?

    attrs = item_params
    return reject_kind(attrs) unless valid_kind?(attrs[:kind])
    return create_scriptures(attrs[:reference]) if attrs[:kind] == "scripture"

    if attrs[:kind] == "picture"
      error = picture_refusal
      error ||= begin
        upload = PictureUpload.call(params.dig(:setlist_item, :image))
        attrs = attrs.merge(media_url: upload.url, media_public_id: upload.public_id) if upload.ok?
        PictureUpload.message_for(upload.error) unless upload.ok?
      end
      return render_error(attrs, error) if error
    end
    item = @study.setlist_items.create(attrs)
    @errored = item unless item.persisted?
    render_setlist
  end

  def update
    attrs = item_params
    if request.format.json?
      return render_json_error("Pick what kind of item this is") if attrs.key?(:kind) && !valid_kind?(attrs[:kind])
      return render_json_error("Pictures can't be changed from here") if item.picture? || attrs[:kind] == "picture"
      return item.update(attrs) ? render(json: item_json(item)) : render_json_error(item.errors.full_messages.to_sentence)
    end
    return reject_kind(attrs) if attrs.key?(:kind) && !valid_kind?(attrs[:kind])

    was_picture = item.picture?
    old_public_id = item.media_public_id
    if was_picture && attrs[:kind].present? && attrs[:kind] != "picture"
      attrs = attrs.merge(media_url: nil, media_public_id: nil)
    end
    if item.update(attrs) && was_picture && !item.picture?
      PictureUpload.purge(old_public_id) # the picture left the queue
    end
    render_setlist
  end

  def destroy
    item.destroy
    PictureUpload.purge(item.media_public_id) if item.picture?
    return render(json: queue_json) if request.format.json?
    render_setlist
  end

  # POST /studies/:study_id/setlist_items/:id/move?direction=up|down
  def move
    item.move!(params[:direction])
    render_setlist
  end

  # PATCH /studies/:study_id/setlist/order {order: [id or client_id, …]} —
  # the whole order the device has, so replays and coalesced drags are safe.
  def order
    SetlistItem.arrange!(@study, params.require(:order))
    render json: queue_json
  end

  # GET /studies/:study_id/setlist/library — songs to drop in without retyping:
  # the public-domain hymnal plus songs this account has queued before.
  def library
    render json: { songs: SetlistItem.song_library_for(@study) }
  end

  private

  # A device-made item. Idempotent on client_id: the same create replayed (the
  # outbox retries after a timeout) returns the first row, never a twin.
  def create_json
    attrs = item_params
    client_id = params.dig(:setlist_item, :client_id).presence
    return render_json_error("Pick what kind of item this is") unless valid_kind?(attrs[:kind])
    return render_json_error("Add pictures from the queue form while online") if attrs[:kind] == "picture"

    existing = client_id && @study.setlist_items.find_by(client_id: client_id)
    return render(json: item_json(existing)) if existing

    item = @study.setlist_items.new(attrs.merge(client_id: client_id))
    begin
      saved = item.save
    rescue ActiveRecord::RecordNotUnique # a concurrent replay of the same create won
      return render(json: item_json(@study.setlist_items.find_by!(client_id: client_id)))
    end
    return render_json_error(item.errors.full_messages.to_sentence) unless saved

    position = params.dig(:setlist_item, :position)
    item.place_at!(position) if position.to_s.match?(/\A\d+\z/)
    render json: item_json(item.reload), status: :created
  end

  def item_json(item)
    item.as_queue_json.merge(position: item.position, server_time: server_time)
  end

  def queue_json
    { items: @study.setlist_items.in_order.map(&:as_queue_json), server_time: server_time }
  end

  def server_time = (Time.current.to_f * 1000).to_i

  def render_json_error(message)
    render json: { error: message }, status: :unprocessable_entity
  end

  # Queue one or several scriptures at once. A fast minister can drop in a whole
  # block — "John 3:16, Rom 8:28, Ps 23" or one reference per line — and each
  # becomes its own queue item in a single submit. Any that can't be read are
  # reported together while the rest are still added.
  def create_scriptures(raw)
    refs = raw.to_s.split(/[\n,;]+/).map(&:strip).reject(&:blank?)
    refs = [ raw.to_s ] if refs.empty? # let the model report the blank/invalid one

    failed = []
    refs.each do |ref|
      item = @study.setlist_items.create(kind: "scripture", reference: ref)
      failed << ref unless item.persisted?
    end

    if failed.any?
      @errored = @study.setlist_items.new(kind: "scripture", reference: failed.join(", "))
      @errored.errors.add(:reference,
        "couldn't be read: #{failed.to_sentence}. Try something like John 3:16.")
    end
    render_setlist
  end

  # Why a picture can't be added (before any upload is attempted), or nil.
  def picture_refusal
    return "Sign in to add pictures to the queue" unless authenticated?
    if @study.setlist_items.picture.count >= SetlistItem::PICTURE_LIMIT
      "This queue already holds #{SetlistItem::PICTURE_LIMIT} pictures — remove one first"
    end
  end

  def valid_kind?(kind)
    SetlistItem.kinds.key?(kind.to_s)
  end

  # An unknown kind (tampered form) is a 422 with the form re-rendered — never
  # an ArgumentError 500 from the enum.
  def reject_kind(attrs)
    render_error(attrs.except(:kind), "Pick what kind of item this is", status: :unprocessable_entity)
  end

  def render_error(attrs, message, status: :ok)
    @errored = @study.setlist_items.new(attrs.slice(:kind, :reference, :title, :body))
    @errored.errors.add(:base, message)
    render_setlist(status: status)
  end

  def set_study
    @study = current_study(params[:study_id])
  end

  def item
    @item ||= @study.setlist_items.find_by_any_id!(params[:id])
  end

  def item_params
    params.require(:setlist_item).permit(:kind, :reference, :title, :body)
  end

  def render_setlist(status: :ok)
    render partial: "studies/setlist", locals: { study: @study, errored: @errored },
           layout: false, status: status
  end
end
