require "json"

# "Rewrite with AI" on the glossary review desk (/admin/faith/:slug/edit).
#
# The pastor explains a term in his own words — typed or dictated on his phone,
# typos and run-on sentences included — and this turns it into the term's
# fields: short_definition, new_believer, explanation and key_references. It
# keeps HIS theology: the prompt forbids softening, adding to or "correcting"
# his doctrine, and every word of Scripture must be the KJV.
#
# Nothing is saved here. The caller shows the suggestion beside the current
# text; the reviewer copies what he wants into the form and presses Save.
#
# Scripture is checked against our own KJV, never trusted from the model:
#   * key_references that ReferenceParser can't read, or that aren't in our
#     KJV (KeyPassages), are dropped and listed in `dropped_references`;
#   * every quotation in the explanation followed by "(Book c:v)" is compared
#     with that verse's KJV words — `quote_checks` says which ones match.
#
#   FaithTermRewriter.call(term:, words: "righteousness is …", chips: %w[shorter])
#   => #<Result ok=true suggestion={short_definition: …, key_references: [...]}, …>
class FaithTermRewriter
  CHIPS = {
    "shorter" => "Shorter: make every field noticeably shorter than your last draft (explanation 2 short paragraphs).",
    "simpler" => "Simpler: plain everyday English a new believer or a teenager understands; short sentences, no jargon.",
    "more_scripture" => "More scripture: weave in more KJV quotations that support HIS points, and give 6 key verses.",
    "keep_wording" => "Keep my wording: keep his own phrases and expressions wherever they are clear; fix only spelling, grammar and order."
  }.freeze
  CHIP_LABELS = { "shorter" => "Shorter", "simpler" => "Simpler", "more_scripture" => "More scripture", "keep_wording" => "Keep my wording" }.freeze

  FIELDS = %i[ short_definition new_believer explanation key_references ].freeze
  WORDS_LIMIT = 6000
  REQUEST_LIMIT = 500
  HISTORY_TURNS = 4
  MAX_TOKENS = 2000
  TEXT_LIMITS = { short_definition: 600, new_believer: 400, explanation: 5000 }.freeze

  SYSTEM_PROMPT = <<~PROMPT.freeze
    You are the writing assistant of a Bible-believing pastor. He writes the
    "Glossary of the Faith" in a Bible app. He explains a term in his own
    conversational words (often dictated on a phone, with typos and run-on
    sentences) and you turn HIS teaching into clear, warm, well-ordered text.

    THE TEACHING IS HIS — you are only the scribe:
    - Keep his doctrine, his emphasis and his conclusions exactly. Do not soften,
      qualify, balance, add to or "correct" what he teaches.
    - Do not bring in other traditions' or theologians' views, and no "some
      believe…" framing. If he says it, say it plainly; if he did not say it,
      do not add it.
    - Keep his strong lines (e.g. "not a title but a function") — they are the
      point. Tidy the grammar, order and flow only.

    SCRIPTURE:
    - Quote ONLY the King James Version (KJV), word for word. Never paraphrase a
      verse inside quotation marks and never quote any other translation.
    - Never invent or guess a verse. Use only references you are certain of. If
      he quotes or alludes to a verse, find its real reference.
    - Every quotation in the explanation is written as "exact KJV words"
      followed immediately by the reference in brackets, e.g.
      "He that doeth righteousness is righteous" (1 John 3:7).
    - Key verses are plain references like "Romans 3:22" or "1 John 3:7-10",
      verses that support HIS points.

    WRITE:
    - short_definition: 1–2 plain sentences (the home-screen card).
    - new_believer: ONE warm, plain sentence for someone who just believed.
    - explanation: 2–4 short paragraphs separated by a blank line ("\\n\\n"),
      weaving in KJV quotations that support his points. No headings, lists,
      markdown or HTML.
    - key_references: 4–6 references.

    When there are change requests, revise YOUR LAST DRAFT accordingly and keep
    everything else as it was.

    Respond ONLY as JSON:
    {"short_definition":"…","new_believer":"…","explanation":"…","key_references":["…"]}
  PROMPT

  Result = Struct.new(:ok, :suggestion, :dropped_references, :quote_checks, :error, :provider, keyword_init: true) do
    def ok? = ok

    def unchecked_quotes = Array(quote_checks).reject { |check| check[:ok] }
  end

  def self.call(...) = new(...).call

  # term:     the FaithTerm (its name; current text is read from `current`)
  # words:    his teaching, in his own words
  # chips:    any of CHIPS.keys
  # request:  a follow-up ("make it shorter", "add Romans 8:2")
  # current:  the edit form's fields as they are now (unsaved edits included)
  # history:  { "requests" => [...], "last" => {suggestion} } from earlier rounds
  def initialize(term:, words: "", chips: [], request: "", current: {}, history: {})
    @term = term
    @words = words.to_s.strip[0, WORDS_LIMIT]
    @chips = Array(chips).map(&:to_s) & CHIPS.keys
    @request = request.to_s.squish[0, REQUEST_LIMIT]
    @current = self.class.normalize_fields(current)
    @history = self.class.clean_history(history)
  end

  def call
    return Result.new(ok: false, error: :blank) if @words.blank? && @request.blank?

    res = chat_completion
    return Result.new(ok: false, error: res.error == :no_key ? :no_key : (res.error == :budget ? :budget : :api)) unless res.ok?

    data = parse(res.content)
    return Result.new(ok: false, error: :api) unless data

    suggestion, dropped = clean(data)
    return Result.new(ok: false, error: :api) if suggestion.values_at(:short_definition, :explanation).all?(&:blank?)

    Result.new(ok: true, suggestion:, dropped_references: dropped,
               quote_checks: check_quotes(suggestion[:explanation]), provider: res.provider)
  rescue => e
    Rails.logger.error("[FaithTermRewriter] #{e.class}: #{e.message}")
    Result.new(ok: false, error: :api)
  end

  # The conversation the form posts back: the last few requests and the last
  # suggestion. Anything else (or anything too long) is thrown away.
  def self.clean_history(raw)
    raw = JSON.parse(raw) if raw.is_a?(String) && raw.present?
    raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
    return {} unless raw.is_a?(Hash)

    requests = Array(raw["requests"] || raw[:requests]).map { |r| r.to_s.squish[0, REQUEST_LIMIT] }.compact_blank.last(HISTORY_TURNS)
    last = raw["last"] || raw[:last]
    last = last.is_a?(Hash) ? normalize_fields(last) : {}
    { "requests" => requests, "last" => last }
  rescue JSON::ParserError
    {}
  end

  # A field hash from a form or a past suggestion, trimmed to sane sizes.
  def self.normalize_fields(raw)
    raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
    raw = (raw || {}).to_h.transform_keys(&:to_sym)
    refs = raw[:key_references]
    refs = refs.to_s.split(/[\n;]/) unless refs.is_a?(Array)
    {
      short_definition: raw[:short_definition].to_s.strip[0, TEXT_LIMITS[:short_definition] * 2],
      new_believer: raw[:new_believer].to_s.strip[0, TEXT_LIMITS[:new_believer] * 2],
      explanation: raw[:explanation].to_s.strip[0, TEXT_LIMITS[:explanation] * 2],
      key_references: refs.map { |r| r.to_s.squish[0, 60] }.compact_blank.first(10)
    }
  end

  # The history to post back after this round.
  def next_history(suggestion)
    asked = @request.presence || ("Rewrite from my words" + (@chips.any? ? " (#{@chips.map { CHIP_LABELS[_1] }.join(', ')})" : ""))
    { "requests" => (Array(@history["requests"]) + [ asked ]).last(HISTORY_TURNS), "last" => suggestion.to_h.transform_keys(&:to_s) }
  end

  def user_prompt
    parts = []
    parts << "TERM: #{@term&.name}"
    parts << "CURRENT TEXT ON THE PAGE (may be empty or an older draft):\n#{format_fields(@current)}"
    parts << "HIS TEACHING, IN HIS OWN WORDS:\n#{@words.presence || '(not repeated this time — see your last draft)'}"
    if @history["last"].present?
      parts << "YOUR LAST DRAFT:\n#{format_fields(@history['last'])}"
    end
    if Array(@history["requests"]).any?
      parts << "EARLIER REQUESTS (oldest first):\n" + @history["requests"].map { |r| "- #{r}" }.join("\n")
    end
    parts << "CHANGE REQUEST NOW: #{@request}" if @request.present?
    if @chips.any?
      parts << "STYLE CHOICES:\n" + @chips.map { |c| "- #{CHIPS[c]}" }.join("\n")
    end
    parts.join("\n\n")
  end

  private

  # Network seam — overridden in tests.
  def chat_completion
    AiChat.call(system: SYSTEM_PROMPT, user: user_prompt, json: true, temperature: 0.3, max_tokens: MAX_TOKENS)
  end

  def format_fields(fields)
    [
      "short_definition: #{fields[:short_definition].presence || '(empty)'}",
      "new_believer: #{fields[:new_believer].presence || '(empty)'}",
      "explanation: #{fields[:explanation].presence || '(empty)'}",
      "key_references: #{Array(fields[:key_references]).join('; ').presence || '(none)'}"
    ].join("\n")
  end

  def parse(content)
    cleaned = content.to_s.strip.sub(/\A```(?:json)?\s*/, "").sub(/```\z/, "")
    data = JSON.parse(cleaned)
    data.is_a?(Hash) ? data : nil
  rescue JSON::ParserError
    nil
  end

  # Plain text only (PlainText), paragraph breaks kept, references checked.
  def clean(data)
    explanation = data["explanation"]
    explanation = explanation.join("\n\n") if explanation.is_a?(Array)
    paragraphs = explanation.to_s.gsub("\r\n", "\n").split(/\n\s*\n/).map { |p| PlainText.call(p).to_s.squish }.compact_blank

    kept, dropped = check_references(Array(data["key_references"]))
    suggestion = {
      short_definition: PlainText.call(data["short_definition"].to_s.squish, limit: TEXT_LIMITS[:short_definition]).to_s,
      new_believer: PlainText.call(data["new_believer"].to_s.squish, limit: TEXT_LIMITS[:new_believer]).to_s,
      explanation: paragraphs.join("\n\n").truncate(TEXT_LIMITS[:explanation]),
      key_references: kept
    }
    [ suggestion, dropped ]
  end

  # References that parse AND are in our KJV, as the parser labels them
  # ("Rom 3:22" → "Romans 3:22"), at most FaithTerm::MAX_REFERENCES.
  def check_references(refs)
    kept = []
    dropped = []
    refs.map { |r| PlainText.call(r.to_s.squish).to_s }.compact_blank.each do |ref|
      passage = kjv && KeyPassages.resolve(ref, kjv)
      if passage then kept << passage.label
      else dropped << ref
      end
    end
    [ kept.uniq.first(FaithTerm::MAX_REFERENCES), dropped.uniq ]
  end

  QUOTE = /[“"]([^“”"]{6,}?)[”"](?:\s*\(([^()]{3,40})\))?/

  # Each "quotation" (Reference) in the explanation, compared with that verse's
  # KJV words (case, punctuation and an ellipsis are forgiven). A quotation
  # with no reference after it can't be checked, so it is flagged too.
  def check_quotes(explanation)
    explanation.to_s.scan(QUOTE).map do |quote, ref|
      passage = ref.present? && kjv && KeyPassages.resolve(ref, kjv)
      { quote: quote.strip, reference: ref&.strip, ok: passage.present? && quote_in?(quote, passage.text) }
    end
  end

  def quote_in?(quote, verse_text)
    haystack = squash(verse_text)
    pieces = quote.split(/\.{3}|…/).map { |piece| squash(piece) }.compact_blank
    pieces.any? && pieces.all? { |piece| haystack.include?(piece) }
  end

  def squash(text) = text.to_s.downcase.gsub(/[^a-z0-9\s]/, " ").squish

  def kjv
    return @kjv if defined?(@kjv)
    @kjv = KeyPassages.default_translation
  end
end
