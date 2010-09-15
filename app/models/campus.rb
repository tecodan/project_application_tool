class Campus < ActiveRecord::Base
  load_mappings
  include Common::Core::Campus
  
  def self.regional_national_id
  	@@regional_national_id ||= Campus.find_by_campus_abbrv('Reg/Nat')
  end
  
  def students(options = {})
    # under assumption that everyone with a CI is a student
    # this is eager loading at the moment, so probably need refactoring.

  	#ministry_student_ids = MinistryRole.all(:conditions => { :type => 'StudentRole' }).compact.collect(&:id)
  	#Person.all :joins => :ministry_involvements, :limit => 2, :conditions => { :ministry_involvements => { :ministry_id => 1, :ministry_role_id => ministry_student_ids }}

    self.people.all :conditions => "campus_involvements.end_date is null OR campus_involvements.end_date > curdate()", :select => options[:select]

    #campus_involvements.find_all_by_assignmentstatus_id(Assignmentstatus.campus_student_ids,
    #    :select => options[:select]
    #).collect { |a| a.person }
    
  end
  
end

