require "test_helper"

class SongCollectionTest < ActiveSupport::TestCase
  test "save_for! upserts by the device's id and tidies the titles" do
    user = users(:one)
    SongCollection.save_for!(user, "col-1", name: "Choir", titles: [ "A", " a ", "", "B" ])
    SongCollection.save_for!(user, "col-1", name: "Choir songs", titles: [ "B" ])
    assert_equal [ [ "Choir songs", [ "B" ] ] ], user.song_collections.pluck(:name, :titles)
  end

  test "a bad device id or a missing name is refused" do
    assert_not SongCollection.new(user: users(:one), client_id: "../x", name: "A").valid?
    assert_not SongCollection.new(user: users(:one), client_id: "col-1", name: " ").valid?
  end
end
