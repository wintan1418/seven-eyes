# The glossary review desk (/admin/faith): no theology goes public until a
# pastor has read it. Lists every term with its status; a reviewer can edit the
# text, "Mark reviewed" (records who and when) or send a term back to draft.
#
# Open to admins and reviewers (`bin/rails reviewer:grant EMAIL=...`), like
# AdminController's require_admin. Editing the words of a reviewed term sends
# it back to draft, so a changed text is always re-read before it is public.
class FaithTermReviewsController < ApplicationController
  before_action :require_reviewer
  before_action :set_term, except: :index

  REVIEWED_TEXT = %w[ name short_definition new_believer explanation root_strongs key_references aliases ].freeze

  def index
    @terms = FaithTerm.order(:status, :position, :id).to_a # drafts first: the work to do
    @reviewed_count = @terms.count(&:reviewed?)
  end

  def edit
  end

  def update
    @term.assign_attributes(term_params)
    text_changed = (@term.changed & REVIEWED_TEXT).any?
    @term.edited_at = Time.current if @term.changed?
    sent_back = text_changed && @term.reviewed?
    if sent_back
      @term.status = :draft
      @term.reviewed_by = @term.reviewed_at = nil
    end

    if @term.save
      @term.mark_reviewed!(by: reviewer_name) if params[:mark_reviewed].present?
      redirect_to admin_faith_terms_path(anchor: @term.slug), notice: update_notice(sent_back)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def review
    @term.mark_reviewed!(by: reviewer_name)
    redirect_to admin_faith_terms_path(anchor: @term.slug), notice: "“#{@term.name}” is reviewed and now public."
  end

  def unreview
    @term.send_back_to_draft!
    redirect_to admin_faith_terms_path(anchor: @term.slug), notice: "“#{@term.name}” is back in draft and hidden from the public."
  end

  private

  def require_reviewer
    return if authenticated? && current_user.faith_reviewer?
    redirect_to root_path, alert: "That page isn't available."
  end

  def set_term
    @term = FaithTerm.find_by!(slug: params[:slug])
  end

  # The name typed beside "Mark reviewed" (remembered for next time), else the
  # reviewer's email.
  def reviewer_name
    typed = params[:reviewed_by].to_s.squish.first(80)
    session[:faith_reviewer_name] = typed if typed.present?
    typed.presence || session[:faith_reviewer_name].presence || current_user.email_address
  end
  helper_method :reviewer_name_default

  def reviewer_name_default
    session[:faith_reviewer_name].presence || current_user.email_address
  end

  def update_notice(sent_back)
    if params[:mark_reviewed].present? then "“#{@term.name}” saved and marked reviewed."
    elsif sent_back then "“#{@term.name}” saved. Its words changed, so it is back in draft until it is reviewed again."
    else "“#{@term.name}” saved."
    end
  end

  # Lists come from textareas: one per line (references may also be split by ";").
  def term_params
    raw = params.require(:faith_term).permit(:name, :short_definition, :new_believer, :explanation,
                                             :aliases, :root_strongs, :key_references, :related_slugs)
    raw.to_h.to_h do |key, value|
      case key
      when "aliases", "related_slugs" then [ key, value.to_s.split(/[\n,]/) ]
      when "root_strongs" then [ key, value.to_s.split(/[\s,]+/) ]
      when "key_references" then [ key, value.to_s.split(/[\n;]/) ]
      else [ key, value.to_s.strip ]
      end
    end
  end
end
