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

  # The /faith intro's picture.
  def self.intro = IMAGES.fetch(DATA.fetch("intro"))

  def self.all = IMAGES.values

  def self.default_key(slug)
    keys = IMAGES.keys
    keys[Zlib.crc32(slug.to_s) % keys.size]
  end
end
