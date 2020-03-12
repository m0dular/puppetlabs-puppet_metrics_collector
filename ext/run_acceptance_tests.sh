#!/bin/bash

PE_TEST_SERIES="2018.1"
TEST_MATRIX=()
PRESERVE_BEHAVIOR="never"

print_usage() {
  cat <<-EOF
USAGE: ./run_acceptance_tests.sh [-h] [-p preserve] [-r pe_series] [-t hostspec]

A small shell script that spawns a beaker test for each PE
infrastructure platform, in parallel, then launches a
webserver to display the test results.

  -h  Print help.
  -p  Change whether or not hosts are detroyed after tests run.
      Default value is "never". Other values are:
        always onpass onfail
  -r  Release series of PE to test against as an X.Y string.
      Also accepts the string "master" to test against the
      very latest build.
      Default value is: ${PE_TEST_SERIES}
  -t  A beaker-hostgenerator string to run tests against.
      May be passed multiple times.

For example, to run tests against PE 2019.0, with monolithic installs of
CentOS 7 and Ubuntu 18.04, and to preserve hosts if tests fail:

./run_acceptance_tests.sh \\
  -p onfail \\
  -t centos7-64mdca -t ubuntu1804-mdca \\
  -r 2019.0

EOF
}

while getopts hp:r:t: flag; do
  case "${flag}" in
    h)
      print_usage
      exit 0
      ;;
    p)
      PRESERVE_BEHAVIOR="${OPTARG?}"
      ;;
    r)
      PE_TEST_SERIES="${OPTARG?}"
      ;;
    t)
      TEST_MATRIX+=("${OPTARG?}")
      ;;
    ?)
      print_usage
      exit 1
      ;;
  esac
done

if [[ "${#TEST_MATRIX[@]}" -eq 0 ]]; then
  TEST_MATRIX=('centos6-64mdca'
               'centos7-64mdca'
               'sles12-64mdca'
               'ubuntu1604-64mdca'
               'ubuntu1804-64mdca'
               'centos7-64am-64ad-64ac-64compile_master.af')
fi

build_url="https://artifactory.delivery.puppetlabs.net/artifactory/generic_enterprise__local/${PE_TEST_SERIES}/ci-ready/LATEST"
printf 'Reading latest good build from: %s\n' "${build_url}"

LATEST_GOOD_BUILD=$(curl -Ss "${build_url}")
printf "Testing build: %s\n" "${LATEST_GOOD_BUILD?}"

export BEAKER_PE_DIR="https://artifactory.delivery.puppetlabs.net/artifactory/generic_enterprise__local/${PE_TEST_SERIES}/ci-ready/"
export BEAKER_PE_VER="${LATEST_GOOD_BUILD}"

execute_beaker() {
  # Changing preserve-hosts from "never" to "onfail" will leave VMs behind for debugging.
  bundle exec beaker \
    --preserve-hosts "${PRESERVE_BEHAVIOR}" \
    --config "$1" \
    --debug \
    --keyfile ~/.ssh/id_rsa-acceptance \
    --pre-suite tests/beaker/pre-suite \
    --tests tests/beaker/tests | \
  grep 'PE-' | while read line; do
    printf '%s: %s\n' "${1}" "${line}"
  done
}

pids=()
for config in "${TEST_MATRIX[@]}"; do
  printf 'Spawning test for: %s\n' "${config}"
  execute_beaker "${config}" &
  pids+=("$!")
done

for pid in "${pids[@]}";do
  wait "${pid}"
done

pushd junit &> /dev/null || exit 1
bundle exec ruby -run -e httpd -- --bind-address=127.0.0.1 --port=8000
