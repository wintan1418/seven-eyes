# Scene pictures behind the reader: Gustave Doré's Bible engravings (1866,
# public domain), each tied to the passage it shows. config/scripture_scenes.yml
# is the list; the files are public/scenes/<key>.webp (served as they are, so
# the device can draw them offline from the service worker's cache).
#
# The reader picks the picture on the device (lib/scripture_scenes.js) from a
# bundled copy of the list, app/javascript/lib/scripture_scenes.json — after
# editing the YAML run `bin/rails scenes:json` (a test checks they match).
module ScriptureScenes
  SOURCE = Rails.root.join("config/scripture_scenes.yml")
  BUNDLE = Rails.root.join("app/javascript/lib/scripture_scenes.json")
  DIR = Rails.root.join("public/scenes")

  Scene = Data.define(:key, :title, :plate, :ref, :osis, :chapter, :verse, :commons_url, :licence) do
    def path = "/scenes/#{key}.webp"
  end

  DATA = YAML.safe_load_file(SOURCE).freeze

  SCENES = DATA.fetch("scenes").map do |h|
    Scene.new(key: h.fetch("key"), title: h.fetch("title"), plate: h["plate"], ref: h.fetch("ref"),
              osis: h.fetch("osis"), chapter: h.fetch("chapter"), verse: h["verse"],
              commons_url: h.fetch("commons_url"), licence: h.fetch("licence"))
  end.freeze

  def self.all = SCENES

  # What the device needs: no credits, just enough to pick and draw.
  def self.bundle
    SCENES.map { |s| { key: s.key, title: s.title, ref: s.ref, osis: s.osis, chapter: s.chapter, verse: s.verse } }
  end

  def self.bundle_json = JSON.pretty_generate(bundle) + "\n"

  def self.write_bundle! = File.write(BUNDLE, bundle_json)
end
