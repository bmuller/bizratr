module BizRatr
  class Business
    attr_accessor :name, :phone, :address, :state, :country, :zip, :twitter, :ids, :checkins, :users, :likes, :ratings, :review_counts, :coords, :city, :categories

    def initialize(lat, lon, name)
      @ids = {}
      @checkins = {}
      @users = {}
      @likes = {}
      @ratings = {}
      @review_counts = {}
      @categories = {}
      @coords = [lat, lon]
      @name = name
    end

    def to_s
      attrs = [:name, :phone, :address, :state, :country, :zip, :twitter, :ids, :checkins, :users, :likes, :ratings, :review_counts, :coords, :city, :categories]
      args = attrs.map { |k| "#{k.to_s}=#{send(k)}" }.join(", ")
      "<Business [#{args}]>"
    end

    def rating
      @ratings.values.inject(:+) / @ratings.length
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
      @checkins = @checkins.merge(other.checkins)
      @users = @users.merge(other.users)
      @likes = @likes.merge(other.likes)
      @ratings = @ratings.merge(other.ratings)
      @review_counts = @review_counts.merge(other.review_counts)
      @coords[0] = (@coords[0].to_f + other.coords[0].to_f) / 2.0
      @coords[1] = (@coords[1].to_f + other.coords[1].to_f) / 2.0
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
      @users[connector] = likes
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
      Levenshtein::normalized_distance(@name, name)
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
