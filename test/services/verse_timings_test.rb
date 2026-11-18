# frozen_string_literal: true

require "test_helper"

class VerseTimingsTest < ActiveSupport::TestCase
  def words(spoken)
    t = 0.0
    spoken.split.map { |w| { "word" => w, "start" => (t += 0.4) } }
  end

  test "each verse starts where its opening words are spoken" do
    verses = [ [ 1, "In the beginning was the Word," ], [ 2, "The same was in the beginning with God." ], [ 3, "All things were made by him;" ] ]
    heard = words("John chapter one In the beginning was the Word The same was in the beginning with God All things were made by him")
    t = VerseTimings.align(verses, heard)
    assert_equal %w[1 2 3], t.keys
    assert_in_delta heard[3]["start"], t["1"], 0.01   # "In"
    assert_in_delta heard[9]["start"], t["2"], 0.01   # "The same"
    assert_in_delta heard[17]["start"], t["3"], 0.01  # "All things"
  end

  test "a misheard or missing verse is placed between its neighbours, in order" do
    verses = [ [ 1, "And Jesus wept." ], [ 2, "Then said the Jews, Behold how he loved him!" ], [ 3, "And some of them said, Could not this man" ] ]
    heard = words("And Jesus wept mumble mumble mumble mumble mumble mumble And some of them said Could not this man")
    t = VerseTimings.align(verses, heard)
    assert t["1"] < t["2"] && t["2"] < t["3"], "times stay in verse order: #{t.inspect}"
  end
end
