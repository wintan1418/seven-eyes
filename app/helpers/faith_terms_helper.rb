module FaithTermsHelper
  # A FaithArt picture as <picture>: WebP with a JPEG fallback, 800px and
  # 1600px wide, so phones fetch the small one. Decorative (alt="") — the
  # caption beside it credits the artist.
  def faith_art_picture(image, sizes:, img_class: nil, loading: "lazy")
    srcset = ->(format) { FaithArt::WIDTHS.map { |w| "#{image_path(image.path(w, format))} #{w}w" }.join(", ") }
    tag.picture(class: "ft-art", data: { art: image.key }) do
      tag.source(type: "image/webp", srcset: srcset.("webp"), sizes:) +
        image_tag(image.path(800), srcset: srcset.("jpg"), sizes:, alt: "", class: img_class,
                  loading:, decoding: "async", fetchpriority: (loading == "eager" ? "high" : nil))
    end
  end

  # Text the pastor writes in paragraphs (blank line between them) as <p>s;
  # a single line break inside a paragraph stays a <br>.
  def faith_paragraphs(text, css_class = nil)
    simple_format(text.to_s.strip, class: css_class)
  end
end
