module Routemaster::Workers
  WORKER_NAMES = [:null, :sidekiq]

  WORKER_NAMES.each do |wn|
    autoload wn.to_s.capitalize.to_sym, "routemaster/workers/#{wn}"
  end

  MAP = {}.tap do |map|
    map.default_proc =  ->(hash, key) do
      class_name = key.to_s.capitalize
      hash[key] = self.const_get class_name
    end
  end
end
