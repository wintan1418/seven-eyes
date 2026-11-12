require "net/http"
require "json"

# Finds the current model names from each provider, so a retired model can't
# silently break a feature. Nov 2026: OpenAI removed gpt-image-1 and Google
# removed gemini-2.0-flash, which stopped illustrations working.
#
# Each provider's model list is fetched at most once a day per process (and kept
# in Rails.cache when it works), then the best match is picked:
#   * OpenAI images: the newest full "gpt-image-N" model (mini only if nothing else), then dall-e-3.
#   * Gemini text:   "gemini-flash-latest" if offered, else the newest stable "gemini-N-flash".
# Picking is pure (see .pick_openai_image / .pick_gemini_flash) so it's easy to test.
class AiModels
  TTL = 1.day
  SNAPSHOT = /-\d{4}-\d{2}-\d{2}\z/ # dated copies like gpt-image-2-2026-09-01; prefer the plain name
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 10

  class << self
    def openai_image(api_key, exclude: nil)
      pick_openai_image(model_ids(:openai, api_key) - Array(exclude))
    end

    def gemini_flash(api_key, exclude: nil)
      pick_gemini_flash(model_ids(:gemini, api_key) - Array(exclude))
    end

    # Forget the cached list (after a provider says a model doesn't exist).
    def refresh!(provider)
      @memo&.delete(provider)
      Rails.cache.delete(cache_key(provider))
    rescue StandardError
      nil
    end

    def pick_openai_image(ids)
      images = ids.grep(/\Agpt-image-\d/).reject { |id| id.match?(SNAPSHOT) }
      full = images.reject { |id| id.include?("mini") }
      best = (full.presence || images).max_by { |id| [ version(id, "gpt-image"), -id.length ] }
      best || ids.find { |id| id == "dall-e-3" }
    end

    def pick_gemini_flash(ids)
      names = ids.map { |id| id.delete_prefix("models/") }
      # Newest numbered model first: Google keeps listing "gemini-flash-latest"
      # but refuses it (404 "no longer available to new users") on new keys.
      stable = names.grep(/\Agemini-\d+(\.\d+)?-flash\z/)
      stable.max_by { |id| version(id, "gemini") } || ("gemini-flash-latest" if names.include?("gemini-flash-latest"))
    end

    private

    # "gpt-image-1.5" -> [1, 5]; "gemini-3.8-flash" -> [3, 8]
    def version(id, family)
      m = id.match(/\A#{family}-(\d+)(?:\.(\d+))?/)
      m ? [ m[1].to_i, m[2].to_i ] : [ 0, 0 ]
    end

    def cache_key(provider) = "ai_models/#{provider}/v1"

    def model_ids(provider, api_key)
      return [] if api_key.blank?

      @memo ||= {}
      hit = @memo[provider]
      return hit[:ids] if hit && hit[:at] > TTL.ago

      ids = (Rails.cache.read(cache_key(provider)) rescue nil) || fetch(provider, api_key)
      if ids.present?
        @memo[provider] = { ids: ids, at: Time.current }
        Rails.cache.write(cache_key(provider), ids, expires_in: TTL) rescue nil
      end
      ids || []
    end

    # Network seam (stubbed in tests).
    def fetch(provider, api_key)
      return nil if Rails.env.test? # tests stub this; never call out

      case provider
      when :openai
        body = get("https://api.openai.com/v1/models", "Authorization" => "Bearer #{api_key}")
        body && Array(JSON.parse(body)["data"]).map { |m| m["id"].to_s }
      when :gemini
        body = get("https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000", "x-goog-api-key" => api_key)
        body && Array(JSON.parse(body)["models"])
                  .select { |m| Array(m["supportedGenerationMethods"]).include?("generateContent") }
                  .map { |m| m["name"].to_s }
      end
    rescue StandardError => e
      Rails.logger.warn("[AiModels] #{provider} list failed: #{e.class}: #{e.message}")
      nil
    end

    def get(url, headers)
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT
      req = Net::HTTP::Get.new(uri)
      headers.each { |k, v| req[k] = v }
      res = http.request(req)
      return res.body if res.is_a?(Net::HTTPSuccess)

      Rails.logger.warn("[AiModels] #{uri.host} -> #{res.code}: #{res.body.to_s.truncate(200)}")
      nil
    end
  end
end
