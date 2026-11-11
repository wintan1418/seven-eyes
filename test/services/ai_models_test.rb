require "test_helper"

class AiModelsTest < ActiveSupport::TestCase
  test "picks the newest full gpt-image model, then mini, then dall-e-3" do
    assert_equal "gpt-image-2", AiModels.pick_openai_image(%w[gpt-4o dall-e-3 gpt-image-1.5 gpt-image-2 gpt-image-2-mini gpt-image-2-2026-09-01])
    assert_equal "gpt-image-1.5", AiModels.pick_openai_image(%w[gpt-image-1.5 gpt-image-1-mini])
    assert_equal "gpt-image-1-mini", AiModels.pick_openai_image(%w[gpt-image-1-mini gpt-4o])
    assert_equal "dall-e-3", AiModels.pick_openai_image(%w[gpt-4o dall-e-3 dall-e-2])
    assert_nil AiModels.pick_openai_image(%w[gpt-4o])
  end

  test "picks gemini-flash-latest, else the newest stable Flash" do
    assert_equal "gemini-flash-latest", AiModels.pick_gemini_flash(%w[models/gemini-3.8-flash models/gemini-flash-latest])
    assert_equal "gemini-3.8-flash", AiModels.pick_gemini_flash(%w[models/gemini-2.5-flash models/gemini-3.8-flash models/gemini-3.8-flash-lite models/gemini-4-pro models/gemini-3.9-flash-preview])
    assert_nil AiModels.pick_gemini_flash(%w[models/gemini-4-pro])
  end
end
