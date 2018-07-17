#!/bin/bash

# A small shell script that spawns a beaker test for each PE
# infrastructure platform, in parallel, then launches a
# webserver to display the test results. Defaults to testing
# the latest good LTS build, but can be directed at other
# release series by passing an X.Y version number
# as an argument:
#
#     ./ext/run_acceptance_tests.sh 2017.1

PE_TEST_SERIES=${1-"2017.3"}

if (( $(bc <<< "${PE_TEST_SERIES} > 2017.3") )); then
  TEST_MATRIX=('centos6-64mdca'
               'centos7-64mdca'
               'sles12-64mdca'
               'ubuntu1604-64mdca'
               'ubuntu1804-64mdca'
               'centos7-64am-64ad-64ac-64compile_master.af')
else
  TEST_MATRIX=('centos6-64mdca'
               'centos7-64mdca'
               'sles11-64mdca'
               'sles12-64mdca'
               'ubuntu1404-64mdca'
               'ubuntu1604-64mdca'
               'centos7-64am-64ad-64ac-64compile_master.af')
fi

LATEST_GOOD_BUILD=$(curl -q "http://getpe.delivery.puppetlabs.net/latest/${PE_TEST_SERIES}")
echo "Testing build: ${LATEST_GOOD_BUILD?}"

export BEAKER_PE_DIR="http://enterprise.delivery.puppetlabs.net/${PE_TEST_SERIES}/ci-ready/"
export BEAKER_PE_VER="${LATEST_GOOD_BUILD}"

execute_beaker() {
  # Changing preserve-hosts from "never" to "onfail" will leave VMs behind for debugging.
  bundle exec beaker \
    --preserve-hosts never \
    --config "$1" \
    --debug \
    --keyfile ~/.ssh/id_rsa-acceptance \
    --pre-suite tests/beaker/pre-suite \
    --tests tests/beaker/tests | \
  grep 'PE-' | while read line; do
    echo "${1}: ${line}"
  done
}

pids=""
for config in "${TEST_MATRIX[@]}"; do
  echo "Spawning test for: $(basename "${config}")"
  execute_beaker "${config}" &
  pids="${pids} $!"
done

for pid in ${pids};do
  wait "${pid}"
done

pushd junit &> /dev/null || exit 1
bundle exec ruby -run -e httpd -- --bind-address=127.0.0.1 --port=8000
