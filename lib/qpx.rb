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
      :api_key => 'b2af842a51f01435cdb7',
      :base_headers => {content_type: :json, accept: :json},
    }

    @valid_config_keys = @@config.keys

    # Configure through hash
    def self.configure(opts = {})
      opts.each { |k, v| @@config[k.to_sym] = v if @valid_config_keys.include? k.to_sym }
      #@@config[:base_params] = {api_key: @@config[:api_key], ts_code: @@config[:ts_code], locale: @@config[:locale]}
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
    end

  end
end
