

namespace :db do
    desc "Maps CDM campus associations with legacy campus selectbox"
    task :map_campuses => :environment do
    	campus_map = YAML.load_file("config/campus_mapping.yml")
		# Go through each form_anwser with question_id 252 (campus selectbox)
		#	remember answer (this is the option value)
		# 	use instance id to figure out person: instance_id->applns.id
		#		check if person has a campus association. If not, then add a new one based on
		#		the static map we built
		puts "This is the campus association mapping script"
		@apps = Appln.all :joins => :answers, :conditions => { :form_answers => { :question_id => 252 } }
		@apps.each do |app|
			# eager loading is broken here, so we'll have to waste some cpu cycles
          puts "# Found app to process: " + app.id.to_s
          option_value = nil
          app.answers.each do |form_answer|
          	if form_answer.question_id == 252 and !form_answer.answer.empty? then
          		puts "	Option value = " + form_answer.answer
          		puts "	This is campus: " + campus_map[form_answer.answer.to_i]["campus_name"]
				option_value = form_answer.answer.to_i
          		break
			end
          end
          if option_value.nil?
          	puts "  No option value found, continue with next app"
          	next
          end
 
          # At this stage we can now check if the person already has a campus involvement
          @ci = app.viewer.person.most_recent_involvement
          if @ci.nil?
          	
          	puts "	No ci found, creating one from selected legacy campus"
          	puts "		person id: " + app.viewer.person.id.to_s
          	# get ministry for campus, manually
          	@mc = MinistryCampus.find(:first, :conditions => { :campus_id => campus_map[option_value]["pulse_id"] })
			# now do the insert
			if !@mc.nil?
				puts "ministry id: " + @mc.ministry_id.to_s
				@campus_involvement = CampusInvolvement.create :start_date => Date.today, :ministry_id => @mc.ministry_id, :campus_id => campus_map[option_value]["pulse_id"], :person_id => app.viewer.person.id, :school_year_id => 1
				
				@campus_involvement.find_or_create_ministry_involvement
				# Set primary campus for person
				app.viewer.person.update_attributes({ :primary_campus_involvement_id => @campus_involvement.id })
				
				puts "new ci id: " + @campus_involvement.id.to_s
			end
          end
        end
    end
end


