namespace :scenes do
  desc "Rebuild app/javascript/lib/scripture_scenes.json from config/scripture_scenes.yml"
  task json: :environment do
    ScriptureScenes.write_bundle!
    puts "#{ScriptureScenes.all.size} scenes → #{ScriptureScenes::BUNDLE.relative_path_from(Rails.root)}"
  end
end
