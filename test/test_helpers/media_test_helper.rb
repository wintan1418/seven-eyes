# Uploaded pictures for My Media tests: a real image from
# test/fixtures/files, or made-up bytes of an image type.
module MediaTestHelper
  def picture_upload(name = "welcome_flyer.png", type: nil)
    path = Rails.root.join("test/fixtures/files", name)
    type ||= name.end_with?(".jpg") ? "image/jpeg" : "image/png"
    Rack::Test::UploadedFile.new(path, type, original_filename: name)
  end

  def bytes_upload(bytes = "fake png", type: "image/png", name: "slide.png")
    Rack::Test::UploadedFile.new(StringIO.new(bytes), type, original_filename: name)
  end

  def library_picture(user, name = "welcome_flyer.png", **attrs)
    result = MediaLibrary.add(user, picture_upload(name), **attrs)
    raise "upload refused: #{result.error}" unless result.ok?
    result.asset
  end
end

ActiveSupport.on_load(:active_support_test_case) { include MediaTestHelper }
