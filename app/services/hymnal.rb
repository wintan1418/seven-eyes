# A small starter set of clearly PUBLIC-DOMAIN hymns the pastor can drop into
# the preach queue without typing the lyrics out each Sunday.
#
# Copyright caution (same rule as our translations): only public-domain texts
# ship here. Every hymn below has a pre-1900 text. Never add hymns still under
# copyright — e.g. "How Great Thou Art" or "Great Is Thy Faithfulness" (1923,
# renewed). When in doubt, leave it out and let the pastor paste it themselves.
#
# Blank lines separate stanzas, matching how SetlistItem splits a song body into
# stanza slides.
module Hymnal
  HYMNS = [
    {
      title: "Amazing Grace",
      body: <<~LYRICS.strip
        Amazing grace! how sweet the sound,
        That saved a wretch like me!
        I once was lost, but now am found,
        Was blind, but now I see.

        'Twas grace that taught my heart to fear,
        And grace my fears relieved;
        How precious did that grace appear
        The hour I first believed!

        Through many dangers, toils and snares,
        I have already come;
        'Tis grace hath brought me safe thus far,
        And grace will lead me home.
      LYRICS
    },
    {
      title: "Holy, Holy, Holy",
      body: <<~LYRICS.strip
        Holy, holy, holy! Lord God Almighty!
        Early in the morning our song shall rise to thee;
        Holy, holy, holy! merciful and mighty,
        God in three Persons, blessed Trinity!

        Holy, holy, holy! all the saints adore thee,
        Casting down their golden crowns around the glassy sea;
        Cherubim and seraphim falling down before thee,
        Which wert, and art, and evermore shalt be.
      LYRICS
    },
    {
      title: "It Is Well with My Soul",
      body: <<~LYRICS.strip
        When peace, like a river, attendeth my way,
        When sorrows like sea billows roll;
        Whatever my lot, thou hast taught me to say,
        It is well, it is well with my soul.

        It is well with my soul,
        It is well, it is well with my soul.

        Though Satan should buffet, though trials should come,
        Let this blest assurance control,
        That Christ has regarded my helpless estate,
        And hath shed his own blood for my soul.
      LYRICS
    },
    {
      title: "Come, Thou Fount of Every Blessing",
      body: <<~LYRICS.strip
        Come, thou Fount of every blessing,
        Tune my heart to sing thy grace;
        Streams of mercy, never ceasing,
        Call for songs of loudest praise.

        Here I raise mine Ebenezer;
        Hither by thy help I'm come;
        And I hope, by thy good pleasure,
        Safely to arrive at home.
      LYRICS
    },
    {
      title: "Crown Him with Many Crowns",
      body: <<~LYRICS.strip
        Crown him with many crowns,
        The Lamb upon his throne;
        Hark! how the heavenly anthem drowns
        All music but its own:
        Awake, my soul, and sing
        Of him who died for thee,
        And hail him as thy matchless King
        Through all eternity.
      LYRICS
    },
    {
      title: "Rock of Ages",
      body: <<~LYRICS.strip
        Rock of Ages, cleft for me,
        Let me hide myself in thee;
        Let the water and the blood,
        From thy wounded side which flowed,
        Be of sin the double cure,
        Save from wrath and make me pure.
      LYRICS
    },
    {
      title: "Great Is the Lord",
      body: <<~LYRICS.strip
        O worship the King, all glorious above,
        O gratefully sing his power and his love;
        Our Shield and Defender, the Ancient of Days,
        Pavilioned in splendour, and girded with praise.
      LYRICS
    },
    {
      title: "Be Thou My Vision",
      body: <<~LYRICS.strip
        Be thou my vision, O Lord of my heart;
        Naught be all else to me, save that thou art;
        Thou my best thought, by day or by night,
        Waking or sleeping, thy presence my light.

        Riches I heed not, nor man's empty praise,
        Thou mine inheritance, now and always;
        Thou and thou only, first in my heart,
        High King of heaven, my treasure thou art.
      LYRICS
    }
  ].freeze
end
