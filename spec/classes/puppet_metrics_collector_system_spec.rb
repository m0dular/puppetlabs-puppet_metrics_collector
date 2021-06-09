require 'spec_helper'

describe 'puppet_metrics_collector::system' do
  context 'when the virtual fact does not report vmware' do
    let(:facts) { { virtual: 'physical' } }

    it { is_expected.not_to contain_class('puppet_metrics_collector::system::vmware') }
  end

  context 'when the virtual fact reports vmware' do
    let(:facts) { { virtual: 'vmware' } }

    it { is_expected.to contain_class('puppet_metrics_collector::system::vmware') }
    it { is_expected.not_to contain_package('open-vm-tools') }

    context 'when management of VMware Tools is enabled' do
      let(:params) { { manage_vmware_tools: true, vmware_tools_pkg: 'foo-tools' } }

      it { is_expected.to contain_package('foo-tools').with_ensure('present') }
    end

    context 'when vmware-toolbox-cmd is present on the PATH' do
      let(:facts) { super().merge(puppet_metrics_collector: { have_vmware_tools: true, have_systemd: true }) }

      it { is_expected.to contain_service('pe_vmware-metrics.timer').with_ensure('running') }
    end

    context 'when vmware-toolbox-cmd is not present on the PATH' do
      let(:facts) { super().merge(puppet_metrics_collector: { have_vmware_tools: false, have_systemd: true }) }

      it { is_expected.to contain_notify('vmware_tools_warning') }
    end
  end

  context 'when /opt/puppetlabs/server/bin/psql is present' do
    let(:facts) { { puppet_metrics_collector: { have_pe_psql: true, have_systemd: true } } }

    it { is_expected.to contain_service('pe_postgres-metrics.timer').with_ensure('running') }
  end

  context 'when /opt/puppetlabs/server/bin/psql is absent' do
    let(:facts) { { puppet_metrics_collector: { have_pe_psql: false, have_systemd: true } } }

    it { is_expected.not_to contain_service('pe_postgres-metrics.timer') }
  end
end
