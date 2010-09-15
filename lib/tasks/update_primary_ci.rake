

namespace :db do
    desc "Bulk update missing primary campus involvements"
    task :update_primary_ci => :environment do

		# Go through each form_anwser with question_id 252 (campus selectbox)
		#	remember answer (this is the option value)
		# 	use instance id to figure out person: instance_id->applns.id
		#		check if person has a campus association. If not, then add a new one based on
		#		the static map we built
		puts "This is the bulk primary campus involvement update script"
		@people = Person.all :conditions => "primary_campus_involvement_id is null or primary_campus_involvement_id = ''"
		
		@people.each do |person|
		  # eager loading is broken here, so we'll have to waste some cpu cycles
          puts "# Found person to process: " + person.id.to_s
          # see if we can get their most recent campus involvement
          ci = person.most_recent_involvement
          if ci.nil?
          	puts "	Person has no existing campus involvement record."
          	next
          end
          puts "	Person most recent CI record: " + ci.id.to_s
          # Now update their primary campus involvement value
          result = person.update_attributes({ :primary_campus_involvement_id => ci.id })
          if result 
          	puts "	Primary CI has been updated."
          else
          	puts "	Could not update person, possibly a validation error!"
          end
        end
    end
end


