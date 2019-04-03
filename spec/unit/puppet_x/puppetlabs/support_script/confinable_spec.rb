require 'spec_helper'

describe PuppetX::Puppetlabs::SupportScript::Confinable do
  class ConfinedClass
    include PuppetX::Puppetlabs::SupportScript::Confinable

    attr_reader :confines

    def initialize
      initialize_confinable
    end
  end

  subject { ConfinedClass.new }
  let(:confine_class) { PuppetX::Puppetlabs::SupportScript::Confine }

  describe 'confining on facts' do
    it 'can add confines with a fact and a single value' do
      subject.confine :kernel => 'Linux'
    end

    it 'creates a PuppetX::Puppetlabs::SupportScript::Confine object for the confine call' do
      subject.confine :kernel => 'Linux'
      conf = subject.confines.first
      expect(conf).to be_a_kind_of(confine_class)
      expect(conf.fact).to eq :kernel
      expect(conf.values).to eq ['Linux']
    end
  end

  describe 'confining on blocks' do
    it 'can add a single fact with a block parameter' do
      subject.confine(:one) { true }
    end

    it 'creates a Util::Confine instance for the provided fact with block parameter' do
      block = lambda { true }
      expect(confine_class).to receive(:new).with('one')

      subject.confine('one', &block)
    end

    it 'should accept a single block parameter' do
      subject.confine() { true }
    end

    it 'should create a Util::Confine instance for the provided block parameter' do
      block = lambda { true }
      expect(confine_class).to receive(:new)

      subject.confine(&block)
    end
  end

  describe 'determining suitability' do
    it 'is true if all confines for the object evaluate to true' do
      subject.confine :kernel => 'Linux'
      subject.confine :operatingsystem => 'Redhat'

      subject.confines.each do |confine|
        allow(confine).to receive(:true?).and_return(true)
      end

      expect(subject).to be_suitable
    end

    it 'is false if any confines for the object evaluate to false' do
      subject.confine :kernel => 'Linux'
      subject.confine :operatingsystem => 'Redhat'

      allow(subject.confines.first).to receive(:true?).and_return(true)
      allow(subject.confines.first).to receive(:true?).and_return(false)

      expect(subject).to_not be_suitable
    end

    it 'recalculates suitability on every invocation' do
      subject.confine :kernel => 'Linux'

      allow(subject.confines.first).to receive(:true?).and_return(false)
      expect(subject).to_not be_suitable

      allow(subject.confines.first).to receive(:true?).and_call_original
      allow(subject.confines.first).to receive(:true?).and_return(true)
      expect(subject).to be_suitable
    end
  end
end
