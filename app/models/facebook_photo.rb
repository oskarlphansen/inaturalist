class FacebookPhoto < Photo
  
  Photo.descendent_classes ||= []
  Photo.descendent_classes << self
  
  validates_presence_of :native_photo_id
    
#  def validate
#    # Check to make sure the user owns the flickr photo
#    if self.user && self.api_response
#      if self.api_response.is_a?(Net::Flickr::Photo)
#        fp_flickr_user_id = self.api_response.owner
#      else
#        fp_flickr_user_id = self.api_response.owner.nsid
#      end
#      
#      if user.flickr_identity.blank? || fp_flickr_user_id != user.flickr_identity.flickr_user_id
#        errors.add(:user, "must own the photo on Flickr.")
#      end
#    end
#  end
#  
  
  def validate
    fbp_json = FacebookPhoto.get_api_response(self.native_photo_id, {:user=>self.user})
    if self.user && fbp_json
      if user.facebook_identity.blank? || fbp_json['from']['id'] != user.facebook_identity.provider_uid
        errors.add(:user, "must own the photo on Facebook.")
      end
    end
  end

  def self.get_api_response(native_photo_id, options = {})
    return nil unless (options[:user] && options[:user].facebook_api)
    return options[:user].facebook_api.get_object(native_photo_id)
  end

  # facebook doesn't provide a square image
  # so for now, just return the thumbnail image
  def square_url
    return self.thumb_url
  end

  def self.new_from_api_response(api_response, options = {})
    fp = api_response
    # facebook api provides these sizes in an keyless array, in this order
    [:large_url, :medium_url, :small_url, :thumb_url].each_with_index{|img_size,i|
      options.update(img_size=>fp['images'][i]['source'])
    }
    options.update(
      :native_photo_id => fp["id"],
      :square_url => nil, # facebook doesn't provide a square image
      :original_url => fp['source'],
      :native_page_url => fp["link"],
      :native_username => fp["from"]["name"],
      :native_realname => fp["from"]["name"],
      :license => nil
    )
    facebook_photo = FacebookPhoto.new(options)
    facebook_photo.api_response = fp
    return facebook_photo
  end

  def to_observation
    fbp_json = self.api_response || FacebookPhoto.get_api_response(self.native_photo_id, :user => self.user)
    observation = Observation.new
    observation.user = self.user if self.user
    observation.photos << self
    observation.description = fbp_json["name"]
    #observation.observed_on_string = fp.taken.to_s(:long)
    #observation.munge_observed_on_with_chronic
    #observation.time_zone = observation.user.time_zone if observation.user
    return observation
  end

#  
#  # Try to extract known taxa from the tags of a flickr photo
#  def to_taxa(options = {})
#    self.api_response ||= FlickrPhoto.get_api_response(self.native_photo_id, :user => options[:user] || self.user)
#    taxa = if api_response.tags.blank?
#      []
#    else
#      # First try to find taxa matching taxonomic machine tags, then default 
#      # to all tags
#      tags = api_response.tags.values.map(&:raw)
#      machine_tags = tags.select{|t| t =~ /taxonomy\:/}
#      taxa = Taxon.tags_to_taxa(machine_tags) unless machine_tags.blank?
#      taxa ||= Taxon.tags_to_taxa(tags, options)
#      taxa
#    end
#    taxa.compact
#  end
end
