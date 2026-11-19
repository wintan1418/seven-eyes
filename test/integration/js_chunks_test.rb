require "test_helper"

# application.js is code-split (esbuild.config.mjs): the layout preloads the
# chunks it imports up front, heavy controllers load on first use, and the
# service worker saves every chunk for offline use.
class JsChunksTest < ActionDispatch::IntegrationTest
  test "pages preload the chunks application.js imports, and each one is served" do
    get root_path
    assert_response :success
    preloads = css_select("link[rel=modulepreload]").map { |link| link["href"] }
    assert preloads.any?, "expected modulepreload links (is app/assets/builds built with yarn build?)"
    assert preloads.all? { |href| href.match?(%r{\A/assets/[\w.-]+\.digested\.js\z}) }, preloads.inspect
    preloads.each do |href|
      asset = Rails.application.assets.load_path.find(href.delete_prefix("/assets/"))
      assert asset, "#{href} isn't in the asset load path"
    end
  end

  test "heavy controllers are lazy: the projector isn't in the up-front bundle" do
    main = [ "application.js", *ApplicationHelper.static_chunks("application.js") ]
      .map { |name| Rails.application.assets.load_path.find(name).content }.join
    index = Rails.root.join("app/javascript/controllers/index.js").read
    assert_match(/"presentation": \(\) => import\("\.\/presentation_controller"\)/, index)
    refute_match(/^import PresentationController/, index)
    # presentation_controller's own chunk is only named through import().
    lazy = Dir[Rails.root.join("app/assets/builds/presentation_controller-*.digested.js")]
    assert_equal 1, lazy.size
    assert_includes main, "/assets/#{File.basename(lazy.first)}"
    refute_includes ApplicationHelper.static_chunks("application.js"), File.basename(lazy.first)
  end

  test "the service worker saves the chunks scripts import, and keeps them when pruning" do
    get pwa_service_worker_path, headers: { "Accept" => "text/javascript" }
    body = @response.body
    assert_includes body, "async function saveScriptChunks"
    assert_includes body, "savedChunksOf(statics, keep)"
    assert_match(/await saveScriptChunks\(CONFIG\.assets/, body)
  end
end
