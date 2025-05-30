#!/usr/bin/env ruby

require 'net/http'
require 'json'
require 'uri'
require 'mqtt'
require 'pp'

module Trompie
  extend self

  VERSION = %w'0 0 1-pre'

  def log(*args, prefix: " >")
    args.each { |a| $stdout.puts "#{prefix} #{a}" }
  end
  module_function :log

  def debug
    yield
  end

  def self.version
    VERSION.join(".")
  end

  def self.log_basedir
    debug { log "#{version} from #{$LOAD_PATH.first}" }
  end

  def self.setenv
    env_file = '/etc/nixos/res/hass_token.env'
    if(File.exist?(env_file))
      File.readlines(env_file).each do |line|
        next if line.strip.empty? || line.start_with?('#')
        key, value = line.strip.split('=', 2)
        if key && value
          ENV[key] = value
        end
      end
    end
    ENV["HASS_TOKEN"]
  end

  HASS_TOKEN = setenv
  abort "problems with token" unless HASS_TOKEN

  def self.do_with_synced_stdout(&blk)
    old_sync = $stdout.sync
    $stdout.sync = true
    blk.call
  ensure
    $stdout.sync = old_sync
  end

  class CFG
    DEFAULT_SETTINGS = {
      ha: "%s:443" % ENV["HASS_HOST"],
      mqtt: "192.168.1.3:1883"
    }


    HostDef = Struct.new(:host, :port) do
      def to_s
        "#{host}:#{port}"
      end

      def uri(*ads)
        base = "http%s://%s" % [(aport == 443 ? "s" : ""), host]
        [base].push(*ads).join("/")
      end
    end

    DEFAULT_SETTINGS.keys.each do |key|
      singleton_class.define_method("#{key}=") do |value|
        instance_variable_set("@#{key}", value)
      end

      singleton_class.define_method(key) do
        ret = instance_variable_get("@#{key}") || DEFAULT_SETTINGS[key]
        hs, port = ret.split(":")
        HostDef.new(hs, port.to_i)
      end
    end
  end


  class HA
    attr_reader :host

    def initialize(hoststruct = CFG.ha)
      @host = hoststruct
    end

    # make_req(:states, "sensor.temperature")
    def make_req(*args, basepath: "api")
      path = [basepath].push(*args)

      uri = URI(host.uri(*path))
      req = Net::HTTP::Get.new(uri)
      req['Authorization'] = "Bearer #{HASS_TOKEN}"
      req['Content-Type'] = 'application/json'

      Trompie.debug{ Trompie.log({ from: :ha, arget: uri.to_s }) }
      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
        http.request(req)
      end

      begin
        JSON.parse(res.body)
      rescue JSON::ParserError
        raise "invalid JSON from HA: #{res.code} #{res.body}"
      end
    end
  end


  class MMQTT
    attr_reader :host

    def initialize(hoststruct = CFG.mqtt)
      @host = hoststruct
    end

    def client
      @client ||= MQTT::Client.connect(host.host, host.port)
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

