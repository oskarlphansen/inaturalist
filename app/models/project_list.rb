class ProjectList < LifeList
  belongs_to :project
  validates_presence_of :project_id
  
  def owner
    project
  end
  
  def owner_name
    project.title
  end
  
  def listed_taxa_editable_by?(user)
    return false if user.blank?
    project.project_users.exists?(:user_id => user)
  end
  
  # Curators and admins can alter the list.
  def editable_by?(user)
    return false if user.blank?
    project.project_users.exists?(["role IN ('curator', 'manager') AND user_id = ?", user])
  end
  
  #For project_lists, returns first_observation (array of [date, observation_id])
  #where date represents the first date observed (e.g. not first date added to iNat)
  #now only make project listed taxa from research grade obs or
  #obs with po.curator_identifications which take precidence over research grade obs for creating listed_taxa
  def cache_columns_query_for(lt)
    lt = ListedTaxon.find_by_id(lt) unless lt.is_a?(ListedTaxon)
    return nil unless lt
    ancestry_clause = [lt.taxon_ancestor_ids, lt.taxon_id].flatten.map{|i| i.blank? ? nil : i}.compact.join('/')
    sql_key = "EXTRACT(month FROM observed_on) || substr(quality_grade,1,1)"
    <<-SQL
      SELECT
        min(CASE WHEN quality_grade = 'research' THEN o.id WHEN po.curator_identification_id IS NOT NULL THEN o.id END) AS first_observation_id,
        max(
          CASE WHEN quality_grade = 'research'
          THEN (COALESCE(time_observed_at, observed_on)::varchar || ',' || o.id::varchar)
          WHEN po.curator_identification_id IS NOT NULL THEN (COALESCE(time_observed_at, observed_on)::varchar || ',' || o.id::varchar) 
          END
        ) AS last_observation,
        count(*),
        (#{sql_key}) AS key
      FROM
        observations o
          LEFT OUTER JOIN taxa t ON t.id = o.taxon_id
          LEFT OUTER JOIN project_observations po ON po.observation_id = o.id
          LEFT OUTER JOIN identifications i ON i.id = po.curator_identification_id
          LEFT OUTER JOIN taxa ti ON ti.id = i.taxon_id
      WHERE
        po.project_id = #{project_id} AND
        (
          CASE WHEN po.curator_identification_id IS NULL THEN (
            o.taxon_id = #{lt.taxon_id} OR 
            t.ancestry = '#{ancestry_clause}' OR
            t.ancestry LIKE '#{ancestry_clause}/%'
          ) ELSE (
            i.taxon_id = #{lt.taxon_id} OR 
            ti.ancestry = '#{ancestry_clause}' OR
            ti.ancestry LIKE '#{ancestry_clause}/%'
          ) END
        )
      GROUP BY #{sql_key}
    SQL
  end
  
  def self.refresh_with_project_observation(project_observation, options = {})
    Rails.logger.info "[INFO #{Time.now}] Starting ProjectList.refresh_with_project_observation for #{project_observation}, #{options.inspect}"
    project_observation = ProjectObservation.find_by_id(project_observation) unless project_observation.is_a?(ProjectObservation)
    unless observation = Observation.find_by_id(options[:observation_id])
      Rails.logger.error "[ERROR #{Time.now}] ProjectList.refresh_with_project_observation " + 
        "failed with blank observation, project_observation: #{project_observation}, options: #{options.inspect}"
      return
    end
    taxon = Taxon.find_by_id(options[:taxon_id])
    if taxon.nil?
      taxon_ids = []
    else
      taxon_ids = [taxon.ancestor_ids, taxon.id].flatten
    end
    if taxon_was = Taxon.find_by_id(options[:taxon_id_was])
      taxon_ids = [taxon_ids, taxon_was.ancestor_ids, taxon_was.id].flatten.uniq
    end
    unless project = Project.find_by_id(options[:project_id])
      Rails.logger.error "[ERROR #{Time.now}] ProjectList.refresh_with_project_observation " + 
        "failed with blank project, project_observation: #{project_observation}, options: #{options.inspect}"
      return
    end
    target_list_id = ProjectList.where(:project_id => project.id).first.id
    
    # get listed taxa for this taxon and its ancestors that are on the project list
    listed_taxa = ListedTaxon.all(:include => [:list],
      :conditions => ["taxon_id IN (?) AND list_id = ?", taxon_ids, target_list_id])
    listed_taxa.each do |lt|
      Rails.logger.info "[INFO #{Time.now}] ProjectList.refresh_with_project_observation, refreshing #{lt}"
      refresh_listed_taxon(lt)
    end
    Rails.logger.info "[INFO #{Time.now}] Finished ProjectList.refresh_with_project_observation for #{project_observation.id}"
    
    if taxon #if the observation has a curator_id
      if respond_to?(:create_new_listed_taxa_for_refresh)
        create_new_listed_taxa_for_refresh(taxon, listed_taxa, [target_list_id])
      end
    end
    Rails.logger.info "[INFO #{Time.now}] refresh_with_project_observation #{project_observation.id}, finished"
  end
  
  def self.refresh_with_observation_lists(observation, options = {})
    observation = Observation.find_by_id(observation) unless observation.is_a?(Observation)
    return [] unless observation.is_a?(Observation)
    project_ids, curator_identification_ids = observation.project_observations.map{|po| [po.project_id, po.curator_identification_id]}.transpose
    return [] if project_ids.nil?
    target_list_and_curator_ids = ProjectList.all(:select => "id", :conditions => ["project_id IN (?)", project_ids]).map{|pl| pl.id}.zip(curator_identification_ids)
    #only update listed taxa if the project_observations have no curator_identification_ids
    #otherwise update these listed_taxa when the curator_identification_id on the project_observation changes
    target_list_and_curator_ids.map{|pair| pair[0] unless pair[1] }.compact
  end
  
  private
  def set_defaults
    self.title ||= "%s's Check List" % owner_name
    self.description ||= "The species list for #{owner_name}"
    true
  end
end
