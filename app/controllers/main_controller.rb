require_dependency 'bsearch'
require_dependency 'rubygems'

class MainController < ApplicationController
  before_filter :set_campuses, :only => [ :index, :your_campuses, :your_applications ]
  
  stateless_tasks = [ :questionnaire, :dump_fixtures, :load_fixtures ]

  skip_before_filter :verify_user, :only => stateless_tasks
  skip_before_filter :verify_event_group_chosen, :only => stateless_tasks
  skip_before_filter :set_event_group, :only => stateless_tasks

  skip_before_filter :set_user, :only => stateless_tasks
  skip_before_filter :get_user, :only => stateless_tasks
  skip_before_filter :restrict_students, :only => [ :questionnaire, :emails ]
  skip_before_filter :ensure_year_set, :only => stateless_tasks
  skip_before_filter :set_campuses, :only => stateless_tasks
  
  CampusStats = Struct.new(:students_cnt, :student_profiles, :accepted_cnt, :applied_cnt, :students_no_profiles)
  StudentProfile = Struct.new(:student, :profile)
  
  def send_test_email
    TestMailer.deliver_test(params[:subject], params[:message], params[:to], params[:from])
    flash[:notice] = 'test email sent'
    redirect_to :action => :test_email
  end

  def emails
    if RAILS_ENV =~ /test/ || RAILS_ENV == 'development'
      @emails = ActionMailer::Base.deliveries
    end
  end

  def index
    logger.info 'starting main_controller index'
    flash.keep

    # at this point we know the user is not a student, unless they're intern
    # 
    # project directors would like to go to my projects
    if @viewer.is_eventgroup_coordinator?(@eg)
      redirect_to :action => :your_projects
    else
      # students should go to your projects, that's all they can see -- they might
      #  be interns then they can see support coaches only
      if @viewer.is_student?(@eg)
        redirect_to :action => :your_projects
      else
        redirect_to :action => :your_campuses
      end
    end
  end
  
  def edit_form
    @form = Form.find(params[:id])
    # try to reconnect the form by being smart about the name if necssary
    if @form.questionnaire.nil?
      @form.questionnaire_id = Questionnaire.find_by_title("#{@form.year} #{@form.name}").id
      @form.save!
    end
    redirect_to :controller => "questionnaires", :action => "edit", :id => @form.questionnaire_id
  end
  
  def your_campuses
    @current_projects_form = @eg.application_form

    # getting the project name as a join is simply too slow
    @projects_cache = Hash[*@eg.projects.collect{ |p| [ p.id, p.title ] }.flatten]
    
    generate_campus_stats(@campuses)
    
    @page_title = "Your Campuses"
  end
  
  def your_projects
    if (@viewer.is_eventgroup_coordinator?(@eg))
      @allowable_projects = @eg.projects.find :all
    else
      @allowable_projects = @viewer.current_projects_with_any_role @eg
    end
    
    @allowable_projects_array = []
    @allowable_projects.each { |p| @allowable_projects_array << [p.title, p.id]}
    
    @first_allowable_project = @allowable_projects.first unless @allowable_projects.empty?
    
    @allowable_projects_array << ["All", "all"]
    
    # give a default project_id
    if params[:project_id].nil?
      if session[:project_id]
        params[:project_id] = session[:project_id]
      else
        params[:project_id] = @first_allowable_project ? @first_allowable_project.id.to_s : ''
      end
    end

    if params[:project_id] == 'all'
      @show_projects = @allowable_projects
    else
      requested_project_ids = params[:project_id].to_s.split(',') # comma-separated list of projects ids
      @show_projects = @allowable_projects.find_all{ |p| requested_project_ids.include?(p.id.to_s) }

      # if none of the projects they requested are permissible, use the first one
      @show_projects = [ @allowable_projects.first ] if @show_projects.empty? && @allowable_projects.length >= 1

    # now that we know what projects will be shown with @show_projects, we can do the big query
    #@show_projects = @eg.projects.find @show_projects.collect{ |p| p.id },
    #  :include => [ 
    #    { :acceptances => [
    #        { :viewer => [ 
    #            :vieweraccessgroups, 
    #            { :persons => :campuses } 
    #          ]
    #        },
    #        :projects,
    #         
    #      ]
    #    }
    #  ] end
    end

    session[:project_id] = @show_projects.first.id if @show_projects.length == 1
    
    @page_title = "Your Projects"
    if request.xml_http_request?
      render :file => 'main/render_your_project.rjs', :use_full_path => true
    else
      render :layout => !request.xml_http_request?
    end
  end
  
  def your_applications
    @page_title = "App Processing"
    if (@viewer.is_eventgroup_coordinator?(@eg))
      processor_for_project_ids = @eg.projects.collect{ |p| p.id }
    else
      # find which projects @viewer is a processor for
      processor_for_project_ids = Processor.find_all_by_viewer_id(@viewer.id).collect { 
        |entry| if entry.project.event_group_id == @eg.id then entry.project_id else nil end }.compact
    end
    
    @can_evaluate = true
    @processor_list = Applying.find_all_by_project_id(processor_for_project_ids, :include => :appln)
    @processor_list.delete_if { |pl| pl.appln.status != 'completed' }
    @processor_list.sort{ |a,b| 
      if a.appln.submitted_at.nil? && b.appln.submitted_at
        1
      elsif b.appln.submitted_at.nil? && a.appln.submitted_at
        -1
      elsif a.appln.submitted_at.nil? && b.appln.submitted_at.nil?
        0
      else
        b.appln.submitted_at <=> a.appln.submitted_at
      end
    }
  end
  
  def questionnaire
    @controller = params[:c] || params[:controller]
    headers['Content-Type'] = "text/javascript"
    render :layout => false
  end
  
  def find_people
    name = params[:viewer][:name]
    @people = Person.search_by_name name
    @viewers = Viewer.find_all_by_viewer_userID name
    @viewers += @people.collect {|p| p.viewers }.flatten
    @viewers.compact!
  end
  
  def get_viewer_specifics
    @show_viewer = Viewer.find(params[:id])

    profiles = Profile.find_all_by_viewer_id(@show_viewer.id, :include => [ :appln => :form ])
    @profiles_by_eg = EventGroup.find(:all).collect { |eg|
      [ eg, profiles.find_all { |p| 
        if p.project 
          p.project.event_group_id == eg.id 
        elsif p.appln && p.appln.form
          p.appln.form.event_group_id == eg.id
        else
          false
        end
      } ]
    }

    for profile in profiles
      @project = profile.project
      @viewer.set_project @project

      if @viewer.fullview?
        # we know at least one project has a full view
        @restricted_full_view = true
      end
    end

    @project = nil # force it to reset view permission for each item

    render :partial => "viewer_specifics"
  end

  def get_viewer_specifics_old
    @viewer = Viewer.find(params[:id], :include => :persons)
    @acceptances_list = Acceptance.find_all_by_viewer_id(@viewer.id, :include => :appln)
    @withdrawns_list = Withdrawn.find_all_by_viewer_id(@viewer.id, :include => :appln)
    @processor_lists_list = Applying.find_all_by_viewer_id(@viewer.id, :include => :appln)
    #@processor_lists_list.delete_if { |pl| pl.appln.status != 'completed' }
    @processor_lists_list.sort{ |a,b| 
      b.appln.submitted_at <=> a.appln.submitted_at
    }
    #@staffs = nil
    @staffs_list = Profile.find(:all, 
    :conditions => ["profiles.viewer_id = ? and profiles.type = ?", @viewer.id, "StaffProfile"])
    @applns = Appln.find_all_by_viewer_id @viewer.id, :include => :profiles
    #@applns.reject!{ |a| ![ 'withdrawn', 'declined', 'started', 'unsubmitted' ].include?(a.status) }
    @full_view = @viewer.fullview?
    @projects = true

    # sort the different findings into event groups
    #        if !@accepted.empty? || !@processor_list.empty? || !@staff.empty? || !@withdrawn.empty?
    #
    @acceptances = {}
    @acceptances_list.each do |a| eg = a.form.event_group; 
       @acceptances[eg] ||= []; @acceptances[a.form.event_group] << eg;
    end
    @processor_lists = {}
    @processor_lists_list.each do |a| eg = a.form.event_group; 
       @processor_lists[eg] ||= []; @processor_lists[a.form.event_group] << eg;
    end
    @acceptances = {}
    @acceptances_list.each do |a| eg = @acceptances[a.form.event_group_id]; 
       @acceptances[eg] ||= []; @acceptances[a.form.event_group] << eg;
    end
