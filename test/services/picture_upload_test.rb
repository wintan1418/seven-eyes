require "test_helper"

class PictureUploadTest < ActiveSupport::TestCase
  # Test double: pretends Cloudinary is configured and skips the network.
  class FakeUpload < PictureUpload
    def self.configured? = true

    private

    def upload
      { "secure_url" => "https://res.cloudinary.com/demo/image/upload/v1/bibliorata/queue/x.jpg",
        "public_id" => "bibliorata/queue/x" }
    end
  end

  def file_upload(size: 1.kilobyte, type: "image/jpeg")
    tempfile = Tempfile.new([ "pic", ".jpg" ])
    tempfile.write("0" * size)
    tempfile.rewind
    ActionDispatch::Http::UploadedFile.new(tempfile: tempfile, filename: "pic.jpg", type: type)
  end

  test "a small image uploads and returns the CDN url" do
    result = FakeUpload.call(file_upload)
    assert result.ok?
    assert_match %r{\Ahttps://res\.cloudinary\.com/}, result.url
    assert_equal "bibliorata/queue/x", result.public_id
  end

  test "non-images are refused before any network call" do
    assert_equal :not_image, FakeUpload.call(file_upload(type: "application/pdf")).error
  end

  test "oversized files are refused before any network call" do
    assert_equal :too_large, FakeUpload.call(file_upload(size: PictureUpload::MAX_BYTES + 1)).error
  end

  test "a missing file is reported; without a picture host the file is kept on our server" do
    assert_equal :missing, FakeUpload.call(nil).error
    result = PictureUpload.call(file_upload) # test env never has a picture host
    assert result.ok?
    assert result.blob.present?
    assert_match %r{\A/rails/active_storage/blobs/}, result.url
  end

  test "every error code has a human message" do
    PictureUpload::ERROR_MESSAGES.each_key do |code|
      assert PictureUpload.message_for(code).present?
    end
  end
end
