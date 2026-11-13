# The built-in hymnal: clearly PUBLIC-DOMAIN hymns the pastor can drop into the
# preach queue without typing the lyrics out each Sunday. The words live in
# config/hymnal.yml (title, author, year, body); this module loads them once.
#
# Copyright caution (same rule as our translations): only public-domain texts
# ship here. Every hymn's text — and, for a translated hymn, its English
# translation — was first published before 1929 by an author who died more than
# 70 years ago, so it is free to project in Nigeria as well as the US and UK.
# Never add hymns still under copyright — e.g. "How Great Thou Art" (Hine's
# translation), "Great Is Thy Faithfulness" (1923, renewed), "In Christ Alone",
# "The Old Rugged Cross" (Bennard d. 1958) or any modern worship song. When in
# doubt, leave it out and let the pastor paste it themselves.
# test/services/hymnal_test.rb checks every entry against BLOCKLIST.
#
# Bodies use the song sheet format (SongSheet): "[Verse 1]" / "[Chorus]" labels,
# blank lines between stanzas, a refrain written once (it repeats after every
# verse when projected).
module Hymnal
  SOURCE = Rails.root.join("config/hymnal.yml")

  # Known copyrighted songs that must never be bundled (lower-case titles).
  BLOCKLIST = [
    "how great thou art", "great is thy faithfulness", "in christ alone", "the old rugged cross",
    "because he lives", "amazing grace (my chains are gone)", "10,000 reasons", "10,000 reasons (bless the lord)",
    "turn your eyes upon jesus", "i'd rather have jesus", "victory in jesus", "he lives",
    "wonderful grace of jesus", "living for jesus", "way maker", "oceans", "oceans (where feet may fail)",
    "shout to the lord", "blessed be your name", "here i am to worship", "majesty", "morning has broken",
    "give thanks", "lord i lift your name on high", "how deep the father's love for us", "mighty to save",
    "cornerstone", "what a beautiful name", "goodness of god", "build my life", "reckless love",
    "how great is our god", "open the eyes of my heart", "the heart of worship", "jesus, lover of my soul (it's all about you)",
    "shine, jesus, shine", "as the deer", "draw me close", "you raise me up",
    "great are you lord", "this is amazing grace", "o praise the name (anástasis)",
    "king of kings", "graves into gardens", "battle belongs", "the blessing", "holy forever", "firm foundation"
  ].freeze

  HYMNS = YAML.safe_load_file(SOURCE).map do |h|
    { title: h.fetch("title"), body: h.fetch("body").strip, author: h["author"], year: h["year"] }.compact.freeze
  end.freeze
end
