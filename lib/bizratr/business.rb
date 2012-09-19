require 'uri'

module BizRatr
  class Business
    attr_accessor :name, :phone, :address, :state, :country, :zip, :twitter, :ids, :checkins, :users, :likes, :ratings, :review_counts, :coords, :city, :categories, :website

    def initialize(uberclient, lat, lon, name)
      @ids = {}
      @checkins = {}
      @users = {}
      @likes = {}
      @ratings = {}
      @review_counts = {}
      @categories = {}
      @coords = [lat, lon]
      @name = name
      @uberclient = uberclient
    end

    def to_s
      attrs = [:name, :phone, :address, :state, :country, :zip, :twitter, :ids, :checkins, :users, :likes, :ratings, :review_counts, :coords, :city, :categories, :website]
      args = attrs.map { |k| "#{k.to_s}=#{send(k)}" }.join(", ")
      "<Business [#{args}]>"
    end

    def rating
      @ratings.values.inject(:+) / @ratings.length
    end

    def total_users
      @users.values.inject { |a,b| a+b } || 0
    end

    # remove path and query info from the businesses website
    # (some website's have http://blah.com/index.html in some places
    # and http://blah.com in others and http://blah.com/ in yet others
    # - all three are equivalent)
    def website_normalized
      return nil if @website.nil?
      begin
        uri = URI(@website)
        uri.query = nil
        uri.path = ''
        uri.to_s
      rescue
        nil
      end
    end

    # Get all of the website like information from Facebook.  If there's no website, or an issue, return {} - otherwise
    # you'll get something of the form {"share_count"=>75, "like_count"=>10, "comment_count"=>9, "click_count"=>6}
    def website_likes
      fb = @uberclient.get_connector(:facebook)
      # normalize URL first
      url = website_normalized
      return {} if fb.nil? or url.nil?
      results = fb.get_url_likes(url)
      (results.length > 0) ? results.first : {}
    end

    def total_reviews
      @review_counts.values.inject { |a,b| a+b } || 0
    end

    def total_checkins
      @checkins.values.inject { |a,b| a+b } || 0
    end

    def total_likes
      @likes.values.inject { |a,b| a+b } || 0
    end

    def merge(other)
      @ids = @ids.merge(other.ids)
      @phone ||= other.phone
      @address ||= other.address
      @state ||= other.state
      @country ||= other.country
      @zip ||= other.zip
      @twitter ||= other.twitter
      @city ||= other.city
      @website ||= other.website
      @checkins = @checkins.merge(other.checkins)
      @users = @users.merge(other.users)
      @likes = @likes.merge(other.likes)
      @ratings = @ratings.merge(other.ratings)
      @review_counts = @review_counts.merge(other.review_counts)
      @coords[0] = (@coords[0].to_f + other.coords[0].to_f) / 2.0
      @coords[1] = (@coords[1].to_f + other.coords[1].to_f) / 2.0
      @categories = @categories.merge(other.categories)
      return self
    end

    def add_id(connector, id)
      @ids[connector] = id
    end

    def add_checkins(connector, checkins)
      @checkins[connector] = checkins
    end

    def add_users(connector, users)
      @users[connector] = users
    end

    def add_categories(connector, categories)
      @categories[connector] = categories
    end

    # Get all categories from all connectors.
    def flattened_categories
      @categories.values.flatten.map { |c| c.downcase }.uniq
    end

    def add_likes(connector, likes)
      @likes[connector] = likes
    end

    def add_rating(connector, rating)
      @ratings[connector] = rating
    end

    def add_review_counts(connector, counts)
      @review_counts[connector] = counts
    end

    def any_equal_ids?(other)
      @ids.each { |k,v|
        return true if other.ids[k] == v
      }
      false
    end

    def distance_to(other)
      rpd = 0.017453293  #  PI/180
      dlat = other.coords[0] - @coords[0]
      dlon = other.coords[1] - @coords[1]
      dlon_rad = dlon * rpd 
      dlat_rad = dlat * rpd
      lat1_rad = @coords[0] * rpd
      lon1_rad = @coords[1] * rpd
      lat2_rad = other.coords[0] * rpd
      lon2_rad = other.coords[1] * rpd
      a = (Math.sin(dlat_rad/2))**2 + Math.cos(lat1_rad) * Math.cos(lat2_rad) * (Math.sin(dlon_rad/2))**2
      2 * Math.atan2( Math.sqrt(a), Math.sqrt(1-a)) * 3956 # 3956 is the radius of the great circle in miles
    end

    def name_distance_to(other)
      name = other.is_a?(Business) ? other.name : other
      Levenshtein::normalized_distance(@name.downcase, name.downcase)
    end

    def ==(other)
      return false if other.nil?
      return true if any_equal_ids?(other)
      return true if @phone == other.phone and not @phone.nil?
      return true if distance_to(other) < 0.3 and name_distance_to(other) < 0.4
      false
    end
  end
end
