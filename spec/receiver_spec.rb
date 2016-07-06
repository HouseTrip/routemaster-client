require 'spec_helper'
require 'rack/test'
require 'routemaster/receiver'

describe Routemaster::Receiver do
  include Rack::Test::Methods

  let(:handler) { double 'handler', on_events: nil, on_events_received: true }
  let(:app) { described_class.new(fake_app, options) }
  
  def perform
    post '/events', payload, 'CONTENT_TYPE' => 'application/json'
  end
  
  let(:options) do
    {
      path:     '/events',
      uuid:     'demo'
    }
  end

  class FakeApp
    def call(env)
      [501, {}, 'fake app']
    end
  end

  let(:fake_app) { FakeApp.new }
  
  let(:payload) do
    [{
      topic: 'widgets', event: 'created', url: 'https://example.com/widgets/1', t: 1234
    }, {
      topic: 'widgets', event: 'created', url: 'https://example.com/widgets/2', t: 1234 
    }, {
      topic: 'widgets', event: 'created', url: 'https://example.com/widgets/3', t: 1234 
    }].to_json
  end


  it 'passes with valid HTTP Basic' do
    authorize 'demo', 'x'
    perform
    expect(last_response.status).to eq(204)
  end

  it 'fails without authentication' do
    perform
    expect(last_response.status).to eq(401)
  end

  it 'delegates to the next middleware for unknown paths' do
    post '/foobar'
    expect(last_response.status).to eq(501)
  end

  it 'delegates to the next middlex for non-POST' do
    get '/events'
    expect(last_response.status).to eq(501)
  end

  context 'with the deprecated :handler option' do
    let(:options) {{
      path:     '/events',
      uuid:     'demo',
      handler:  handler
    }}

    it 'calls the handler when receiving an avent' do
      authorize 'demo', 'x'
      expect(handler).to receive(:on_events).exactly(:once)
      perform
    end

    it 'calls the handler multiple times' do
      authorize 'demo', 'x'
      expect(handler).to receive(:on_events).exactly(3).times
      3.times { perform }
    end
    
    it 'warns about deprecation' do
      expect_any_instance_of(described_class).to receive(:warn).with(/deprecated/)
      app
    end
  end

  context 'with a listener' do
    let(:handler) { double }
    before { Wisper.subscribe(handler, scope: 'Routemaster::Receiver', prefix: true) }
    after { Wisper::GlobalListeners.clear }

    it 'broadcasts :events_received' do
      authorize 'demo', 'x'

      expect(handler).to receive(:on_events_received).exactly(:once)
      # TODO:
      # we'll be able to say this with a more recent wisper (and skip the
      # handler):
      # expect(app).to publish_event(:events_received)
      perform
    end

    it 'can broadcast multiple times' do
      authorize 'demo', 'x'
      expect(handler).to receive(:on_events_received).exactly(3).times
      3.times { perform }
    end
  end
end
