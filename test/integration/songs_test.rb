require "test_helper"

# "Save to my songs": the account's own song bank.
class SongsTest < ActionDispatch::IntegrationTest
  test "a signed-in operator saves a song (any slide, even pasted scripture) and saving again by title updates it" do
    sign_in_as users(:one)
    body = "Matthew 28:20 AMP\nteaching them to observe everything\n\nMark 1:1 BSB\nThe beginning of the gospel"
    assert_difference -> { users(:one).songs.count }, 1 do
      post songs_path, params: { song: { title: "jajaj", body: body } }, as: :json
    end
    assert_response :created
    assert_equal "jajaj", response.parsed_body["title"]
    assert response.parsed_body["saved"]

    assert_no_difference -> { users(:one).songs.count } do # a replayed / repeated save is one song
      post songs_path, params: { song: { title: "JAJAJ ", body: "new words", arrangement: "V1" } }, as: :json
    end
    assert_equal "new words", users(:one).songs.sole.body
    assert_equal [ "new words" ], SongSheet.new(users(:one).songs.sole.body).slides.map(&:text)

    library = users(:one).studies.create!(name: "S", pane_count: 1)
    get library_study_setlist_items_path(library), as: :json
    assert_equal "new words", response.parsed_body["songs"].find { |s| s["title"].casecmp?("jajaj") }["body"]

    delete song_path("by-title", title: "jajaj"), as: :json
    assert_response :no_content
    assert_equal 0, users(:one).songs.count
  end

  test "guests can't save songs, and a title is required" do
    post songs_path, params: { song: { title: "x", body: "y" } }, as: :json
    assert_response :unauthorized

    sign_in_as users(:one)
    post songs_path, params: { song: { title: " ", body: "y" } }, as: :json
    assert_response :unprocessable_entity
  end

  test "one account can't delete another's song" do
    song = users(:two).songs.create!(title: "Theirs", body: "x")
    sign_in_as users(:one)
    delete song_path(song), as: :json
    assert_response :no_content
    assert Song.exists?(song.id)
  end
end
