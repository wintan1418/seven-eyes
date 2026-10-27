# Permanently delete a user and everything that belongs to them: studies (with
# panes, notes, preach queues, live sessions), highlights, reading plans,
# sign-in sessions, AI quotas, and any testimonials / feedback they left.
# Pictures they uploaded to Cloudinary for their preach queues are purged too.
class AccountDeletion
  def self.call(user) = new(user).call

  def initialize(user)
    @user = user
  end

  def call
    picture_ids = SetlistItem.where(study: @user.studies).where.not(media_public_id: [ nil, "" ])
                             .pluck(:media_public_id)

    ApplicationRecord.transaction do
      IllustrationQuota.where(owner_key: IllustrationQuota.key_for(@user)).delete_all
      delete_testimonials
      @user.destroy!
    end

    # Remote, best-effort, and only once the local delete has committed.
    picture_ids.each { |id| PictureUpload.purge(id) }
    true
  end

  private

  # The testimonials engine stores authors loosely (author_id string / email)
  # rather than by foreign key, so clear them explicitly.
  def delete_testimonials
    author_id = @user.id.to_s
    email = @user.email_address
    Testimonials::Testimonial.where(author_id: author_id).or(Testimonials::Testimonial.where(email: email)).destroy_all
    Testimonials::NpsResponse.where(author_id: author_id).or(Testimonials::NpsResponse.where(email: email)).delete_all
    Testimonials::PromptEvent.where(author_id: author_id).delete_all
  end
end
