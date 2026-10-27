# The preach queue ("setlist"): scripture references, songs, and thoughts the
# operator lines up before the service and walks through from the preach bar.
# Every action re-renders the queue's Turbo Frame; guests can build a queue on
# their session study (current_study resolves owner-or-guest). Pictures are
# hosted on Cloudinary, so uploading one needs an account and is capped per
# study (SetlistItem::PICTURE_LIMIT).
class SetlistItemsController < ApplicationController
  allow_unauthenticated_access

  before_action :set_study

  def create
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
    render_setlist
  end

  # POST /studies/:study_id/setlist_items/:id/move?direction=up|down
  def move
    item.move!(params[:direction])
    render_setlist
  end

  # GET /studies/:study_id/setlist/library — songs to drop in without retyping:
  # the public-domain hymnal plus songs this account has queued before.
  def library
    render json: { songs: SetlistItem.song_library_for(@study) }
  end

  private

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
    @item ||= @study.setlist_items.find(params[:id])
  end

  def item_params
    params.require(:setlist_item).permit(:kind, :reference, :title, :body)
  end

  def render_setlist(status: :ok)
    render partial: "studies/setlist", locals: { study: @study, errored: @errored },
           layout: false, status: status
  end
end
