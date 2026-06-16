# The preach queue ("setlist"): scripture references, songs, and thoughts the
# operator lines up before the service and walks through from the preach bar.
# Every action re-renders the queue's Turbo Frame; guests can build a queue on
# their session study (current_study resolves owner-or-guest).
class SetlistItemsController < ApplicationController
  allow_unauthenticated_access

  before_action :set_study

  def create
    attrs = item_params
    return create_scriptures(attrs[:reference]) if attrs[:kind] == "scripture"

    if attrs[:kind] == "picture"
      upload = PictureUpload.call(params.dig(:setlist_item, :image))
      unless upload.ok?
        @errored = @study.setlist_items.new(attrs)
        @errored.errors.add(:base, PictureUpload.message_for(upload.error))
        return render_setlist
      end
      attrs = attrs.merge(media_url: upload.url, media_public_id: upload.public_id)
    end
    item = @study.setlist_items.create(attrs)
    @errored = item unless item.persisted?
    render_setlist
  end

  def update
    item.update(item_params)
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

  def set_study
    @study = current_study(params[:study_id])
  end

  def item
    @item ||= @study.setlist_items.find(params[:id])
  end

  def item_params
    params.require(:setlist_item).permit(:kind, :reference, :title, :body)
  end

  def render_setlist
    render partial: "studies/setlist", locals: { study: @study, errored: @errored }, layout: false
  end
end
