namespace :faith_terms do
  desc "Load the Glossary of the Faith from config/faith_terms.yml (new terms arrive as drafts; reviewed/edited terms are never touched)"
  task seed: :environment do
    counts = FaithTermSeeder.call
    reviewed = FaithTerm.reviewed.count
    puts "Glossary of the Faith: #{counts[:created]} created, #{counts[:updated]} refreshed, #{counts[:kept]} kept " \
         "(#{reviewed} of #{FaithTerm.count} reviewed and public). Review at /admin/faith."
  end
end
