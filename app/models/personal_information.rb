class PersonalInformation < CustomElement
  def text()
    "Personal Information Form"
  end

  def save_answer(instance, params, answers)
    @person = instance.viewer.person

    PersonalInformation.save_from_params(@person, params)
  end

  def self.save_from_params(person, params)
    # person[:email] is in the campus project app as a q with programmer
    # options, it messes up the update_attributes save since it's a defined
    # method and not a column
    if params[:appln_person]
      
      # copy local address info to permanent if requested
      copy = params[:appln_person].delete :permanent_same_as_local
      if copy == '1'
        for suffix in Common::Core::Person::ADDRESS_SUFFIX_TO_COLUMN.keys
          params[:"person_#{suffix}"] = params[:appln_person][:"person_local_#{suffix}"]
          params[:appln_person][:"permanent_#{suffix}"] = params[:appln_person][:"person_local#{suffix}"]
        end
      end

      person_params = params[:appln_person].clone
      
      # we need to fill in legal first name & last name if it wasn't filled in already
      if person_params[:first_name].empty?
        person_params[:first_name] = person_params[:preferred_first_name]
      end
      if person_params[:last_name].empty?
        person_params[:last_name] = person_params[:preferred_last_name]
      end

      person_params.delete 'email'
      person_params.delete 'year_in_school_id'

      # Grad dates confuse this update.  Grad date is updated in the CampusInfo model anyways.
      person_params.delete 'grad_date(1i)'
      person_params.delete 'grad_date(2i)'
      person_params.delete 'grad_date(3i)'
      person_params.delete 'birth_date(1i)'
      person_params.delete 'birth_date(2i)'
      person_params.delete 'birth_date(3i)'

      # Need all three of date fields chosen, otherwise it crashes
=begin
      if (person_params["local_valid_until(1i)"].present? || person_params["local_valid_until(2i)"].present? ||
          person_params["local_valid_until(3i)"].present?) && !(person_params["local_valid_until(1i)"].present? &&
          person_params["local_valid_until(2i)"].present? && person_params["local_valid_until(3i)"].present?)
        person_params.delete 'local_valid_until(1i)'
        person_params.delete 'local_valid_until(2i)'
        person_params.delete 'local_valid_until(3i)'
      end
=end
      DateParamsParser.parse(person_params, "local_valid_until")
      DateParamsParser.parse(person_params, "permanent_valid_until")

      person.initialize_addresses
      person.update_attributes(person_params)
      person.save!
    end
  end
end

