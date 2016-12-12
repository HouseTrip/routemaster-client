require 'forwardable'

# Internal class used by Routemaster::Client

module Routemaster
  class Client::Connection

    def initialize(options)
      @_url = options[:url]
      @_uuid = options[:uuid]
      @_timeout = options.fetch(:timeout, 1)
      @_verify_ssl = options.fetch(:verify_ssl, true)
    end

    def http(method, path, &block)
      _conn.send(method, path, &block)
    end

    def post(path, &block)
      http(:post, path, &block)
    end

    def get(path, &block)
      http(:get, path, &block)
    end

    def delete(path, &block)
      http(:delete, path, &block)
    end

    def send_event(event, topic, callback, timestamp = nil)
      data = { type: event, url: callback, timestamp: timestamp }

      response = post("/topics/#{topic}") do |r|
        r.headers['Content-Type'] = 'application/json'
        r.body = Oj.dump(_stringify_keys data)
      end
      fail "event rejected (#{response.status})" unless response.success?
    end

    def subscribe(options)
      response = post('/subscription') do |r|
        r.headers['Content-Type'] = 'application/json'
        r.body = Oj.dump(_stringify_keys options)
      end

      unless response.success?
        raise 'subscribe rejected'
      end
    end

    private

    def _stringify_keys(hash)
      hash.dup.tap do |h|
        h.keys.each do |k|
          h[k.to_s] = h.delete(k)
        end
      end
    end

    def _conn
      @_conn ||= Faraday.new(@_url, ssl: { verify: @_verify_ssl }) do |f|
        f.request :retry, max: 2, interval: 100e-3, backoff_factor: 2
        f.request :basic_auth, @_uuid, 'x'
        f.adapter :typhoeus

        f.options.timeout      = @_timeout
        f.options.open_timeout = @_timeout
      end
    end
  end
end
