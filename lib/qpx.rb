require "qpx/version"
require 'restclient'
require 'restclient/components'
require 'json'
require 'rack/cache'
require 'logger'
require 'nokogiri'
require 'mongo'

module Qpx
  class Api

    RestClient.enable Rack::CommonLogger, STDOUT
    RestClient.enable Rack::Cache

    @@logger = Logger.new(STDOUT)
    @@logger.level = Logger::DEBUG

    # Configuration defaults
    @@config = {
      :browser_api_key => 'AIzaSyCLkbAPifQjnIkB1Xqc5xlKvHpOp-v2vlE',
      :server_api_key => 'AIzaSyAGqlwSGMAOzmruUUQjrGI-O2VjJzWnxoc' ,
      :base_headers => {content_type: :json, accept_encoding: :gzip, user_agent: :qpx_gem}, #, accept: :json
      :trips_url => 'https://www.googleapis.com/qpxExpress/v1/trips/search',
      :currencies_url => 'http://www.ecb.int/stats/eurofxref/eurofxref-daily.xml',
      :mongo_host => 'localhost',
      :mongo_port => '27017',
      :mongo_username => nil,
      :mongo_password => nil,
      :mongo_db_name => 'grappes_development',
      :mongo_currencies_coll => 'currencies',
      :mongo_airports_coll => 'airports',
      :airports_filepath => File.expand_path('../../data/airports.dat', __FILE__)
      
    }

    @valid_config_keys = @@config.keys

    # Configure through hash
    def self.configure(opts = {})
      opts.each { |k, v| @@config[k.to_sym] = v if @valid_config_keys.include? k.to_sym }
      @@config[:base_params] = {key: @@config[:server_api_key],
        #fields: 'trips/tripOption'
        fields: 'trips/tripOption(saleTotal,slice(duration,segment))'
      }
      @@config[:mongo_db] = Mongo::MongoClient.new(@@config[:mongo_host], @@config[:mongo_port]).db(@@config[:mongo_db_name])
      @@config[:mongo_db].authenticate(@@config[:mongo_username], @@config[:mongo_password]) unless @@config[:mongo_username].nil?
      
    end

    # Configure through yaml file
    def self.configure_with(path_to_yaml_file)
      begin
        config = YAML::load(IO.read(path_to_yaml_file))
      rescue Errno::ENOENT
        log(:warning, "YAML configuration file couldn't be found. Using defaults."); return
      rescue Psych::SyntaxError
        log(:warning, "YAML configuration file contains invalid syntax. Using defaults."); return
        configure(config)
      end
    end

    #Configure defaults
    self.configure

    def self.config
      @@config
    end

    def self.logger
      @@logger
    end

    def initialize()
      puts "QPX Api Initialized"
    end

    def search_trips(departure_code, arrival_code, outbound_date, inbound_date, adults_count,max_price=600)
      json_post_body = %Q!
      {
        "request": {
          "slice": [
            {
              "origin": "#{departure_code}",
              "destination": "#{arrival_code}",
              "date": "#{outbound_date.strftime('%Y-%m-%d')}"
            }
      !
      unless inbound_date.nil?
        json_post_body += %Q!
        ,{
          "destination": "#{departure_code}",
          "origin": "#{arrival_code}",
          "date": "#{inbound_date.strftime('%Y-%m-%d')}"
        }
        !
      end
      json_post_body += %Q!
           ],
          "passengers": {
            "adultCount": #{adults_count},
            "infantInLapCount": 0,
            "infantInSeatCount": 0,
            "childCount": 0,
            "seniorCount": 0
          },
          "maxPrice": "EUR#{max_price}",
          "saleCountry": "FR",
          "solutions": 2,
          "refundable": false
        }
      }
      !
      #@@logger.debug(json_post_body)
      response = RestClient.post(@@config[:trips_url], json_post_body, {params: @@config[:base_params]}.merge(@@config[:base_headers]))
      if (response.code == 200)
        #@@logger.debug(response.body)
        data = JSON.parse(response.body)
        parseResponse(data)
      end  
      
    end
    
    
