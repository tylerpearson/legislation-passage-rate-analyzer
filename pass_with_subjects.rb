require 'httparty'
require 'json'
require 'pp'
require 'uri'
require 'hashie'

def load_json(filename)
  Hashie::Mash.new(JSON.parse(IO.read(filename)))
end

def calculate_percentage(numerator, denominator)
  total_percentage = numerator.to_f / denominator.to_f
  return 0 if total_percentage.nan?
  (total_percentage * 100).round(2)
end

def update_hashes(primary_hash, secondary_hash)
  secondary_hash.keys.each do |key|
    if primary_hash.has_key?(key)
      primary_hash[key] += 1
    else
      primary_hash[key] = 1
    end
  end
end

legislators_hash = {}

state = "wv" # two-letter abbreviation
year = 2011
chamber = "lower" # upper or lower

path = "dumps/#{state}/bills/#{state}/#{year}/#{chamber}"

Dir.foreach(path) do |item|
  next if item == '.' or item == '..'

  bill = load_json("#{path}/#{item}")

  passed = false

  bill.actions.each do |action|
    # va
    # if action.actor == "governor" && action.action.downcase.include?("approved by governor")
    #   passed = true
    # end

    # wv
    if action.type.include?("governor:signed")
      passed = true
    end

  end

  bill.sponsors.each do |sponsor|
    if !legislators_hash.has_key?(sponsor.name)
      legislators_hash[sponsor.name] = {
          :total => {
              :count => 0,
              :passed => 0,
              :subjects => Hash.new(0),
              :subjects_passed => Hash.new(0)
          },
          :primary => {
              :count => 0,
              :passed => 0,
              :subjects => Hash.new(0),
              :subjects_passed => Hash.new(0)
          },
          :cosponsor => {
              :count => 0,
              :passed => 0,
              :subjects => Hash.new(0),
              :subjects_passed => Hash.new(0)
          }
        }
    end

    bill_subjects_hash = Hash.new(0)
    bill.scraped_subjects.each do |subject|
      bill_subjects_hash[subject] += 1
    end unless bill.scraped_subjects.nil?

    lead_sponsor = (sponsor.type == "primary")

    legislators_hash[sponsor.name][:total][:count] += 1
    update_hashes(legislators_hash[sponsor.name][:total][:subjects], bill_subjects_hash) unless bill.scraped_subjects.nil?

    if lead_sponsor
      legislators_hash[sponsor.name][:primary][:count] += 1
      update_hashes(legislators_hash[sponsor.name][:primary][:subjects], bill_subjects_hash) unless bill.scraped_subjects.nil?
    else
      legislators_hash[sponsor.name][:cosponsor][:count] += 1
      update_hashes(legislators_hash[sponsor.name][:cosponsor][:subjects], bill_subjects_hash) unless bill.scraped_subjects.nil?
    end

    # lead sponsor and passed
    if lead_sponsor && passed
      legislators_hash[sponsor.name][:total][:passed] += 1
      legislators_hash[sponsor.name][:primary][:passed] += 1
      update_hashes(legislators_hash[sponsor.name][:primary][:subjects_passed], bill_subjects_hash) unless bill.scraped_subjects.nil?
    end

    # cosponsor and passed
    if !lead_sponsor && passed
      legislators_hash[sponsor.name][:total][:passed] += 1
      legislators_hash[sponsor.name][:cosponsor][:passed] += 1
      update_hashes(legislators_hash[sponsor.name][:cosponsor][:subjects_passed], bill_subjects_hash) unless bill.scraped_subjects.nil?
    end

    # lead sponsor and didn't pass
    if lead_sponsor && !passed

    end

    # cosponsor and didn't pass
    if !lead_sponsor && !passed

    end

  end

end

# ugly sorting thing that works for now
legislators_hash.keys.each do |legislator|
  legislators_hash[legislator][:total][:subjects] = legislators_hash[legislator][:total][:subjects].sort_by {|_key, value| value}.reverse.to_h
  legislators_hash[legislator][:total][:subjects_passed] = legislators_hash[legislator][:total][:subjects_passed].sort_by {|_key, value| value}.reverse.to_h

  legislators_hash[legislator][:primary][:subjects] = legislators_hash[legislator][:primary][:subjects].sort_by {|_key, value| value}.reverse.to_h
  legislators_hash[legislator][:primary][:subjects_passed] = legislators_hash[legislator][:primary][:subjects_passed].sort_by {|_key, value| value}.reverse.to_h

  legislators_hash[legislator][:cosponsor][:subjects] = legislators_hash[legislator][:cosponsor][:subjects].sort_by {|_key, value| value}.reverse.to_h
  legislators_hash[legislator][:cosponsor][:subjects_passed] = legislators_hash[legislator][:cosponsor][:subjects_passed].sort_by {|_key, value| value}.reverse.to_h
end

results = legislators_hash.sort_by { |username, results| calculate_percentage(results[:total][:passed], results[:total][:count])}.reverse

# pp results.to_h

Dir.mkdir("results/#{state}") unless File.exists?("results/#{state}")
Dir.mkdir("results/#{state}/#{year}") unless File.exists?("results/#{state}/#{year}")

File.open("results/#{state}/#{year}/#{chamber}.json","w") do |f|
  f.write(results.to_h.to_json)
end
