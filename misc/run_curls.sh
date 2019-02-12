#!/bin/sh

sleep_seconds="${1:-1}"
num_curl="${2:-4}"

job_pid_list=''

run_curl() {
  (
    while true; do
      curl --silent -- "$1"/ >/dev/null
    done
  ) &
  job_pid_list="${job_pid_list} $!"
  echo "run curl $!"
}

cmd() {
  echo "$*"
  "$@"
}

echo "GET URL: ${GET_URL:=http://localhost:8080}"

for i in $(yes | head -"${num_curl}"); do
  run_curl "${GET_URL}"
done

cmd sleep "${sleep_seconds}"

for pid in $job_pid_list; do
  cmd kill "${pid}"
  wait "${pid}"
done
