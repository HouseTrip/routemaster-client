require 'routemaster/client/version'
require 'routemaster/client/connection'
require 'routemaster/topic'
require 'routemaster/workers'
require 'uri'
require 'json'
require 'faraday'
require 'typhoeus'
require 'typhoeus/adapters/faraday'
require 'oj'

module Routemaster
  class Client

    def initialize(options = {})
      @_options = options.tap do |o|
        o[:timeout] ||= 1
        o[:worker_type] ||= :null
      end

      _assert_valid_url(@_options[:url])
      _assert_valid_worker_type(@_options.fetch(:worker_type, :null))
      _assert (@_options[:uuid] =~ /^[a-z0-9_-]{1,64}$/), 'uuid should be alpha'
      _assert_valid_timeout(@_options[:timeout])

      @_worker_type = @_options.fetch(:worker_type)

      unless @_options[:lazy]
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
      _conn.subscribe(options)
    end

    def unsubscribe(*topics)
      topics.each { |t| _assert_valid_topic(t) }

      topics.each do |t|
        response = _conn.delete("/subscriber/topics/#{t}")

        unless response.success?
          raise 'unsubscribe rejected'
        end
      end
    end

    def unsubscribe_all
      response = _conn.delete('/subscriber')

      unless response.success?
        raise 'unsubscribe all rejected'
      end
    end

    def delete_topic(topic)
      _assert_valid_topic(topic)

      response = _conn.delete("/topics/#{topic}")

      unless response.success?
        raise 'failed to delete topic'
      end
    end

    def monitor_topics
      response = _conn.get('/topics') do |r|
        r.headers['Content-Type'] = 'application/json'
      end

      unless response.success?
        raise 'failed to connect to /topics'
      end

      Oj.load(response.body).map do |raw_topic|
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
      _assert timestamp.kind_of?(Integer), 'not an integer'
    end

    def _assert_valid_worker_type(worker_type)
      workers = Routemaster::Workers::WORKER_NAMES
      _assert workers.include?(worker_type), "unknown worker type, must be one of #{workers.map{ |w| ":#{w}" }.join(", ")}"
      worker_type
    end

    def _send_event(event, topic, callback, timestamp = nil)
      _assert_valid_url(callback)
      _assert_valid_topic(topic)
      _assert_valid_timestamp(timestamp) if timestamp
      _worker.send_event(event, topic, callback, timestamp)
    end

    def _assert(condition, message)
      condition or raise ArgumentError.new(message)
    end

    def _conn
      @_conn ||= Client::Connection.new(@_options)
    end

    def _worker
      @_worker ||= Routemaster::Workers::MAP[@_worker_type].configure(@_options)
    end
  end
end
