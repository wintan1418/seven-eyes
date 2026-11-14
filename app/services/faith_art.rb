# Bible art for the Glossary of the Faith: public-domain engravings (mostly
# Gustave Doré's 1866 Bible) behind each term's name, on the /faith intro and
# faintly behind the home "Word of the day" card.
#
# config/faith_art.yml holds the pictures (title, artist, year, Commons page,
# licence) and which picture each term gets, keyed by slug. A term that isn't
# listed gets a steady pick from the set (by its slug), so it never changes
# from one visit to the next. The files live in app/assets/images/faith/
# (<key>-1600 / <key>-800, .webp + .jpg), so nothing loads from another host.
#
# Copyright: only pictures that Wikimedia Commons marks public domain (artist
# dead 70+ years, published before 1929). The credits page lists them all.
module FaithArt
  SOURCE = Rails.root.join("config/faith_art.yml")
  WIDTHS = [ 800, 1600 ].freeze

  Image = Data.define(:key, :title, :artist, :year, :commons_url, :licence) do
    def path(width, format = "jpg") = "faith/#{key}-#{width}.#{format}"
    def credit = "#{artist}, #{title} (#{year})"
  end

  DATA = YAML.safe_load_file(SOURCE).freeze

  IMAGES = DATA.fetch("images").to_h do |key, h|
    [ key, Image.new(key:, title: h.fetch("title"), artist: h.fetch("artist"), year: h.fetch("year"),
                     commons_url: h.fetch("commons_url"), licence: h.fetch("licence")) ]
  end.freeze

  TERMS = DATA.fetch("terms").each_with_object({}) do |(key, slugs), map|
    Array(slugs).each { |slug| map[slug] = key }
  end.freeze

  # The picture for a term (or a slug). Unlisted slugs get a steady pick.
  def self.for(term)
    slug = term.respond_to?(:slug) ? term.slug : term.to_s
    IMAGES.fetch(TERMS.fetch(slug) { default_key(slug) })
  end

  # The verse of the day's picture: one that suits the part of the Bible it
  # comes from, the same all day (picked by date among the fitting ones).
  PASSAGE_ART = {
    law: %w[ creation-light moses-tablets ],
    history: %w[ moses-tablets creation-light ],
    wisdom: %w[ creation-light sermon-on-the-mount ascension ],
    prophets: %w[ ascension creation-light crucifixion ],
    gospels: %w[ sermon-on-the-mount prodigal-son crucifixion resurrection ],
    acts: %w[ pentecost ],
    letters: %w[ resurrection pentecost crucifixion sermon-on-the-mount ],
    revelation: %w[ ascension resurrection ]
  }.freeze
  PASSAGE_GROUPS = {
    law: %w[ Gen Exod Lev Num Deut ],
    history: %w[ Josh Judg Ruth 1Sam 2Sam 1Kgs 2Kgs 1Chr 2Chr Ezra Neh Esth ],
    wisdom: %w[ Job Ps Prov Eccl Song ],
    gospels: %w[ Matt Mark Luke John ],
    acts: %w[ Acts ],
    revelation: %w[ Rev ]
  }.flat_map { |group, codes| codes.map { |c| [ c, group ] } }.to_h.freeze
  NT_LETTERS = Set.new(%w[ Rom 1Cor 2Cor Gal Eph Phil Col 1Thess 2Thess 1Tim 2Tim Titus Phlm Heb Jas 1Pet 2Pet 1John 2John 3John Jude ]).freeze

  def self.for_passage(osis, date)
    group = PASSAGE_GROUPS[osis.to_s] || (NT_LETTERS.include?(osis.to_s) ? :letters : :prophets)
    keys = PASSAGE_ART.fetch(group).select { |k| IMAGES.key?(k) }
    keys = IMAGES.keys if keys.empty?
    IMAGES.fetch(keys[date.jd % keys.size])
  end

  # The /faith intro's picture.
  def self.intro = IMAGES.fetch(DATA.fetch("intro"))

  def self.all = IMAGES.values

  def self.default_key(slug)
    keys = IMAGES.keys
    keys[Zlib.crc32(slug.to_s) % keys.size]
  end
end