=begin
    "start_city" : "Paris",
    "end_city" : "Casablanca",
    "end_country" : "Maroc",
    "price" : 200,
    "places_available" : 20,
    "about" : "about",
    "departure" : ISODate("2014-10-07T20:40:00.000Z"),
    "arrival" : ISODate("2014-10-07T21:40:00.000Z"),
    "stopover" : 1,
    "company" : "Easy Jet",
    "lowcost" : false,
    "type" : "",
    "start_airport" : "Paris Charles de Gaule",
    "start_airport_code" : "CDG",
    "end_airport_code" : "CMN",
    "end_airport" : "Casablanca",
    "coordinates" : [ 
        -7.589722, 
        33.367222
    ],
    "title" : "",
    "prefered" : false,
    "start_time" : null,
    "end_time" : null,
    "duration" : 100,
=end
    def euro_usd_rate
      loadCurrencies if (@last_currencies_load_time.nil? or Time.new - @last_currencies_load_time > 60*60*24)
      @@config[:mongo_db][@@config[:mongo_currencies_coll]].find({currency: 'USD'}).to_a[0]['rate'].to_f
    end
    
    
    def parseResponse(data)
      #@@logger.debug(data)
      unless data.nil? or data == {}
        
        #aircrafts = data['trips']['data']['aircraft']
        #taxes     = data['trips']['data']['tax']
        #carriers  = data['trips']['data']['carrier']
        #airports  = data['trips']['data']['airport']
        trips     = data['trips']['tripOption']
        trips.each do |trip|
          firstSegment = trip['slice'].first['segment'].first
          lastSegment = trip['slice'].last['segment'].last
          firstLeg = firstSegment['leg'].first
          lastLeg  = lastSegment['leg'].last
          start_airport_code  = firstLeg['origin']
          end_airport_code    = lastLeg['destination']
          start_airport_data  = @@config[:mongo_db][@@config[:mongo_airports_coll]].find({iata_code: start_airport_code}).to_a[0]
          end_airport_data  = @@config[:mongo_db][@@config[:mongo_airports_coll]].find({iata_code: end_airport_code}).to_a[0]
          grapyTrip = {
            start_city: start_airport_data['city'],  
            end_city: end_airport_data['city'],
            end_country: end_airport_data['country'], 
            price: trip['saleTotal'].sub('EUR','').to_f,#(trip['saleTotal'].sub('USD','').to_f/euro_usd_rate).round(2),
            places_availables:'',
            about:'',
            departure: Time.parse(firstLeg['departureTime']),
            arrival: Time.parse(lastLeg['arrivalTime']),
            stopover: trip['slice'].inject(0) {|sum, slice| sum + slice['segment'].length },
            company: firstSegment['flight']['carrier'],
            lowcost: false,
            type: '',
            start_airport: start_airport_data['name'],
            start_airport_code: start_airport_code,
            end_airport_code: end_airport_code,
            end_airport: end_airport_data['city'],
            coordinates: [end_airport_data['longitude'],end_airport_data['latitude']],
            title:'',
            prefered: false,# WHAT IS THIS ?
            start_time:'',
            end_time:'',
            duration: trip['slice'].inject(0) { |duration, d| duration + d['duration'] }
          }
          puts grapyTrip.inspect
        end
      end
      trips
    end
    
    def loadCurrencies()
      @@logger.info("Loading Central European Bank Euro conversion rates.")
      response = RestClient.get @@config[:currencies_url]
      xml = Nokogiri::XML(response.body)
      @@config[:mongo_db][@@config[:mongo_currencies_coll]].remove
      xml.search('Cube/Cube/Cube').each do |currency|
        @@config[:mongo_db][@@config[:mongo_currencies_coll]].insert({currency: currency['currency'], rate: currency['rate']})
        #puts currency['currency'],currency['rate']
      end
      @last_currencies_load_time = Time.new
    end

    def loadIATAData()
      File.open(@@config[:airports_filepath], "r") do |f|
        f.each_line do |line|
          #id,name,city,country,iataCode,icao,latitude,longitude,altitude,utc_timezone_offset,daily_save_time,timezone
          fields = line.split(',')
          @@config[:mongo_db][@@config[:mongo_airports_coll]].insert({
             name:                fields[1].gsub('"',''),
             city:                fields[2].gsub('"',''),
             country:             fields[3].gsub('"',''),
             iata_code:           fields[4].gsub('"',''),
             icao:                fields[5].gsub('"',''),
             latitude:            fields[6].to_f,
             longitude:           fields[7].to_f,
             altitude:            fields[8].to_f,
             utc_timezone_offset: fields[9].to_f,
             daily_save_time:     fields[10].gsub('"',''),
             timezone:            fields[11].gsub('"','')
          })
        end
      end
    end

  end
end
