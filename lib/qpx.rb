require "qpx/version"
require 'restclient'
require 'restclient/components'
require 'json'
require 'rack/cache'
require 'logger'
require 'nokogiri'
require 'moped'

module Qpx
  class Api

    RestClient.enable Rack::CommonLogger, STDOUT
    RestClient.enable Rack::Cache

    @@logger = Logger.new(STDOUT)
    @@logger.level = Logger::DEBUG
    @@logger.formatter = proc do |severity, datetime, progname, msg|
        "#{datetime}[QPX/#{progname}]- #{severity}: #{msg}\n"
    end
    # Configuration defaults
    @@config = {
      :server_api_keys => ['AIzaSyAGqlwSGMAOzmruUUQjrGI-O2VjJzWnxoc','AIzaSyBjULg8APtSAe8qVmiMKQbqJBnR5DMkuU8','AIzaSyADFCXgCV-TG3eIX8fA8TmQWdOgckkhz3E','AIzaSyBXSBWXFCik8w_HjGECO7BUsxk1vilyiRE','AIzaSyBBRqrad-v_VIOHijWyVihVJnN1ksZiOZs'] ,
      :base_headers => {content_type: :json, accept_encoding: :gzip, user_agent: :qpx_gem}, #, accept: :json
      :trips_url => 'https://www.googleapis.com/qpxExpress/v1/trips/search',
      :currencies_url => 'http://www.ecb.int/stats/eurofxref/eurofxref-daily.xml',
      :mongo_url => 'localhost:27017',
      :mongo_username => nil,
      :mongo_password => nil,
      :mongo_db_name => 'grappes_development',
      :mongo_currencies_coll => 'currencies',
      :mongo_airports_coll => 'airports',
      :mongo_airlines_coll => 'airlines',
      :mongo_travels_coll => 'travels',
      :mongo_server_apikeys_coll => 'server_apikeys',
      :airports_filepath => File.expand_path('../../data/airports.dat', __FILE__),
      :airlines_filepath => File.expand_path('../../data/airlines.dat', __FILE__),
      :place_availables_mean => 5,
      :max_solutions => 3
    }

    def self.config
      @@config
    end

    def self.logger
      @@logger
    end

    def initialize()
      puts "QPX Api Initialized"
    end


    ####################################### General Data Loading ####################################
    def self.loadCurrencies()
      return if @@config[:mongo_db][@@config[:mongo_currencies_coll]].find.count > 0
      @@logger.info("ReLoading Central European Bank Euro conversion rates.")
      response = RestClient.get @@config[:currencies_url]
      xml = Nokogiri::XML(response.body)

      xml.search('Cube/Cube/Cube').each do |currency|
        @@config[:mongo_db][@@config[:mongo_currencies_coll]].insert({currency: currency['currency'], rate: currency['rate']})
        #puts currency['currency'],currency['rate']
      end
      @@last_currencies_load_time = Time.new
    end

    def self.loadAirlinesData()
      return if @@config[:mongo_db][@@config[:mongo_airlines_coll]].find.count > 0
      @@logger.info("ReLoading Airlines Data.")
      File.open(@@config[:airlines_filepath], "r") do |f|
        f.each_line do |line|
          #id,name,alias,iata_code,icao_code,call_sign,country,active
          fields = line.split(',')
          @@config[:mongo_db][@@config[:mongo_airlines_coll]].insert({
             name:                fields[1].gsub('"',''),
             alias:               fields[2].gsub('"',''),
             iata_code:           fields[3].gsub('"',''),
             icao_code:           fields[4].gsub('"',''),
             call_sign:           fields[5].gsub('"',''),
             country:             fields[6].gsub('"',''),
             active:              fields[7].gsub('"','')
          })
        end
      end
    end


    def self.loadAirportsData()
      return if @@config[:mongo_db][@@config[:mongo_airports_coll]].find.count > 0
      @@logger.info("ReLoading Airports Data.")
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
             timezone:            fields[11].gsub('"',''),
             city_airport:            (fields[1].gsub('"','')=='All Airports')?1:0,
             first_class:         false
          }) unless fields[4].gsub('"','').lstrip =='' #avoid airport without iata code. its useless.
        end
      end
    end

    def self.loadServerApiKeys()
      return if @@config[:mongo_db][@@config[:mongo_server_apikeys_coll]].find.count > 0
      @@logger.info("ReLoading Server Api Keys")
      @@config[:server_api_keys].each do |apikey|
         @@config[:mongo_db][@@config[:mongo_server_apikeys_coll]].insert({
           key:             apikey,
           last_call_date:  Time.now.to_date.to_time ,
           day_api_calls:   0
         })
      end
    end


    def self.next_server_api_key()
      current_date = Time.now.to_date.to_time
      #Update previous days calls
      @@config[:mongo_db][@@config[:mongo_server_apikeys_coll]]
      .find({last_call_date:  {'$lt' => current_date}})
      .update({'$set' => {last_call_date: current_date, day_api_calls: 0}},{multi: true})
      # Get an available key
      next_key = @@config[:mongo_db][@@config[:mongo_server_apikeys_coll]]
      .find({day_api_calls:  {'$lt' => 50}})
      .modify({'$set' => {last_call_date: current_date}, '$inc' => {day_api_calls: 1}})

      if next_key.nil? or next_key.empty?
        @@logger.error("No available Api Keys found")
        nil
      else
        next_key['key']
      end
    end

    def self.euro_usd_rate
      loadCurrencies if (@@last_currencies_load_time.nil? or Time.new - @@last_currencies_load_time > 60*60*24)
      @@config[:mongo_db][@@config[:mongo_currencies_coll]].find({currency: 'USD'}).to_a[0]['rate'].to_f
    end




    ####################################### Configuration Helpers ####################################
    @valid_config_keys = @@config.keys

    # Configure through hash
    def self.configure(opts = {})
      opts.each { |k, v| @@config[k.to_sym] = v if @valid_config_keys.include? k.to_sym }

      @@config[:mongo_db] = session = Moped::Session.new([@@config[:mongo_url]])
      @@config[:mongo_db].use @@config[:mongo_db_name]
      #Mongo::Connection.new(@@config[:mongo_host], @@config[:mongo_port]).db(@@config[:mongo_db_name])
      @@config[:mongo_db].login(@@config[:mongo_username], @@config[:mongo_password]) unless @@config[:mongo_username].nil?
      @@config[:mongo_db][@@config[:mongo_travels_coll]].indexes.create({
        start_airport_code:  1,
        end_airport_code:    1,
        price:               1,
        departure:           1,
        arrival:             1,
        stopover:            1,
        company:             1 } ,
        { unique: true, dropDups: true, sparse: true })
      #@@config[:mongo_db].authenticate(@@config[:mongo_username], @@config[:mongo_password]) unless @@config[:mongo_username].nil?

      #Load general Data
      self.loadCurrencies
      self.loadAirlinesData
      self.loadAirportsData
      self.loadServerApiKeys
      'QPX is Configured and ready !'
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
    #self.configure


    ####################################### API Calls ####################################
    def self.search_trips(departure_code, arrival_code, outbound_date, inbound_date, adults_count,max_price=600)
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
          "solutions": #{@@config[:max_solutions]},
          "refundable": false
        }
      }
      !
      #@@logger.debug(json_post_body)
      begin
        response = RestClient.post(@@config[:trips_url], json_post_body, {
          params: {
            key: Qpx::Api.next_server_api_key,
            fields: 'trips/tripOption(saleTotal,slice(duration,segment))'
          }
        }.merge(@@config[:base_headers]))

        if (response.code == 200)
          #@@logger.debug(response.body)
          data = JSON.parse(response.body)
          self.parseResponse(data)
        end
      rescue Exception => e
        @@logger.error( e.message)
      end
    end



    def self.parseResponse(data)
      #@@logger.debug(data)
      unless data.nil? or data == {}
        #aircrafts = data['trips']['data']['aircraft']
        #taxes     = data['trips']['data']['tax']
        #carriers  = data['trips']['data']['carrier']
        #airports  = data['trips']['data']['airport']
        trips     = data['trips']['tripOption']
        @@logger.info "#{trips.count} trips found."
        trips.each do |trip|
          firstSegment          = trip['slice'].first['segment'].first
          lastSegment           = trip['slice'].last['segment'].last
          firstSliceLastSegment = trip['slice'].first['segment'].last
          firstLeg              = firstSegment['leg'].first
          lastLeg               = lastSegment['leg'].last
          firstSliceLastLeg     = firstSliceLastSegment['leg'].last
          start_airport_code    = firstLeg['origin']
          end_airport_code      = firstSliceLastLeg['destination']
          start_airport_data    = @@config[:mongo_db][@@config[:mongo_airports_coll]].find({iata_code: start_airport_code}).to_a[0]
          end_airport_data      = @@config[:mongo_db][@@config[:mongo_airports_coll]].find({iata_code: end_airport_code}).to_a[0]
          first_company         = @@config[:mongo_db][@@config[:mongo_airlines_coll]].find({iata_code: firstSegment['flight']['carrier']}).to_a[0]['name']
          begin
            @@config[:mongo_db][@@config[:mongo_travels_coll]].insert({
                      start_city: start_airport_data['city'],
                        end_city: end_airport_data['city'],
                     end_country: end_airport_data['country'],
                           price: trip['saleTotal'].sub('EUR','').to_f,#(trip['saleTotal'].sub('USD','').to_f/self.euro_usd_rate).round(2),
               places_availables: @@config[:place_availables_mean], # Use a mean
                           about: '', # Description on town
                       departure: Time.parse(firstLeg['departureTime']),
                         arrival: Time.parse(lastLeg['arrivalTime']),
                        stopover: trip['slice'].inject(0) {|sum, slice| sum + slice['segment'].length },
                         company: first_company,
                         lowcost: false,
                            type: 'air', # Evol
                   start_airport: start_airport_data['name'],
              start_airport_code: start_airport_code,
                end_airport_code: end_airport_code,
                     end_airport: end_airport_data['city'],
                     coordinates: self.city_top_airport(end_airport_data['city']).values_at('longitude','latitude'),
                           title: '', # Evol
                        prefered: false,
                        start_time: Time.parse(firstLeg['departureTime']).strftime('%H.%M').to_f, #conserve current grapy system
                        end_time: Time.parse(lastLeg['arrivalTime']).strftime('%H.%M').to_f,
                        duration: trip['slice'].inject(0) { |duration, d| duration + d['duration'] }, #Can be computed again from start_time and end_time
                     search_date: Time.now
                              })
          rescue Moped::Errors::OperationFailure => e
            @@logger.error('Insertion error. may be data is duplicated.')
          end
        end
      end
    end

    def self.multi_search_trips(departure_code, outbound_date, inbound_date, adults_count,max_price=600)
      @@logger.info "Searching from #{departure_code}"
      first_class_arrivals = @@config[:mongo_db][@@config[:mongo_airports_coll]].find(
        {first_class: true, iata_code: {'$nin' => [nil,'',departure_code]}}).select(iata_code: 1, _id: 0)
      first_class_arrivals.each do | first_class_arrival |
        puts "Searching #{departure_code} --> #{first_class_arrival['iata_code']} ..."
        self.search_trips(departure_code, first_class_arrival['iata_code'], outbound_date, inbound_date, adults_count,max_price)
      end
      "Done. #{first_class_arrivals.count} routes searched."
    end

    def self.multi_search_trips_by_city(departure_city, outbound_date, inbound_date, adults_count,max_price=600)
      top_airport = self.city_top_airport(departure_city)
      if top_airport.blank?
        @@logger.warn "No top airport found for city #{departure_city}; Will search all aiports."
        @@config[:mongo_db][@@config[:mongo_airports_coll]].find({city: city, iata_code: {'$nin' => [nil,'']}}).each do |city_airport|
          self.multi_search_trips( city_airport['iata_code'], outbound_date, inbound_date, adults_count,max_price)
        end
      else
        self.multi_search_trips( top_airport['iata_code'], outbound_date, inbound_date, adults_count,max_price)
      end
    end

    def self.city_top_airport(city)
      #@@config[:mongo_db][@@config[:mongo_airports_coll]].find({city: city,iata_code: {'$nin' => [nil,'']}}).sort({priority: -1}).limit(1).one
      @@config[:mongo_db][@@config[:mongo_airports_coll]].find({city: city, city_airport: 1, iata_code: {'$nin' => [nil,'']}}).limit(1).one
    end

  end
end
