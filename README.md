# Trompie

*This is considered not even an alpha. I dont recommend using it (yet).*

**Trompie** is a lightweight Ruby library that provides a fast and
minimal interface between scripts or automation tools and home
automation platforms like Home Assistant (HA) or MQTT-based systems.

It is built for simplicity and speed — ideal for quick scripts,
cronjobs, and integrations — without requiring the user to handle
authentication manually during usage.

## Features

- Easy access to the Home Assistant API  
- Native MQTT publish/subscribe support  
- Requires no manual authentication: uses environment variables or `.env`/`.secret` files  
- Minimal dependencies, suitable for embedded or CLI use cases

## Authentication

Trompie is designed to **just work** by loading tokens and credentials from the environment. It automatically reads from:

- `ENV["HASS_TOKEN"]`  
- A local file (e.g. `/etc/nixos/res/hass_token.env`) with key-value pairs  

No need to handle tokens in your code.

## Configuration

Override default targets via environment variables:

- `HASS_HOST` – the hostname or IP of your Home Assistant instance  
- MQTT configuration can be set via `Trompie::CFG.mqtt = "host:port"`

## Installation

Use directly as a library in your Ruby scripts. Not published on RubyGems yet.

Clone and `require_relative`, or install locally if needed.

## Example Usage

```ruby
require 'trompie'

ha = Trompie::HA.new
puts ha.make_req(:states, "sensor.temperature")

mqtt = Trompie::MMQTT.new
mqtt.publish("home/status") { { alive: true }.to_json }

mqtt.subscribe("home/command") do |payload|
  puts "Received command: #{payload.inspect}"
end


