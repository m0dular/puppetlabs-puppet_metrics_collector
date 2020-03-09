# pe_support_script

#### Table of Contents

1. [Module Description - What the module does and why it is useful](#module-description)
2. [Setup - The basics of getting started with pe_support_script](#setup)
3. [Usage - Configuration options and additional functionality](#usage)
4. [Reference - An under-the-hood peek at what the module is doing and how](#reference)
5. [Limitations - OS compatibility, etc.](#limitations)
6. [Development - Guide for contributing to the module](#development)


## Module Description

This module provides the `puppet enterprise support` face which is used
to gather a snapshot of PE configuration, log messages and other diagnostic
data that is essential to troubleshooting PE infrastructure.


## Setup

Place the pe_support_script module on the `$basemodulepath` of the
Master of Masters (MoM) in a PE installation. The module will then
be distributed to all PE nodes via pluginsync.

The configuration described above is produced by the PE Installer and
should only need to be done manually in non-production circumstances
such as acceptance tests.


## Usage

The support script is used by invoking the `puppet enterprise support`
subcommand as the `root` user. The script will print out a list of
data gathered and finishes by printing the location of a tarball
containing the output:

```
# /opt/puppetlabs/bin/puppet enterprise support
Puppet Enterprise Support Script v1.3.0
Creating drop directory at /var/tmp/puppet_enterprise_support_pe-201643-master_20170206144746
Collecting information

 ** Collecting output of: netstat -anptu

 ** Collecting output of: /usr/sbin/sestatus

...

Please submit /var/tmp/puppet_enterprise_support_pe-201643-master_20170206144746.tar.gz to Puppet Support using the upload site you've been invited to.
```


## Reference

The `puppet enterprise support` face operates by execcing a bash script
located at:

 - [lib/puppet_x/puppetlabs/support_script/v1/puppet-enterprise-support.sh](lib/puppet_x/puppetlabs/support_script/v1/puppet-enterprise-support.sh)

This script is laid out in three general sections:

  - Constants and utility functions.
  - Diagnostic functions that run diagnostics and collect data.
  - A main section which sets up the script output and runs a
    list of diagnostic functions.

The recommended approach for familiarizing yourself with the support
script code is to start at the end with the main section and then
search up for the implementation of diagnostic functions of interest.

The [docs/archive_layout.md](docs/archive_layout.md) file contains
an overview of the files included in support script output.


## Limitations

The `puppet enterprise support` command was developed to aid the
troubleshooting of PE infrastructure nodes --- MoMs, databases, consoles,
compile masters, MCollective hubs and spokes, etc. Therefore, this module
only supports Linux OS versions listed as "Puppet master platforms" for a
given PE release.

The list for the 2018.1 LTS series is at:

https://puppet.com/docs/pe/2018.1/supported_operating_systems.html#puppet-master-platforms

Support for troubleshooting Windows agents was added in v2.9.0 of the support
script which first shipped with PE 2018.1.5 and 2019.0.0.

## Development

The easiest way to contribute to the development of the PE Support Script
is to file tickets for bugs or improvements. Tickets should be filed
in the https://tickets.puppet.com/browse/PE tracker with the component
field set to "Support Script". The component bit is **very important** as
a Support Script ticket will just disappear into the JIRA backlog without it.

### Adding to the Script

The business end of the support script is currently implemented as a single
bash script as described in the [reference section](#reference). Diagnostics
can be extended by adding to the relevant bash functions and new diagnostics
can be added by creating new functions in the middle of the script and
adding a call to them into the main section at the end of the script.

Keep in mind the following guidelines when developing the support script:

  - Keep it safe. The script should default to read-only operations and
    should avoid collecting data that may contain sensitive information
    such as passwords or encryption keys. Running the support script
    should not modify a PE installation in any way beyond copying data
    to the output directory under `/var/tmp`.

  - New additions to the bash support script should follow the
    [Shell Style Guide][shell-guide] and pass a lint check administered by
    [Shellcheck][shellcheck].

  - Diagnostic functions should include guard statements that turn them
    into no-ops if required commands or data are missing. For example, the
    script shouldn't attempt diagnostics related to systemd if the `systemctl`
    command is not present. This keeps the script performant, and maximizes
    compatiblity accross OS versions and PE versions.

  - Structure your development work to produce a single commit per logical
    change. For example: if you extend an existing diagnostic, add a new
    diagnostic, and perform some stylistic cleanup, then each of those changes
    should be a separate commit.

  - Development should be done against the LTS branch of the support script
    unless functionality is being added that is only useful for newer PE
    versions.

[shell-guide]: https://google.github.io/styleguide/shell.xml
[shellcheck]: https://www.shellcheck.net/

### Testing

The support script is currently tested using a Beaker acceptance suite
which runs the script against a PE installation on each supported master
platform. ["Bash Strict Mode"][strict-mode] is enabled when the script is
run as part of an acceptance test. This extra layer of checking catches
the use of undeclared variables or diagnostic functions that are failing
due to incorrect input or missing guard statements.

To run the acceptance suite, first connect to the Puppet VPN as the test
suite makes use of several resources that are only available on the internal
network.

Next, use Bundler to install dependencies such as Beaker:

    bundle install --path=.bundle/lib

And ensure that a copy of the [acceptance testing key][acceptance-key]
is available at:

    ~/.ssh/id_rsa-acceptance

Then, execute the test helper under the `ext/` directory:

    ./ext/run_acceptance_tests.sh

The wrapper defaults to testing against the latest LTS nightly build.
Other PE builds can be tested by passing an X.Y version number to the helper:

    ./ext/run_acceptance_tests.sh 2019.1

The helper will launch parallel tests for every PE configuration described
by files in the tests/beaker/configs/ directory. Tests can take over ten
minutes to run, but when they've finished a Ruby webserver will be launched
to display the results:

    http://localhost:8000

[strict-mode]: http://redsymbol.net/articles/unofficial-bash-strict-mode/
[acceptance-key]: https://confluence.puppetlabs.com/display/QE/SSH+access+to+vmpooler+VMs
