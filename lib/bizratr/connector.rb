require 'foursquare2'
require 'yelpster'
require 'levenshtein'
require 'google_places'

module BizRatr
  class Connector
    # https://api.foursquare.com/v2/venues/VENUE_ID/similar
    def search_similar(business)
      raise "Not implemented"
    end

    # https://developer.foursquare.com/docs/responses/venuestats
    def checkins(business)
      raise "Not implemented"
    end

    def search_location(ll, query)
      raise "Not implemented"
    end
  end

  class GooglePlacesConnector < Connector
    def initialize(config)
      @client = GooglePlaces::Client.new(config[:key])
    end

    def search_location(ll, query)
      coords = ll.split(',')
      results = @client.spots(coords[0].to_f, coords[1].to_f, :name => query)
      results.map { |item| make_business(item) }
    end

    def make_business(item)
      b = Business.new(item.lat, item.lng, item.name)
      b.add_id(:google_places, item.id)
      b.phone = item.formatted_phone_number
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

    def search_location(ll, query)
      results = @client.search_venues(:ll => ll, :query => query)
      results['groups'].first['items'].map { |item| make_business(item) }
    end

    def make_business(item)
      b = Business.new(item['location']['lat'], item['location']['lng'], item['name'])
      b.add_id(:foursquare, item['id'])
      b.phone = item['contact'].fetch('phone', nil)
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

    def search_location(ll, query)
      latlon = ll.split(',')
      config = { :term => query, :latitude => latlon.first, :longitude => latlon.last }
      result = @client.search Yelp::V2::Search::Request::GeoPoint.new(config.merge(@config)) 
      result['businesses'].map { |item| 
        make_business(item) 
      }
    end

    def make_business(item)
      b = Business.new(item['location']['coordinate']['latitude'], item['location']['coordinate']['longitude'], item['name'])
      b.add_id(:yelp, item['id'])
      b.state = item['location']['state_code']
      b.zip = item['location']['postal_code']
      b.country = item['location']['country_code']
      b.city = item['location']['city']
      b.address = item['location']['address'].first
      b.phone = item['phone']
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
        else raise "No such connector found: #{key}"
        end
      }
    end

    def search_location(ll, query)
      merge @connectors.map { |c|
        c.search_location(ll, query)
      }
    end

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
