

namespace :db do
    desc "Process uploaded CSV file containing donation information and update PAT DB"
    task :process_donations => :environment do
		require 'csv'
		Time.zone = 'UTC'
		puts "This is the donation processing script"
		
		# find all .csv files
		FileList["uploads/*.csv"].each do |donation_file|
			any_errors = false
			puts "# Found a CSV file: " + donation_file
			CSV.foreach donation_file do |row|
				puts "# Processing a row"
				update_donation = false
				#puts " ### DEBUG : " + row[4].to_s unless row[4].nil?
				# Check for empty fields
				motvcode = row[0].to_s unless row[0].nil?
				extid = row[1].to_s unless row[1].nil?
				trans_date = row[2].to_s unless row[2].nil?
				ref = row[3].to_s unless row[3].nil?
				name = row[4].to_s unless row[4].nil?
				type = row[5].to_s unless row[5].nil?
				orgamount = row[6].to_s unless row[6].nil?
				amount = row[7].to_s unless row[7].nil?
				
				# set nil fields to empty strings
				motvcode ||= "" 
				extid ||= ""
				trans_date ||= ""
				ref ||= ""
				name ||= ""
				type ||= ""
				orgamount ||= "" 
				amount ||= ""
				
				puts "	# motv code: " + motvcode + " # ext id: " + extid + " # date: " + trans_date + " # ref: " + ref + " # name: " + name + " # type: " + type + " # org_amount: " + orgamount + " # amount: " + amount
				
				# Make sure this is a real row
				if motvcode == "" && extid == "" && trans_date = "" && ref == "" then
					puts "# Invalid row, going to ignore row."
					next
				end
				
				# Make sure we're not duplicating amounts
				donation = AutoDonation.find_by_donation_reference_number ref
				if !donation.nil?
					# check if its an unidentified transaction that now has been identified
					if donation.participant_motv_code == Pat::CONFIG[:motv_code_unidentified] && donation.participant_motv_code != motvcode then
					  update_donation = true
					else
					  puts "# This transaction is already in the system, moving to the next row"
					  next
					end
				end
				puts "# Adding row to database" unless update_donation
				# Refactor incoming date from dd/mm/yyyy to yyyy-mm-dd
				date_split = trans_date.split(/\-/)
				formatted_date = Time.zone.local(date_split[0].to_i, date_split[1].to_i, date_split[2].to_i, 0, 0, 0)
				# formatted_date = date_split[2] + "-" + date_split[1] + "-" + date_split[0]
				if update_donation then
				  donation.participant_motv_code = motvcode
				  donation.participant_external_id = extid
				  donation.donation_date = formatted_date
				  donation.donation_reference_number = ref
				  donation.donor_name = name
				  donation.donation_type = type
				  donation.original_amount = orgamount
				  donation.amount = amount
				  result = donation.save!
				else
				  result = AutoDonation.create :participant_motv_code => motvcode, :participant_external_id => extid, :donation_date => formatted_date, :donation_reference_number => ref, :donor_name => name, :donation_type => type, :original_amount => orgamount, :amount => amount
				end
				
				if result
					puts "# Done. Moving to the next row"
				else
					puts "# Error in inserting row!"
					any_errors = true
				end
			end
			if !any_errors
				# clean up if no errors
				puts "# Removing file: " + donation_file
				FileUtils.rm donation_file
			end
		end
		
    end
end


