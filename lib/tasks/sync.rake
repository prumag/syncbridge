namespace :sync do
  desc "Run a full sync inline. Usage: bin/rails sync:full[attendees] (default: all resources)"
  task :full, [ :resource ] => :environment do |_task, args|
    resources = args[:resource] ? [ args[:resource] ] : SyncRun::RESOURCES

    resources.each do |resource|
      run = FullSync.new(resource).call
      puts "#{resource}: #{run.status} fetched=#{run.records_fetched} created=#{run.records_created} updated=#{run.records_updated}"
    end
  end
end
