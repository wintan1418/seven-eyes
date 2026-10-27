# Public, no-login landing pages for a shared passage (/p/:slug). This is where
# a shared verse image or prayer link brings people: a calm, on-brand page
# showing the text (and an optional chapter prayer) with a clear call to open
# the full workspace. Rich Open-Graph tags make the link unfurl nicely in chats.
class PassagesController < ApplicationController
  allow_unauthenticated_access only: %i[ show open ]

  def show
    @parsed = parse_slug
    return render_not_found unless @parsed&.valid?

    @book = Book.find_by_osis(@parsed.osis)
    return render_not_found unless @book

    @translation = resolve_translation
    @verses = Verse.for_reference(@parsed, translation: @translation, book: @book).to_a
    return render_not_found if @verses.empty?

    @reference = @parsed.label
    @slug = params[:slug]

    if params[:prayer].present?
      res = ChapterPrayer.call(book: @book, chapter: @parsed.chapter, translation: @translation)
      @prayer = res.prayer if res.ok?
    end
  end

  # "Open in Parallel Scripture" — load this passage into a workspace and go.
  def open
    parsed = parse_slug
    return redirect_to(root_path) unless parsed&.valid?

    translation = resolve_translation
    study = target_study(parsed.label)
    study.panes.first&.update(reference: parsed.label, translation:)
    redirect_to study_path(study)
  end

  private

  def parse_slug
    ref = PassageSlug.reference_for(params[:slug])
    ref && ReferenceParser.call(ref)
  end

  # Only translations readers may use: a link naming a hidden (licence-
  # restricted) or incomplete translation falls back to BSB, then the default.
  def resolve_translation
    offered = Translation.available
    offered.find_by(code: params[:t].to_s.upcase.presence) ||
      offered.find_by(code: "BSB") ||
      Translation.default
  end

  def target_study(label)
    if authenticated?
      current_user.studies.create!(name: label, pane_count: 1)
    elsif (existing = guest_study)
      existing
    else
      Study.create!(user: nil, name: label, pane_count: 1).tap do |s|
        session[:guest_study_id] = s.id
      end
    end
  end

  def guest_study
    return nil unless session[:guest_study_id]
    Study.find_by(id: session[:guest_study_id], user_id: nil)
  end

  def render_not_found
    render :not_found, status: :not_found
  end
end
