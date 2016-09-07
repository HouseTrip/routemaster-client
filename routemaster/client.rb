require 'routemaster/client/version'
require 'routemaster/client/openssl'
require 'routemaster/topic'
require 'uri'
require 'faraday'
require 'json'

module Routemaster
  class Client
    def initialize(options = {})
      @_url = _assert_valid_url(options[:url])
      @_uuid = options[:uuid]
      @_timeout = options.fetch(:timeout, 1)

      _assert (options[:uuid] =~ /^[a-z0-9_-]{1,64}$/), 'uuid should be alpha'
      _assert_valid_timeout(@_timeout)

      unless options[:lazy]
        _conn.get('/pulse').tap do |response|
          raise 'cannot connect to bus' unless response.success?
        end
      end
    end

    def created(topic, callback, timestamp = nil)
      _send_event('create', topic, callback, timestamp)
    end

    def updated(topic, callback, timestamp = nil)
      _send_event('update', topic, callback, timestamp)
    end

    def deleted(topic, callback, timestamp = nil)
      _send_event('delete', topic, callback, timestamp)
    end

    def noop(topic, callback, timestamp = nil)
      _send_event('noop', topic, callback, timestamp)
    end

    def subscribe(options = {})
      if (options.keys - [:topics, :callback, :timeout, :max, :uuid]).any?
        raise ArgumentError.new('bad options')
      end
      _assert options[:topics].kind_of?(Enumerable), 'topics required'
      _assert options[:callback], 'callback required'
      _assert_valid_timeout options[:timeout] if options[:timeout]
      _assert_valid_max_events options[:max] if options[:max]

      options[:topics].each { |t| _assert_valid_topic(t) }
      _assert_valid_url(options[:callback])

      response = _post('/subscription') do |r|
        r.headers['Content-Type'] = 'application/json'
        r.body = options.to_json
      end

      unless response.success?
        raise 'subscribe rejected'
      end
    end

    def unsubscribe(*topics)
      topics.each { |t| _assert_valid_topic(t) }

      topics.each do |t|
        response = _delete("/subscriber/topics/#{t}")

        unless response.success?
          raise 'unsubscribe rejected'
        end
      end
    end

    def unsubscribe_all
      response = _delete('/subscriber')

      unless response.success?
        raise 'unsubscribe all rejected'
      end
    end

    def delete_topic(topic)
      _assert_valid_topic(topic)

      response = _delete("/topics/#{topic}")

      unless response.success?
        raise 'failed to delete topic'
      end
    end

    def monitor_topics
      response = _get('/topics') do |r|
        r.headers['Content-Type'] = 'application/json'
      end

      unless response.success?
        raise 'failed to connect to /topics'
      end

      JSON(response.body).map do |raw_topic|
        Topic.new raw_topic
      end
    end


    private

    def _assert_valid_timeout(timeout)
      _assert (0..3_600_000).include?(timeout), 'bad timeout'
    end

    def _assert_valid_max_events(max)
      _assert (0..10_000).include?(max), 'bad max # events'
    end

    def _assert_valid_url(url)
      uri = URI.parse(url)
      _assert (uri.scheme == 'https'), 'HTTPS required'
      return url
    end

    def _assert_valid_topic(topic)
      _assert (topic =~ /^[a-z_]{1,64}$/), 'bad topic name: must only include letters and underscores'
    end

    def _assert_valid_timestamp(timestamp)
      _assert timestamp.is_a?(Numeric), 'not a numeric number'
    end

    def _send_event(event, topic, callback, timestamp = nil)
      _assert_valid_url(callback)
      _assert_valid_topic(topic)
      _assert_valid_timestamp(timestamp) if timestamp

      data = { type: event, url: callback, timestamp: timestamp }

      response = _post("/topics/#{topic}") do |r|
        r.headers['Content-Type'] = 'application/json'
        r.body = data.to_json
      end
      fail "event rejected (#{response.status})" unless response.success?
    end

    def _assert(condition, message)
      condition or raise ArgumentError.new(message)
    end

    def _http(method, path, &block)
      retries ||= 5
      _conn.send(method, path, &block)
    rescue Net::HTTP::Persistent::Error => e
      raise if (retries -= 1).zero?
      puts "warning: retrying post to #{path} on #{e.class.name}: #{e.message} (#{retries})"
      @_conn = nil
      retry
    end

    def _post(path, &block)
      _http(:post, path, &block)
    end

    def _get(path, &block)
      _http(:get, path, &block)
    end

    def _delete(path, &block)
      _http(:delete, path, &block)
    end

    def _conn
      @_conn ||= Faraday.new(@_url) do |f|
        f.request :retry, max: 2, interval: 100e-3, backoff_factor: 2
        f.request :basic_auth, @_uuid, 'x'
        f.adapter :net_http_persistent

        f.options.timeout      = @_timeout
        f.options.open_timeout = @_timeout
      end
    end
  end
end
