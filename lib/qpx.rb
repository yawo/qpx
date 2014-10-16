require "qpx/version"
require 'restclient'
require 'restclient/components'
require 'json'
require 'rack/cache'
require 'logger'


module Qpx
  class Api

    RestClient.enable Rack::CommonLogger, STDOUT
    RestClient.enable Rack::Cache

    @@logger = Logger.new(STDOUT)
    @@logger.level = Logger::DEBUG

    # Configuration defaults
    @@config = {
      :browser_api_key =>'AIzaSyCLkbAPifQjnIkB1Xqc5xlKvHpOp-v2vlE',
      :server_api_key =>'AIzaSyAGqlwSGMAOzmruUUQjrGI-O2VjJzWnxoc' ,
      :base_headers => {content_type: :json, accept: :json},
    }

    @valid_config_keys = @@config.keys

    # Configure through hash
    def self.configure(opts = {})
      opts.each { |k, v| @@config[k.to_sym] = v if @valid_config_keys.include? k.to_sym }
      @@config[:trips_url] = 'https://www.googleapis.com/qpxExpress/v1/trips/search'
      @@config[:base_params] = {key: @@config[:server_api_key]}
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

    def search_trips(departure_code, arrival_code, outbound_date, inbound_date, adults_count)
      json_post_body = %Q!
      {
        "request": {
            "slice": [
                  {
                          "origin": "LAX",
                                  "destination": "NYC",
                                          "date": "2014-10-16"
                                                }
                                                    ],
                                                        "passengers": {
                                                              "adultCount": 1,
                                                                    "infantInLapCount": 0,
                                                                          "infantInSeatCount": 0,
                                                                                "childCount": 0,
                                                                                      "seniorCount": 0
                                                                                          },
                                                                                              "solutions": 20,
                                                                                                  "refundable": false
                                                                                                    }
                                                                                                    }
      !
      puts json_post_body
      response = RestClient.post(@@config[:trips_url], json_post_body, {params: @@config[:base_params]}.merge(@@config[:base_headers]))
    end

  end
end
