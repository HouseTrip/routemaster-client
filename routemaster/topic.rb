module Routemaster
  class Topic

    attr_reader :name, :publisher, :events

    def initialize(options)
      @name      = options.fetch('name')
      @publisher = options.fetch('publisher')
      @events    = options.fetch('events')
    end

    def attributes
      { name: @name, publisher: @publisher, events: @events }
    end

  end
end
