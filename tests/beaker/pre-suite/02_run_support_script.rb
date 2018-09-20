test_name 'PE-15434 - - Run Support Script' do
  hosts.each do |host|
    step "Run Support Script on #{host.name} : #{host['roles'].join(',')}" do
      result = on(host, puppet('enterprise support', 'ENV' => { 'BEAKER_TESTING' => '1' }))
      output_tarball = result.stdout.match(%r{^Support data is located at (.*)$}).captures.first

      stage_dir = create_tmpdir_on(host)
      # Using a pipeline accomodates SUN tar, which doesn't support the z flag
      # for unzipping tarballs or the -C flag when extracting.
      on(host, "cd #{stage_dir} && gunzip -c #{output_tarball}|tar xf -")

      # Save path to extracted data in host object so that tests can inspect it.
      host['support_script_output'] = File.join(stage_dir, File.basename(output_tarball, '.tar.gz'))
    end
  end
end
