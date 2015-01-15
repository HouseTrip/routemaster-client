require 'routemaster/topic'

describe Routemaster::Topic do

  let(:name)      { 'widgets' }
  let(:publisher) { 'demo' }
  let(:events)    { 0 }

  subject do
    described_class.new({
      "name"      => name,
      "publisher" => publisher,
      "events"    => events
    })
  end

  describe '#initialize' do

    it "creates an instance of #{described_class}" do
      expect(subject).to be_an_instance_of(described_class)
    end

  end

  describe '#attributes' do

    it "returns an hash with all attributes" do
      expect(subject.attributes).to eql({
        name: name,
        publisher: publisher,
        events: events
      })
    end

  end
end
