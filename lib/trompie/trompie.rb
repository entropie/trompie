#!/usr/bin/env ruby

require 'net/http'
require 'json'
require 'uri'
require 'mqtt'
require 'pp'
require 'tempfile'

module Trompie
  extend self

  VERSION  = %w'0 0 1-pre'

  ENV_FILE = '/etc/nixos/res/hass_token.env'.freeze

  ENV_VARIABLES = %w'HASS_TOKEN HASS_HOST MQTT_ENDPOINT'

  def log(*args, prefix: " >")
    args.each { |a| $stdout.puts "#{prefix} #{a}" }
  end
  module_function :log

  def self.debug?
    $debug || @debug || false
  end

  def self.debug=(bool)
    @debug = !!bool
  end

  def debug
    if $debug
      yield
    end
  end

  def info
    yield
  end

  def error(code: 1, prefix: "!>", **kwargs)
    $stdout.puts "#{prefix} #{kwargs.inspect}"
    exit 1
  end

  module_function :debug, :info, :error

  def self.version
    VERSION.join(".")
  end

  def self.log_basedir
    debug { log "#{version} from #{$LOAD_PATH.first}" }
  end

  def self.env_from_file(env_file = ENV_FILE)
    result = {  }
    if(File.exist?(env_file))
      File.readlines(env_file).each do |line|
        next if line.strip.empty? || line.start_with?('#')
        key, value = line.strip.split('=', 2)
        if key && value
          result[key] = value
        end
      end
    end
    result
  end

  def self.checkenv(env_file = ENV_FILE)
    # no need to check file since every ENV_VARIABLE is set
    return true if ENV_VARIABLES.map{ |ev| ENV[ev] }.compact.size == ENV_VARIABLES.size
    env_from_file = env_from_file(env_file)
    localenv = env_from_file.dup

    ENV_VARIABLES.each do |ev|
      localenv[ev] = ENV[ev] if ENV[ev]
    end
    localenv.each do |envk, envv|
      ENV[envk] = envv
    end

    localenv
  end

  checkenv

  abort "problems with token" unless ENV["HASS_TOKEN"]

  def self.do_with_synced_stdout(&blk)
    old_sync = $stdout.sync
    $stdout.sync = true
    blk.call
  ensure
    $stdout.sync = old_sync
  end

  class CFG
    def self.token
      ENV["HASS_TOKEN"]
    end

    def self.host
      ENV["HASS_HOST"]
    end

    def self.mqtt_endpoint
      ENV["MQTT_ENDPOINT"]
    end

    def self.mqtt_host
      mqtt_endpoint.split(":").first
    end

    def self.mqtt_port
      mqtt_endpoint.split(":").last
    end

    def self.uri(*ads)
      [host].push(*ads).join("/")
    end
  end

  module ResultEnhancer
    def self.extended(base)
      base.instance_eval do
        if self["state"] and self["attributes"]["unit_of_measurement"]
          self["state"] = "%s%s" % [ self["state"], self["attributes"]["unit_of_measurement"] ]
        end
      end

      def value
        self["value"] || self["state"]
      end

      def true?
        value == "True"
      end

      def false?
        !true?
      end
    end
  end

  class HA
    attr_reader :host

    def initialize(config = CFG)
      @config = config
    end

    def host
      @config.host
    end

    def make_result(res, raw: false, output_file: nil)
      result = {  }
      response =
        case res.content_type

        when "application/json"
          res = JSON.parse(res.body)

        when "image/jpeg"
          if output_file
            File.binwrite(output_file, res.body)
          else
            tf = Tempfile.new(%w[trompie_snapshot .jpg], binmode: true)
            tf.write(res.body)
            tf.rewind
            output_file = tf
          end
          if raw
            return tf.read
          end
          { output_file: tf }
        end
      result = result.merge(response)
      raw ? result : result.extend(ResultEnhancer)

    rescue JSON::ParserError
      raise "invalid JSON from HA: #{res.code} #{res.body}"
    end

    # make_req(:states, "sensor.temperature")
    def make_req(*args, from: :ha, basepath: "api", raw: false, output_file: nil)
      path = [basepath].push(*args)
      uri = URI(@config.uri(*path))

      req = Net::HTTP::Get.new(uri)

      req['Authorization'] = "Bearer #{@config.token}"
      req['Content-Type'] = 'application/json'

      Trompie.debug{ Trompie.log({type: :request, from: from, endpoint: uri.host, path: path.join("/")}) }

      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: (uri.scheme == 'https' || uri.port == 443)) do |http|
        http.request(req)
      end
      make_result(res, raw: raw, output_file: output_file)
      
    rescue SocketError => a
      Trompie.error(type: :error, from: :ha, uri: uri.path, message: $!.to_s)
    end
  end


  class MMQTT
    attr_reader :host

    def initialize(host = CFG.mqtt_host, port = CFG.mqtt_port)
      @host = host
      @port = port
    end

    def client
      @client ||= MQTT::Client.connect(@host, @port)
    end

    def submit(topic, payload, opts = {  })
      client.publish(topic, payload, opts)
    end

    def publish(topic, opts = {  })
      if block_given?
        payload = yield
        submit(topic, payload, opts)
        payload
      end
    end

    def subscribe(topic, parse_json = true)
      client.subscribe(topic)
      client.get do |topic, message|
        yield(parse_json ? JSON.parse(message) : message)
      end
    end
  end

end

