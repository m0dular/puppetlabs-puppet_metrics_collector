test_name 'Params' do
  step 'PE-20886 - - Test directory parameter' do
    hosts.each do |host|
      result = on(host, puppet('enterprise support --dir /tmp', 'ENV' => { 'BEAKER_TESTING' => '1' }))
      directory = result.stdout.match(%r{^Support data is located at (.*)\/puppet_enterprise_support}).captures.first
      assert_match(%r{\/tmp}, directory, 'Path should begin with /tmp as specified by --dir /tmp')
    end
  end

  step 'PE-19805 -- Test ticket parameter' do
    hosts.each do |host|
      result = on(host, puppet('enterprise support --ticket 12345', 'ENV' => { 'BEAKER_TESTING' => '1' }))
      ticket = result.stdout.match(%r{^Support data is located at \/var\/tmp\/puppet_enterprise_support_(.*)_}).captures.first
      assert_match(%r{12345}, ticket, 'Path should include 12345 as specified by --ticket 12345')
    end
  end

  step 'PE-2736 -- Test upload parameter' do
    hosts.each do |host|
      target = 'customer-support.puppetlabs.net'
      # customer-support.puppetlabs.net does not resolve internally.
      on(host, "echo '10.230.16.41 #{target}' >> /etc/hosts")
      result = on(host, puppet('enterprise support --ticket BEAKER_TESTING --v3 --scope system --upload'))
      server = result.stdout.match(%r{File uploaded to: (.*)}).captures.first
      assert_equal(server, target, "File should be uploaded to #{target} as specified by --upload")
    end
  end
end
