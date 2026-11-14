module FaithTermsHelper
  # A FaithArt picture as <picture>: WebP with a JPEG fallback, 800px and
  # 1600px wide, so phones fetch the small one. Decorative (alt="") — the
  # caption beside it credits the artist.
  # phone_small: phones (≤767px) always get the 800px file, whatever their
  # pixel density — the 1600px one is for laptops (home page, slow data).
  def faith_art_picture(image, sizes:, img_class: nil, loading: "lazy", phone_small: false)
    srcset = ->(format) { FaithArt::WIDTHS.map { |w| "#{image_path(image.path(w, format))} #{w}w" }.join(", ") }
    tag.picture(class: "ft-art", data: { art: image.key }) do
      phone = if phone_small
        tag.source(type: "image/webp", media: "(max-width: 767px)", srcset: image_path(image.path(800, "webp"))) +
          tag.source(media: "(max-width: 767px)", srcset: image_path(image.path(800)))
      end
      safe_join([ phone,
        tag.source(type: "image/webp", srcset: srcset.("webp"), sizes:),
        image_tag(image.path(800), srcset: srcset.("jpg"), sizes:, alt: "", class: img_class,
                  loading:, decoding: "async", fetchpriority: (loading == "eager" ? "high" : nil)) ].compact)
    end
  end

  # Text the pastor writes in paragraphs (blank line between them) as <p>s;
  # a single line break inside a paragraph stays a <br>.
  def faith_paragraphs(text, css_class = nil)
    simple_format(text.to_s.strip, class: css_class)
  end
end
