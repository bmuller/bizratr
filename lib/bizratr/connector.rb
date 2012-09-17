require 'foursquare2'
require 'yelpster'
require 'levenshtein'
require 'google_places'
require 'geocoder'
require 'factual'

module BizRatr
  class Connector
    def search_location(location, query)
      raise "Not implemented"
    end

    def geocode(address)
      Geocoder.coordinates(address)
    end
  end

  class FactualConnector < Connector
    def initialize(config)
      @client = Factual.new(config[:key], config[:secret])
    end

    def search_location(location, query)
      location = geocode(location) if location.is_a? String
      results = @client.table("places").filters("name" => query).geo("$circle" => { "$center" => location, "$meters" => 1000 })
      results.map { |item| make_business(item) }
    end

    def make_business(item)
      b = Business.new(item['latitude'], item['longitude'], item['name'])
      b.add_id(:factual, item['factual_id'])
      b.add_categories(:factual, item['category'].split(",").map(&:strip))
      b.phone = item['tel'].gsub(/[\ ()-]*/, '')
      b.city = item['locality']
      b.country = item['country']
      b.zip = item['postcode']
      b.address = item['address']
      b
    end
  end

  class GooglePlacesConnector < Connector
    def initialize(config)
      @client = GooglePlaces::Client.new(config[:key])
    end

    def search_location(location, query)
      location = geocode(location) if location.is_a? String
      results = @client.spots(location[0], location[1], :name => query)
      results.map { |item| make_business(item) }
    end

    def make_business(item)
      b = Business.new(item.lat, item.lng, item.name)
      b.add_id(:google_places, item.id)
      b.add_categories(:google_places, item.types)
      b.phone = (item.formatted_phone_number || "").gsub(/[\ ()-]*/, '')
      b.city = item.city || item.vicinity.split(',').last
      b.country = item.country
      b.zip = item.postal_code
      b.address = item.vicinity.split(',').first
      b.add_rating(:google_places, item.rating)
      b
    end
  end

  class FourSquareConnector < Connector
    def initialize(config)
      @client = Foursquare2::Client.new(config)
    end

    def search_location(location, query)
      if location.is_a? Array
        results = @client.search_venues(:ll => location.join(","), :query => query)
      else
        results = @client.search_venues(:near => location, :query => query)
      end
      results['groups'].first['items'].map { |item| make_business(item) }
    end

    def make_business(item)
      b = Business.new(item['location']['lat'], item['location']['lng'], item['name'])
      b.add_id(:foursquare, item['id'])
      categories = item.categories.map { |c| [ c.name ] + c.parents }.flatten
      b.add_categories(:foursquare, categories)
      b.phone = item['contact'].fetch('phone', '').gsub(/[\ ()-]*/, '')
      b.twitter = item['contact'].fetch('twitter', nil)
      b.state = item['location']['state']
      b.city = item['location']['city']
      b.country = item['location']['cc']
      b.address = item['location']['address']
      b.add_checkins(:foursquare, item['stats']['checkinsCount'])
      b.add_users(:foursquare, item['stats']['usersCount'])
      b
    end
  end

  class YelpConnector < Connector
    def initialize(config)
      @config = config
      @client = Yelp::Client.new
    end

    def search_location(location, query)
      # while yelp does support searching by address, it does so much more shittily w/o lat/lon
      location = geocode(location) if location.is_a? String
      config = { :term => query, :latitude => location.first, :longitude => location.last }
      result = @client.search Yelp::V2::Search::Request::GeoPoint.new(config.merge(@config)) 
      result['businesses'].map { |item| 
        make_business(item) 
      }
    end

    def make_business(item)
      b = Business.new(item['location']['coordinate']['latitude'], item['location']['coordinate']['longitude'], item['name'])
      b.add_id(:yelp, item['id'])
      b.add_categories(:yelp, item['categories'].map(&:first))
      b.state = item['location']['state_code']
      b.zip = item['location']['postal_code']
      b.country = item['location']['country_code']
      b.city = item['location']['city']
      b.address = item['location']['address'].first
      b.phone = (item['phone'] || "").gsub(/[\ ()-]*/, '')
      b.add_rating(:yelp, item['rating'])
      b.add_review_counts(:yelp, item['review_count'])
      b
    end
  end

  class Finder
    def initialize(config)
      @connectors = config.map { |key, value| 
        case key
        when :foursquare then FourSquareConnector.new(value)
        when :yelp then YelpConnector.new(value)
        when :google_places then GooglePlacesConnector.new(value)
        when :factual then FactualConnector.new(value)
        else raise "No such connector found: #{key}"
        end
      }
    end

    # Search for a business (or business category) near lat/lon coordinates.  The 
    # location parameter should be either an address string or an array consisting of
    # [ lat, lon ].
    def search_location(location, query)
      merge @connectors.map { |c|
        c.search_location(location, query)
      }
    end

    # Search a location (just like search_location) but only return the best
    # matching business (based on name).
    def search_location_strictly(location, name)
      search_location(location, name).inject(nil) { |a,b|
        (a.nil? or b.name_distance_to(name) < a.name_distance_to(name)) ? b : a
      }
    end

    private
    def merge(lists)
      lists.inject([]) { |o,t| merge_lists(o, t) }
    end
    
    def merge_lists(one, two)
      one.map { |first|
        result = first
        two.map! { |second|
          if first == second
            result = first.merge(second)
            nil
          else
            second
          end
        }
        result
      } + two.select { |s| not s.nil? }
    end
  end

end
