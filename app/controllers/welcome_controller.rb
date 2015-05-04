class WelcomeController < ApplicationController
  MOBILIZED = [:index]
  before_filter :unmobilized, :except => MOBILIZED
  before_filter :mobilized, :only => MOBILIZED
  before_filter :set_homepage_wiki, only: :index

  def index
    respond_to do |format|
      format.html do
        @announcement = Announcement.where('placement = \'welcome/index\' AND ? BETWEEN "start" AND "end"', Time.now.utc).last
        @observations_cache_key = "#{SITE_NAME}_#{I18n.locale}_welcome_observations"
        unless fragment_exist?(@observations_cache_key)
          @observations = load_observations_with_geo_and_good_photos
        end
        @google_webmaster_verification = @site.google_webmaster_verification if @site
      end
      format.mobile
    end
  end

  def load_observations_with_geo_and_good_photos(number_to_load = 4)
    # number to fetch at time. We could use number_to_load but
    # just in case there are 1 or 2 observations with photos
    # still processing, fetch a couple extra
    batch_size = number_to_load + 2
    offset = 0
    observations = [ ]
    return observations unless Observation.first
    while observations.size < number_to_load
      scope = Observation.has_geo.has_photos.offset(offset).
        order("observations.id DESC").limit(batch_size)
      if CONFIG.site_only_observations && params[:site].blank?
        # we can restrict homepage observations by URI
        scope = scope.where("observations.uri LIKE ?", "#{FakeView.root_url}%")
      elsif (site_bounds = CONFIG.bounds) && params[:swlat].blank?
        # we can also restrict by bounding box
        scope = scope.in_bounding_box(site_bounds['swlat'], site_bounds['swlng'],
          site_bounds['nelat'], site_bounds['nelng'])
      end
      # don't use an observation if its photos are still processing
      observations += scope.to_a.delete_if{ |o|
        o.observation_photos_finished_processing.blank? }
      break if observations.size < number_to_load && offset > Observation.maximum(:id)
      offset += batch_size
    end
    # remove any extra if there are more than were asked for
    observations = observations[0...number_to_load]
    Observation.preload_associations(observations, [
      :taxon, :stored_preferences,
      { :observation_photos => :photo },
      { :user => :stored_preferences } ])
    observations
  end

  def toggle_mobile
    session[:mobile_view] = session[:mobile_view] ? false : true
    redirect_to params[:return_to] || session[:return_to] || "/"
  end

  private

  def set_homepage_wiki
    # use a custom wiki page for this locale
    if CONFIG.home_page_wiki_path_by_locale
      if path = CONFIG.home_page_wiki_path_by_locale.send( I18n.locale )
        @page = WikiPage.find_by_path( path )
      end
    end
    # otherwise use the site default wiki page
    if @page.blank? && CONFIG.home_page_wiki_path
      @page = WikiPage.find_by_path( CONFIG.home_page_wiki_path )
    end
  end

end
