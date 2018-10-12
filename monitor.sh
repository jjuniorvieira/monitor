#!/bin/sh
set -e
$(set -o pipefail 2> /dev/null) && set -o pipefail || {
  echo "\"set -o pipefail\" not supported!"
}

DEBUG=${DEBUG:-false}
$DEBUG && set -x || set +x

BASE_DIR=`cd "$(dirname "$0")"; pwd`
BASE_NAME=`basename "$BASE_DIR"`
GEN_DIR=generated
JAVA_HOME=${JAVA_HOME:-/JuniorsCIA/APIS/thirdparty/jdk/jdk-8u20-linux}
[ "$ip_addr" ] || {
  echo "ip_addr variable is not configured and will be !"
  exit 1
}

TAR=`dirname "$BASE_DIR"`/$BASE_NAME.$ip_addr.tar

export PATH=$JAVA_HOME/bin:$PATH

cd "$BASE_DIR"

mkdir -p $GEN_DIR

# TODO:
# 1) delete logs older than 2 days
# 2) create a script to analyse the $LOG

memory_status() {
  local datetime=`date +%F-%H%M%S`
  local log=$GEN_DIR/status.$datetime.log
  {
    echo "$ cat /proc/meminfo"
    cat /proc/meminfo
    echo -e "\n$ ./ps_mem.py"
    ./ps_mem.py
  } 2>&1 | tee $log
}

get_status() {
  local pid=$1
  local datetime=`date +%F-%H%M%S`
  local log=$GEN_DIR/$2-status.$datetime.log
  {
    echo "$ cat /proc/$pid/status"
    cat /proc/$pid/status
    echo -e "\n$ jstack $pid"
    jstack $pid
  } 2>&1 | tee $log
}

java_status() {
  jps -vvlm | \
  while read java_process
  do
    for s in "$@"
    do
      echo "$java_process" | grep -q $s && \
        get_status $(echo "$java_process" | cut -d" " -f1) $s || true
    done
  done
}

status() {
  memory_status
  java_status obif Standalone
}

disk_usage() {
  local usage
  usage=$(df -h / | grep '/dev/root' | awk '{ print $5 }')
  echo -n ${usage%?}
}

heapdump() {
  local process=$1
  local datetime=`date +%F-%H%M%S`
  local log=$GEN_DIR/heapdump.$datetime.log
  local heapdump
  local pid
  local cmd
  local disk_usage=`disk_usage`

  jps -vvlm | \
  while read java_process
  do
    if echo "$java_process" | grep -q $process
    then
      pid=$(echo "$java_process" | cut -d" " -f1)
      {
        heapdump=$GEN_DIR/$process.$datetime.hprof
        cmd="jmap -dump:file=$heapdump $pid"
        if [ "$disk_usage" -gt "80" ]
        then
          echo "Disk usage is greater than 80%. Removing heap dumps older than 6 hours ..."
          find . -name "$GEN_DIR/*.hprof" -type f -mmin +360 -delete
        fi
        echo "Running \"$cmd\""
        $cmd
        echo -e "Heap dump finished at `date +%F-%H%M%S`.\n"
      } 2>&1 | tee $log
    fi
  done
}

sync() {
  scp *.sh *.adoc *.xml *.excludes $1:$PWD/
}

save() {
  local excludes

  [ "$1" = "all" ] && excludes= || excludes="-X $BASE_NAME/save.excludes"
  echo "Saving $TAR ..."
  cd ..
  tar cf $TAR $excludes $BASE_NAME
  cd - > /dev/null
}

__crontab() {
  local datetime=`date +%F-%H%M%S`
  case "$1" in
    configure)
      echo "To configure crontab execute \"crontab -e\" and append the following lines:"
      echo "0,30 * * * * $BASE_DIR/monitor.sh status 2>&1 >/dev/null"
      echo "0 * * * * $BASE_DIR/monitor.sh heapdump 2>&1 >/dev/null"
      ;;
    test)
      echo "$datetime - Testing from crontab ..." >> $GEN_DIR/crontab.log
      ;;
    *)
      crontab -l | grep monitor || echo "monitor has no configuration on crontab!"
      ;;
  esac
}

main() {
  case "$1" in
    status)
      status
      ;;
    heapdump)
      heapdump Standalone
      ;;
    sync)
      shift
      [ "$1" ] || { echo "You must specify the peer IP ..."; exit 1; }
      sync "$@"
      ;;
    save)
      shift
      save "$@"
      ;;
    crontab)
      shift
      __crontab "$@"
      ;;
    *)
      echo "Usage: $0 <status|heapdump|sync|save|crontab>"
      ;;
  esac
}

main "$@"
