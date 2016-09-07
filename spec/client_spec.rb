require 'spec_helper'
require 'routemaster/client'
require 'routemaster/topic'
require 'webmock/rspec'

describe Routemaster::Client do
  let(:options) do
    { url:  'https://bus.example.com', uuid: 'john_doe' }
  end
  let(:pulse_response) { 204 }

  subject { described_class.new(options) }

  before do
    @stub_pulse = stub_request(:get, %r{^https://bus.example.com/pulse$}).
      with(basic_auth: [options[:uuid], 'x']).
      to_return(status: pulse_response)
  end

  describe '#initialize' do
    it 'passes with valid arguments' do
      expect { subject }.not_to raise_error
    end

    it 'fails with a non-SSL URL' do
      options[:url].sub!(/https/, 'http')
      expect { subject }.to raise_error(ArgumentError)
    end

    it 'fails with a bad URL' do
      options[:url].replace('foobar')
      expect { subject }.to raise_error(ArgumentError)
    end

    it 'fails with a bad client id' do
      options[:uuid].replace('123 $%')
      expect { subject }.to raise_error(ArgumentError)
    end

    context 'when connection fails' do
      before do
        stub_request(:any, %r{^https://bus.example.com}).
          with(basic_auth: [options[:uuid], 'x']).
          to_raise(Faraday::ConnectionFailed)
      end

      it 'fails' do
        expect { subject }.to raise_error(Faraday::ConnectionFailed)
      end

      it 'passes if :lazy' do
        options[:lazy] = true
        expect { subject }.not_to raise_error
      end
    end

    context 'when the heartbeat fails' do
      let(:pulse_response) { 500 }

      it 'fails if it does not get a successful heartbeat from the app' do
        expect { subject }.to raise_error(RuntimeError)
      end
    end

    it 'fails if the timeout value is not an integer' do
      options[:timeout] = 'timeout'
      expect { subject }.to raise_error(ArgumentError)
    end
  end

  shared_examples 'an event sender' do
    let(:callback) { 'https://app.example.com/widgets/123' }
    let(:topic)    { 'widgets' }
    let(:perform)  { subject.send(event, topic, callback) }
    let(:http_status) { nil }

    before do
      @stub = stub_request(:post, 'https://bus.example.com/topics/widgets').
        with(basic_auth: [options[:uuid], 'x'])

      @stub.to_return(status: http_status) if http_status
    end

    context 'when the bus responds 200' do
      let(:http_status) { 200 }

      it 'sends the event' do
        perform
        expect(@stub).to have_been_requested
      end

      it 'sends a JSON payload' do
        @stub.with do |req|
          expect(req.headers['Content-Type']).to eq('application/json')
        end
        perform
      end

      it 'fails with a bad callback URL' do
        callback.replace 'http.foo.bar'
        expect { perform }.to raise_error(ArgumentError)
      end

      it 'fails with a non-SSL URL' do
        callback.replace 'http://example.com'
        expect { perform }.to raise_error(ArgumentError)
      end

      it 'fails with a bad topic name' do
        topic.replace 'foo123$bar'
        expect { perform }.to raise_error(ArgumentError, 'bad topic name: must only include letters and underscores')
      end
    end

    context 'when the bus responds 500' do
      let(:http_status) { 500 }

      it 'raises an exception' do
        expect { perform }.to raise_error(RuntimeError)
      end
    end

    context 'when the bus times out' do
      before { @stub.to_timeout }

      it 'fails' do
        @stub.to_timeout
        expect { perform }.to raise_error(Faraday::TimeoutError)
      end
    end

    context 'with explicit timestamp' do
      let(:timestamp) { Time.now.to_f }
      let(:perform)   { subject.send(event, topic, callback, timestamp) }

      before do
        @stub = stub_request(:post, 'https://@bus.example.com/topics/widgets').
          with(
            body: { type: anything, url: callback, timestamp: timestamp },
            basic_auth: [options[:uuid], 'x'],
          ).
          to_return(status: 200)
      end

      it 'sends the event' do
        perform
        expect(@stub).to have_been_requested
      end

      context 'with bad timestamp' do
        let(:timestamp) { 'foo' }

        it 'fails with non-numeric timestamp' do
          expect { perform }.to raise_error(ArgumentError)
        end
      end
    end
  end

  describe '#created' do
    let(:event) { 'created' }
    it_behaves_like 'an event sender'
  end

  describe '#updated' do
    let(:event) { 'updated' }
    it_behaves_like 'an event sender'
  end

  describe '#deleted' do
    let(:event) { 'deleted' }
    it_behaves_like 'an event sender'
  end

  describe '#noop' do
    let(:event) { 'noop' }
    it_behaves_like 'an event sender'
  end

  describe '#subscribe' do
    let(:perform) { subject.subscribe(subscribe_options) }
    let(:subscribe_options) {{
      topics:   %w(widgets kitten),
      callback: 'https://app.example.com/events',
      timeout:  60_000,
      max:      500
    }}

    before do
      @stub = stub_request(:post, 'https://bus.example.com/subscription').
      with(basic_auth: [options[:uuid], 'x']).
      with { |r|
        r.headers['Content-Type'] == 'application/json' &&
        JSON.parse(r.body).all? { |k,v| subscribe_options[k.to_sym] == v }
      }
    end

    it 'passes with correct arguments' do
      expect { perform }.not_to raise_error
      expect(@stub).to have_been_requested
    end

    it 'fails with a bad callback' do
      subscribe_options[:callback] = 'http://example.com'
      expect { perform }.to raise_error(ArgumentError)
    end

    it 'fails with a bad timeout' do
      subscribe_options[:timeout] = -5
      expect { perform }.to raise_error(ArgumentError)
    end

    it 'fails with a bad max number of events' do
      subscribe_options[:max] = 1_000_000
      expect { perform }.to raise_error(ArgumentError)
    end

    it 'fails with a bad topic list' do
      subscribe_options[:topics] = ['widgets', 'foo123$%bar']
      expect { perform }.to raise_error(ArgumentError)
    end

    it 'fails on HTTP error' do
      @stub.to_return(status: 500)
      expect { perform }.to raise_error(RuntimeError)
    end

    it 'accepts a uuid' do
      subscribe_options[:uuid] = 'hello'
      expect { perform }.not_to raise_error
    end
  end

  describe '#unsubscribe' do
    let(:perform) { subject.unsubscribe(*args) }
    let(:args) {[
      'widgets'
    ]}

    before do
      @stub = stub_request(:delete, %r{https://bus.example.com/subscriber/topics/widgets}).
      with(basic_auth: [options[:uuid], 'x'])
    end

    it 'passes with correct arguments' do
      expect { perform }.not_to raise_error
      expect(@stub).to have_been_requested
    end

    it 'fails with a bad topic' do
      args.replace ['foo123%bar']
      expect { perform }.to raise_error(ArgumentError)
    end

    it 'fails on HTTP error' do
      @stub.to_return(status: 500)
      expect { perform }.to raise_error(RuntimeError)
    end
  end


  describe '#unsubscribe_all' do
    let(:perform) { subject.unsubscribe_all }

    before do
      @stub = stub_request(:delete, %r{https://bus.example.com/subscriber}).
      with(basic_auth: [options[:uuid], 'x'])
    end

    it 'passes with correct arguments' do
      expect { perform }.not_to raise_error
      expect(@stub).to have_been_requested
    end

    it 'fails on HTTP error' do
      @stub.to_return(status: 500)
      expect { perform }.to raise_error(RuntimeError)
    end
  end

  describe '#delete_topic' do
    let(:perform) { subject.delete_topic(*args) }
    let(:args) {[
      'widgets'
    ]}

    before do
      @stub = stub_request(:delete, %r{https://bus.example.com/topics/widgets}).
      with(basic_auth: [options[:uuid], 'x'])
    end

    it 'passes with correct arguments' do
      expect { perform }.not_to raise_error
      expect(@stub).to have_been_requested
    end

    it 'fails with a bad topic' do
      args.replace ['foo123%bar']
      expect { perform }.to raise_error(ArgumentError)
    end

    it 'fails on HTTP error' do
      @stub.to_return(status: 500)
      expect { perform }.to raise_error(RuntimeError)
    end
  end


  describe '#monitor_topics' do

    let(:perform) { subject.monitor_topics }
    let(:expected_result) do
      [
        {
          name: 'widgets',
          publisher: 'demo',
          events: 12589
        }
      ]
    end

    before do
      @stub = stub_request(:get, 'https://bus.example.com/topics').
        with(basic_auth: [options[:uuid], 'x']).
        with { |r|
          r.headers['Content-Type'] == 'application/json'
        }.to_return {
          { status: 200, body: expected_result.to_json }
        }
    end

    it 'expects a collection of topics' do
      expect(perform.map(&:attributes)).to eql(expected_result)
    end
  end

  describe '#monitor_subscriptions' do
    it 'passes'
  end
end

