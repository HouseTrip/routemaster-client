require 'sidekiq'

module Routemaster::Workers
  class Sidekiq
    @queue = :realtime

    class << self
      def configure(options)
        new(options)
      end
    end

    def initialize(options)
      @_options = options
    end

    def send_event(event, topic, callback, timestamp = nil)
      Job.perform_async(event, topic, callback, timestamp, @_options)
    end

    class Job
      include ::Sidekiq::Worker

      def perform(event, topic, callback, timestamp, options)
        conn = Routemaster::Client::Connection.new(_symbolize_keys(options))
        conn.send_event(event, topic, callback, timestamp)
      end

      private

      def _symbolize_keys(hash)
        Hash[hash.map{|(k,v)| [k.to_sym,v]}]
      end
    end

  end
end
