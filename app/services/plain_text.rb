require "cgi"

# Reduce untrusted model output to plain text before it reaches a page or a JSON
# payload. A prompt-injected passage or note could otherwise talk the model into
# emitting <a href="https://evil"> or <img onerror>; even after sanitising, a
# rogue link in "the Rabbi's" voice is a phishing vector. So: no markup at all.
#
#   PlainText.call("<b>Hi</b> <a href='x'>there</a> &amp; you") # => "Hi there & you"
#
# Tags are stripped (repeatedly, so entity-encoded tags can't reassemble), any
# stray angle brackets are dropped, and entities are decoded so the result is
# literal text — views must still escape it (ERB does, simple_format(h(...))).
module PlainText
  MAX_PASSES = 3

  def self.call(value, limit: nil)
    return nil if value.nil?
    text = value.to_s
    MAX_PASSES.times do
      stripped = CGI.unescapeHTML(Rails::HTML5::FullSanitizer.new.sanitize(text).to_s)
      break if stripped == text
      text = stripped
    end
    text = text.delete("<>").strip
    limit ? text.truncate(limit) : text
  end
end
