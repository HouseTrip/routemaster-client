require 'delegate'
require 'set'

module Routemaster
  module Dirty
    # Locale prepresentation of the state of an entity.
    # - url (string): the entity's authoritative locator
    # - exists (boolean): whether it is know to exist or not
    # - t (datetime, UTC): when the state was last refreshed
    State = Struct.new(:url, :t) do
      KEY = 'dirtymap:state:%s'

      def self.get(redis, url)
        data = redis.get(KEY % url)
        return new(url, 0) if data.nil?
        Marshal.load(data)
      end

      def save(redis, expiry)
        data = Marshal.dump(self)
        redis.set(KEY % url, data, ex: expiry)
      end
    end
  end
end


