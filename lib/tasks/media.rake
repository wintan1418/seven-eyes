namespace :media do
  desc "Collect pictures already in signed-in users' services into their My Media libraries (idempotent)"
  task backfill: :environment do
    stats = MediaBackfill.run(logger: Logger.new($stdout))
    puts "My Media backfill: #{stats.inspect}"
  end
end
