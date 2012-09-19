require 'foursquare2'
require 'yelpster'
require 'levenshtein'
require 'google_places'
require 'geocoder'
require 'factual'
require 'koala'

module BizRatr
  class Connector
    def initialize(uberclient, config)
      @uberclient = uberclient
      @config = config
      @client = make_client(@config)
    end

    def make_client(config)
      raise "Not implemented"
    end

    def search_location(location, query)
      raise "Not implemented"
    end
  end

  class FacebookConnector < Connector
    def make_client(config)
      oauth = Koala::Facebook::OAuth.new(config[:key], config[:secret])
      Koala::Facebook::API.new(oauth.get_app_access_token)
    end

    def search_location(location, query)
      results = @client.search(query, { :type => 'place', :center => location.join(','), :distance => 1000 })
      results.map { |item|
        make_business(@client.get_object(item['id']))
      }
    end

    def make_business(item)
      b = Business.new(@uberclient, item['location']['latitude'], item['location']['longitude'], item['name'])
      b.add_id(:facebook, item['id'])
      b.city = item['location']['city']
      b.country = item['location']['country']
      b.phone = item['phone'] unless item['phone'] == "nope"
      b.zip = item['location']['zip']
      b.website = item['website'].split(' ').first
      b.address = item['location']['street']
      b.add_categories(:facebook, [item['category']])
      b.add_checkins(:facebook, item['checkins'] + item['were_here_count'])
      b.add_likes(:facebook, item['likes'])
      b
    end

    def get_url_likes(url)
      @client.fql_query("SELECT share_count, like_count, comment_count, click_count FROM link_stat WHERE url='#{url}'")
    end
  end

  class FactualConnector < Connector
    def make_client(config)
      Factual.new(config[:key], config[:secret])
    end

    def search_location(location, query)
      results = @client.table("places").filters("name" => query).geo("$circle" => { "$center" => location, "$meters" => 1000 })
      results.map { |item| make_business(item) }
    end

    def make_business(item)
      b = Business.new(@uberclient, item['latitude'], item['longitude'], item['name'])
      b.add_id(:factual, item['factual_id'])
      b.add_categories(:factual, item['category'].split(",").map(&:strip))
      b.phone = item['tel'].gsub(/[\ ()-]*/, '')
      b.website = item['website']
      b.city = item['locality']
      b.country = item['country']
      b.zip = item['postcode']
      b.address = item['address']
      b
    end
  end

  class GooglePlacesConnector < Connector
    def make_client(config)
      GooglePlaces::Client.new(config[:key])
    end

    def search_location(location, query)
      results = @client.spots(location[0], location[1], :name => query)
      results.map { |item| make_business(item) }
    end

    def make_business(item)
      b = Business.new(@uberclient, item.lat, item.lng, item.name)
      b.add_id(:google_places, item.id)
      b.add_categories(:google_places, item.types)
      b.phone = (item.formatted_phone_number || "").gsub(/[\ ()-]*/, '')
      b.city = item.city || item.vicinity.split(',').last
      b.country = item.country
      b.website = item.website
      b.zip = item.postal_code
      b.address = item.vicinity.split(',').first
      b.add_rating(:google_places, item.rating)
      b.add_review_counts(:google_places, item.reviews.length)
      b
    end
  end

  class FourSquareConnector < Connector
    def make_client(config)
      Foursquare2::Client.new(config)
    end

    def search_location(location, query)
      results = @client.search_venues(:ll => location.join(","), :query => query)
      results['groups'].first['items'].map { |item| make_business(item) }
    end

    def make_business(item)
      b = Business.new(@uberclient, item['location']['lat'], item['location']['lng'], item['name'])
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
      b.website = item['url']
      b.add_users(:foursquare, item['stats']['usersCount'])
      b
    end
  end

  class YelpConnector < Connector
    def make_client(config)
      Yelp::Client.new
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
      b = Business.new(@uberclient, item['location']['coordinate']['latitude'], item['location']['coordinate']['longitude'], item['name'])
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

  class UberClient
    def initialize(config)
      @connectors = {}
      config.each { |key, value| 
        @connectors[key] = case key
                           when :foursquare then FourSquareConnector.new(self, value)
                           when :yelp then YelpConnector.new(self, value)
                           when :google_places then GooglePlacesConnector.new(self, value)
                           when :factual then FactualConnector.new(self, value)
                           when :facebook then FacebookConnector.new(self, value)
                           else raise "No such connector found: #{key}"
                           end
      }
    end

    # Search for a business (or business category) near lat/lon coordinates.  The 
    # location parameter should be either an address string or an array consisting of
    # [ lat, lon ].
    def search_location(location, query)
      location = geocode(location) if location.is_a? String
      merge @connectors.values.map { |c|
        c.search_location(location, query)
      }
    end

    def geocode(address)
      Geocoder.coordinates(address)
    end

    def get_connector(key)
      @connectors.fetch(key, nil)
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