render :partial => "viewer_specifics"
  end
  
  def search_people_by_name
    @page_title = "Search"
  end

  def dump_fixtures
    return unless RAILS_ENV == 'test'
    r = %x[cd #{RAILS_ROOT}; rake db:fixtures:dump_test]
    render :inline => "<html><body><pre>#{r}</pre></body></html>"
  end

  def load_fixtures
    return unless RAILS_ENV == 'test'
    require RAILS_ROOT + '/spec/spec_helper'

    r = describe EventGroup, "loading all fixtures" do
      fixtures :all
    end

    render :inline => "<html><body><pre>#{r}</pre></body></html>"
  end
  
  def find_prep_items
    if %w(received optional).include?(params[:command]) && params[:project_id]
      # set @projects - if no project id is given, use all if using tools
      @projects = if params[:project_id].empty?
                    if params[:from_tools] then @eg.projects else nil end
                  else @eg.projects.find_all_by_id params[:project_id].split(',') end

      # ensure valid project
      unless @projects && !@projects.empty?
        flash[:notice] = 'paperwork: invalid project'
        redirect_to :back
        return
      end
        
      # get profiles out of projects
      @profiles = @projects.collect{ |p| p.acceptances + p.staff_profiles }.flatten
        
      # sort by name if they came from tools
      if params[:from_tools] && params[:name] && !params[:name].empty?
        people = Person.search_by_name params[:name]
        @profiles = @profiles.find_all{ |p| people.include?(p.viewer.person) }
      end

      # get prep_items from projects
      @prep_items = @eg.prep_items + @projects.collect{ |p| p.prep_items }.flatten.uniq
      # ensure profile_prep_items is current
      @prep_items.each { |pi| pi.ensure_all_profile_prep_items_exist }

      # filter non-individual prep_items if optional command
      if params[:command] == "optional" then @prep_items.delete_if { |pi| !pi.individual } end
    else
      flash[:notice] = 'paperwork: invalid command or options: command should be either received or optional, and project_id should be given'
      redirect_to :back
    end
  end

  protected
  
  def get_students_profiles_from_sorted_profiles(profiles, viewers)
    viewers.collect{ |viewer|
      # do a binary search to find all profiles by viewer
      range = profiles.bsearch_range { |profile| profile.viewer_id <=> viewer.id }

      # return all appropriate applications
      profiles[range]
    }.compact.flatten
  end

  def generate_campus_stats(campuses)
    @campus_stats = { }
    for campus in campuses
      @campus_stats[campus] = CampusStats.new
      
      @campus_stats[campus].students_cnt = 0
      @campus_stats[campus].student_profiles = [ ]
      @campus_stats[campus].students_no_profiles = [ ] # not used
      @campus_stats[campus].accepted_cnt = 0
      @campus_stats[campus].applied_cnt = 0
      
      next if @current_projects_form.nil?

      for person in campus.students
        @campus_stats[campus].students_cnt += 1

        if person.viewer
          for profile in person.viewer.profiles
            next unless profile.appln && profile.appln.form_id == @current_projects_form.id

            @campus_stats[campus].student_profiles << StudentProfile.new(person, profile)
          
            if profile.class == Acceptance
              @campus_stats[campus].accepted_cnt += 1
              @campus_stats[campus].applied_cnt += 1
            elsif profile.class == Applying
              @campus_stats[campus].applied_cnt += 1
	        end
          end
        end
      end
    end
  end
  
  def set_campuses
    @campuses = @viewer ? users_campuses : []
  end
  
  def users_campuses
    campuses = nil

    if @viewer.is_eventgroup_coordinator?(@eg)
      campuses = Campus.all
    elsif @viewer.person.is_staff_somewhere?
      ministry_involvements = @viewer.person.ministry_involvements
      for mi in ministry_involvements
        if campuses.nil?
      	  campuses = mi.ministry.campuses.all
        else
     	  campuses = campuses + mi.ministry.campuses.all
     	end
      end
      campuses
    else
      campuses = @viewer.person.campuses
    end
  end
  
 
  private

  #def start_profiling() RubyProf.start end

  #def end_profiling
  #  result = RubyProf.stop
  #  #printer = RubyProf::GraphHtmlPrinter.new(result)
  #  printer = RubyProf::FlatPrinter.new(result)
  #  @debug = ''
  #  printer.print(@debug, :min_percentage => 0)
  #  @debug = "<pre>#{@debug}</pre>"
  #end

end
