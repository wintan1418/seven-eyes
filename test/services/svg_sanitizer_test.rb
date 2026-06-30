require "test_helper"

class SvgSanitizerTest < ActiveSupport::TestCase
  test "keeps safe drawing primitives and the viewBox" do
    svg = "<svg viewBox='0 0 100 60'><rect x='2' y='2' width='40' height='20' " \
          "fill='none' stroke='#3a2a18'/><text x='4' y='40'>1.5 cubits</text></svg>"
    out = SvgSanitizer.call(svg)
    assert out.present?
    assert out.html_safe?
    assert_includes out, "<rect"
    assert_includes out, "1.5 cubits"
    assert_includes out, "viewBox=\"0 0 100 60\""
  end

  test "strips <script> and event handlers" do
    svg = "<svg viewBox='0 0 10 10' onload='steal()'>" \
          "<script>alert(1)</script><rect x='0' y='0' width='5' height='5' onclick='x()'/></svg>"
    out = SvgSanitizer.call(svg)
    assert_not_includes out, "script"
    assert_not_includes out, "onload"
    assert_not_includes out, "onclick"
    assert_includes out, "<rect"
  end

  test "drops <foreignObject>, <image>, and href/external references" do
    svg = "<svg viewBox='0 0 10 10'><foreignObject><div>x</div></foreignObject>" \
          "<image href='http://evil/x.png'/><a href='javascript:x()'><rect width='1' height='1'/></a></svg>"
    out = SvgSanitizer.call(svg)
    assert_not_includes out.downcase, "foreignobject"
    assert_not_includes out.downcase, "<image"
    assert_not_includes out.downcase, "javascript:"
    assert_not_includes out, "href"
  end

  test "rejects an EXTERNAL url() payload but keeps an internal url(#id) reference" do
    external = "<svg viewBox='0 0 10 10'><rect width='5' height='5' fill='url(http://evil)'/></svg>"
    assert_not_includes SvgSanitizer.call(external), "url(http"

    internal = "<svg viewBox='0 0 10 10'><defs><linearGradient id='g'>" \
               "<stop offset='0' stop-color='#a3812e'/></linearGradient></defs>" \
               "<rect width='5' height='5' fill='url(#g)'/></svg>"
    out = SvgSanitizer.call(internal)
    assert_includes out, "url(#g)" # gradient fill survives
    assert_includes out.downcase, "lineargradient"
  end

  test "returns nil for blank, oversize, or svg-less input" do
    assert_nil SvgSanitizer.call("")
    assert_nil SvgSanitizer.call(nil)
    assert_nil SvgSanitizer.call("<div>not an svg</div>")
    assert_nil SvgSanitizer.call("<svg>#{'x' * 70_000}</svg>")
  end

  test "returns nil rather than raising on malformed markup" do
    assert_nothing_raised { SvgSanitizer.call("<svg viewBox='0 0 1 1'><rect") }
  end
end
