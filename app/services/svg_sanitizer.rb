require "nokogiri"
require "set"
require "json"

# Strict allow-list sanitizer for inline SVG returned by the AI (the Rabbi's
# diagrams). The model's output is rendered raw into the page, so we parse it,
# drop every element and attribute not on the allow-list (scripts, event
# handlers, external references, <image>, <foreignObject>, <style>), cap its
# size, and re-serialise. Returns an html_safe SVG String, or nil when there is
# no usable <svg> — callers simply skip the figure.
class SvgSanitizer
  MAX_BYTES = 60_000

  # Drawing primitives + gradient/marker scaffolding. Compared case-insensitively;
  # the HTML5 parser corrects the casing of known SVG names (viewBox, linearGradient)
  # when the markup is injected, so we keep the check simple.
  ELEMENTS = %w[
    svg g defs title desc path rect circle ellipse line polyline polygon
    text tspan lineargradient radialgradient stop marker symbol
  ].to_set

  # Presentation + geometry attributes only. Deliberately excludes href/xlink:href
  # (external refs), style (url()/expression()), and anything starting with "on".
  ATTRS = %w[
    id class d fill fill-opacity fill-rule stroke stroke-width stroke-linecap
    stroke-linejoin stroke-dasharray stroke-opacity opacity transform
    x y x1 y1 x2 y2 cx cy r rx ry width height points offset
    stop-color stop-opacity gradientunits gradienttransform spreadmethod
    font-family font-size font-weight font-style text-anchor letter-spacing
    dominant-baseline text-decoration dx dy markerwidth markerheight
    orient refx refy viewbox preserveaspectratio
  ].to_set

  # Block javascript:, CSS expression(), data: payloads, and EXTERNAL url(...)
  # references — but allow url(#id), the safe in-document reference a gradient or
  # marker fill needs (fill='url(#gold)').
  UNSAFE_VALUE = /javascript:|expression\(|data:(?!image\/)|url\(\s*(?!#)/i

  def self.call(raw) = new(raw).call

  # Pull an <svg> out of an AI response that may be raw markup OR a JSON wrapper
  # like {"svg":"<svg…>"} (optionally code-fenced), then sanitise it. Returns an
  # html_safe SVG String, or nil when there is nothing drawable.
  def self.from_ai(content)
    raw = content.to_s.strip
    return nil if raw.empty?

    markup =
      if raw.start_with?("{", "```")
        cleaned = raw.sub(/\A```(?:json)?\s*/, "").sub(/```\z/, "")
        (JSON.parse(cleaned)["svg"].to_s rescue raw)
      else
        raw
      end
    return nil unless markup.match?(/<svg/i)
    call(markup)
  end

  def initialize(raw)
    @raw = raw.to_s
  end

  def call
    return nil if @raw.strip.empty? || @raw.bytesize > MAX_BYTES

    fragment = Nokogiri::XML.fragment(@raw)
    svg = fragment.children.find { |n| n.element? && n.name.casecmp?("svg") }
    return nil unless svg

    scrub(svg)
    out = svg.to_xml
    return nil if out.bytesize > MAX_BYTES
    out.html_safe
  rescue => e
    Rails.logger.warn("[SvgSanitizer] #{e.class}: #{e.message}")
    nil
  end

  private

  # Depth-first: remove disallowed elements wholesale (and their subtrees),
  # then strip disallowed attributes from what remains.
  def scrub(node)
    node.children.to_a.each do |child|
      if child.comment? || child.cdata? || child.processing_instruction?
        child.remove
      elsif child.element?
        next child.remove unless ELEMENTS.include?(child.name.downcase)
        scrub(child)
      end
    end
    scrub_attrs(node)
  end

  def scrub_attrs(el)
    el.attribute_nodes.each do |attr|
      key = attr.name.downcase
      ok = ATTRS.include?(key) && !key.start_with?("on") && attr.value !~ UNSAFE_VALUE
      ok ? normalize(el, attr) : el.remove_attribute(attr.name)
    end
  end

  # Restore the camelCase the SVG spec expects for the two attrs we allow that
  # need it (browsers correct these anyway, but it keeps the markup clean).
  def normalize(el, attr)
    canonical = { "viewbox" => "viewBox", "preserveaspectratio" => "preserveAspectRatio" }[attr.name.downcase]
    return unless canonical && canonical != attr.name
    value = attr.value
    el.remove_attribute(attr.name)
    el[canonical] = value
  end
end
