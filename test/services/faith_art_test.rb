require "test_helper"

class FaithArtTest < ActiveSupport::TestCase
  test "every picture is credited and bundled at both sizes, as WebP and JPEG, under 200 KB" do
    assert_operator FaithArt.all.size, :>=, 6
    FaithArt.all.each do |art|
      assert art.title.present? && art.artist.present?, art.key
      assert_operator art.year.to_s[/\d{4}/].to_i, :<, 1929, "#{art.key} must be public domain"
      assert_match %r{\Ahttps://commons\.wikimedia\.org/wiki/File:}, art.commons_url
      assert_match(/public domain/i, art.licence)
      FaithArt::WIDTHS.each do |width|
        %w[ jpg webp ].each do |format|
          file = Rails.root.join("app/assets/images", art.path(width, format))
          assert file.exist?, "missing #{file}"
          assert_operator file.size, :<, 200.kilobytes, "#{file} is too big"
        end
      end
    end
  end

  test "terms map to known pictures, and an unlisted term gets the same pick every time" do
    FaithArt::TERMS.each_value { |key| assert FaithArt::IMAGES.key?(key), key }
    assert_equal "crucifixion", FaithArt.for("salvation").key
    assert_equal FaithArt.for("brand-new-term"), FaithArt.for(FaithTerm.new(slug: "brand-new-term"))
    assert FaithArt::IMAGES.key?(FaithArt.intro.key)
  end

  test "every seeded term has its own picture" do
    slugs = YAML.safe_load_file(Rails.root.join("config/faith_terms.yml")).map { |t| t["slug"] }
    assert_empty slugs - FaithArt::TERMS.keys
  end

  test "neighbouring slides in the glossary's order never share a picture, and every picture is used" do
    slugs = YAML.safe_load_file(Rails.root.join("config/faith_terms.yml")).map { |t| t["slug"] }
    keys = slugs.map { |slug| FaithArt.for(slug).key }
    keys.each_with_index do |key, i|
      neighbour = keys[(i + 1) % keys.size]
      assert_not_equal key, neighbour, "#{slugs[i]} and #{slugs[(i + 1) % slugs.size]} share #{key}"
    end
    assert_empty FaithArt::IMAGES.keys - keys, "every picture shows on some term"
    assert_operator keys.tally.values.max, :<=, 6, "no picture dominates the slider"
  end

  test "the verse of the day gets a fitting picture, the same all day" do
    date = Date.new(2026, 11, 14)
    assert_equal "pentecost", FaithArt.for_passage("Acts", date).key
    assert_includes FaithArt::PASSAGE_ART[:gospels], FaithArt.for_passage("John", date).key
    assert_includes FaithArt::PASSAGE_ART[:letters], FaithArt.for_passage("Rom", date).key
    assert_includes FaithArt::PASSAGE_ART[:prophets], FaithArt.for_passage("Isa", date).key
    assert_equal FaithArt.for_passage("Ps", date), FaithArt.for_passage("Ps", date)
    keys = (0..3).map { |i| FaithArt.for_passage("Matt", date + i).key }.uniq
    assert_operator keys.size, :>, 1, "the gospels' pictures take turns by date"
    assert FaithArt.for_passage("Nope", date) # unknown books still get a picture
  end
end
