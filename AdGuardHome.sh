#!/bin/sh

NAME="$(basename "$0")[$$]"
SCRIPT_LOC="/jffs/addons/AdGuardHome.d/AdGuardHome.sh"
UPPER_SCRIPT="/opt/etc/init.d/S99AdGuardHome"
LOWER_SCRIPT="/opt/etc/init.d/rc.func.AdGuardHome"

dnsmasq_params () {
  local CONFIG
  local COUNT
  local iCOUNT
  local dCOUNT
  local iVARS
  local IVARS
  local dVARS
  local DVARS
  local NIVARS
  local NDCARS
  local i 
  CONFIG="/etc/dnsmasq.conf"
  if [ "$(pidof "$PROCS")" ] && [ -z "$(nvram get ipv6_rtr_addr)" ]; then printf "%s\n" "port=553" "local=/$(nvram get lan_ipaddr | awk 'BEGIN{FS="."}{print $2"."$1".in-addr.arpa"}')/" "local=/10.in-addr.arpa/" "dhcp-option=lan,6,0.0.0.0" >> $CONFIG; fi
  if [ "$(pidof "$PROCS")" ] && [ -n "$(nvram get ipv6_rtr_addr)" ]; then printf "%s\n" "port=553" "local=/$(nvram get lan_ipaddr | awk 'BEGIN{FS="."}{print $2"."$1".in-addr.arpa"}')/" "local=/10.in-addr.arpa/" "local=/$(nvram get ipv6_prefix | sed "s/://g;s/^.*$/\n&\n/;tx;:x;s/\(\n.\)\(.*\)\(.\n\)/\3\2\1/;tx;s/\n//g;s/\(.\)/\1./g;s/$/ip6.arpa/")/" "dhcp-option=lan,6,0.0.0.0" >> $CONFIG; fi
  if [ -n "$(route | grep "br" | grep -v "br0" | grep -E "^(192\.168|10\.|172\.1[6789]\.|172\.2[0-9]\.|172\.3[01]\.)" | awk '{print $1}' | sed -e 's/[0-9]$/1/' | sed -e ':a; N; $!ba;s/\n/ /g')" ]; then
    iCOUNT="1"
    for iVARS in $(route | grep "br" | grep -v "br0" | grep -E "(192\.168|10\.|172\.1[6789]\.|172\.2[0-9]\.|172\.3[01]\.)" | awk '{print $8}' | sed -e ':a; N; $!ba;s/\n/ /g'); do
      [ "$iCOUNT" = "1" ] && COUNT="$iCOUNT" && IVARS="$iVARS"
      [ "$iCOUNT" != "1" ] && COUNT="$COUNT $iCOUNT" && IVARS="$IVARS $iVARS"
      iCOUNT="$((iCOUNT+1))"
    done
    dCOUNT="1"
    for dVARS in $(route | grep "br" | grep -v "br0" | grep -E "192\.168|10\.|172\.1[6789]\.|172\.2[0-9]\.|172\.3[01]\.)" | awk '{print $1}' | sed -e 's/[0-9]$/1/' | sed -e ':a; N; $!ba;s/\n/ /g'); do
      [ "$dCOUNT" = "1" ] && DVARS="$dVARS"
      [ "$dCOUNT" != "1" ] && DVARS="$DVARS $dVARS"
      dCOUNT="$((dCOUNT+1))"
    done
    for i in $COUNT; do
      NIVARS="$(printf "%s\n" "$IVARS" | cut -d' ' -f"$i")"
      NDVARS="$(printf "%s\n" "$DVARS" | cut -d' ' -f"$i")"
      if [ "$(pidof "$PROCS")" ]; then printf "%s\n" "dhcp-option=${NIVARS},6,${NDVARS}" >> $CONFIG; fi
    done
  fi
  if [ "$(pidof "$PROCS")" ] && [ "$(nvram get dns_local_cache)" != "1" ]; then umount /tmp/resolv.conf 2>/dev/null; mount -o bind /rom/etc/resolv.conf /tmp/resolv.conf; fi
}

lower_script () {
  case $1 in
    start|stop|restart|kill|check)
      $LOWER_SCRIPT_LOC $1 $NAME
      ;;
  esac
}

script_loc () {
  local UPPER_SCRIPT_LOC
  local LOWER_SCRIPT_LOC
  [ ! -f "$UPPER_SCRIPT" ] && return 1 || UPPER_SCRIPT_LOC=". $UPPER_SCRIPT"
  [ ! -f "$LOWER_SCRIPT" ] && return 1 || LOWER_SCRIPT_LOC=". $LOWER_SCRIPT"
  [ -z "$PROCS" ] && $UPPER_SCRIPT_LOC
}

start_AdGuardHome () {
  local NW_STATE
  local RES_STATE
  if [ -z "$(pidof "$PROCS")" ]; then lower_script start; else lower_script restart; fi
  if [ ! -f "/tmp/stats.db" ]; then ln -sf "${WORK_DIR}/data/stats.db" "/tmp/stats.db" >/dev/null 2>&1; fi
  if [ ! -f "/tmp/sessions.db" ]; then ln -sf "${WORK_DIR}/data/sessions.db" "/tmp/sessions.db" >/dev/null 2>&1; fi
  NW_STATE="$(ping 1.1.1.1 -c1 -W2 >/dev/null 2>&1; printf "%s" "$?")"
  RES_STATE="$(nslookup google.com 127.0.0.1 >/dev/null 2>&1; printf "%s" "$?")"
  while { [ "$NW_STATE" = "0" ] && [ "$RES_STATE" != "0" ]; }; do sleep 1; NW_STATE="$(ping 1.1.1.1 -c1 -W2 >/dev/null 2>&1; printf "%s" "$?")"; RES_STATE="$(nslookup google.com 127.0.0.1 >/dev/null 2>&1; printf "%s" "$?")"; done
  lower_script check
}

start_monitor () {
  trap "" 1 2 3 15
  while [ "$(nvram get ntp_ready)" -eq 0 ]; do sleep 1; done
  local NW_STATE
  local RES_STATE
  local COUNT
  COUNT=0
  while true; do
    if [ "$COUNT" -gt 90 ]; then
      COUNT=0
      timezone
    fi
    COUNT="$((COUNT + 1))"
    if [ -f "/opt/sbin/AdGuardHome" ]; then
      case $COUNT in
        "30"|"60"|"90")
          NW_STATE="$(ping 1.1.1.1 -c1 -W2 >/dev/null 2>&1; printf "%s" "$?")"
          RES_STATE="$(nslookup google.com 127.0.0.1 >/dev/null 2>&1; printf "%s" "$?")"
          ;;
      esac
      if [ -z "$(pidof "$PROCS")" ]; then
        logger -st "$NAME" "Warning: $PROCS is dead; $NAME will force-start it!"
        start_AdGuardHome
      elif { [ "$COUNT" -eq 30 ] || [ "$COUNT" -eq 60 ] || [ "$COUNT" -eq 90 ]; } && { [ "$NW_STATE" = "0" ] && [ "$RES_STATE" != "0" ]; }; then
        logger -st "$NAME" "Warning: $PROCS is not responding; $NAME will re-start it!"
        start_AdGuardHome
      fi
    fi
    sleep 10
  done
}

stop_AdGuardHome () {
  if [ -n "$(pidof "$PROCS")" ]; then lower_script stop; lower_script kill; service restart_dnsmasq >/dev/null 2>&1; else lower_script check; fi
  if [ -f "/tmp/stats.db" ]; then rm -rf "/tmp/stats.db" >/dev/null 2>&1; fi
  if [ -f "/tmp/sessions.db" ]; then rm -rf "/tmp/sessions.db" >/dev/null 2>&1; fi
}

timezone () {
  local SANITY
  local NOW
  local TIMEZONE
  local TARGET
  #local LINK
  SANITY="$(date -u -r "$SCRIPT_LOC" '+%s')"
  NOW="$(date -u '+%s')"
  TIMEZONE="/jffs/addons/AdGuardHome.d/localtime"
  TARGET="/etc/localtime"
  #LINK="$(readlink "$TARGET")"
  if [ -f "$TARGET" ]; then
      if [ "$NOW" -ge "$SANITY" ]; then
        touch "$SCRIPT_LOC"
      elif [ "$NOW" -le "$SANITY" ]; then
        date -u -s "$(date -u -r \"$SCRIPT_LOC\" '+%Y-%m-%d %H:%M:%S')"
      fi 
  elif [ -f "$TIMEZONE" ] || [ ! -f "$TARGET" ]; then
    ln -sf $TIMEZONE $TARGET
    timezone
  fi
}

unset TZ

case $1 in
  "start"|"restart")
    script_loc
    if [ "$?" = "0" ]; then "$UPPER_SCRIPT" monitor-start >/dev/null 2>&1; start_AdGuardHome; fi
    ;;
  "dnsmasq")
    script_loc
    [ "$?" = "0" ] && dnsmasq_params
    ;;
  "init-start"|"services-stop")
    [ "$1" = "init-start" ] && printf "1" > /proc/sys/vm/overcommit_memory
    timezone
    ;;
  "monitor-start")
    start_monitor &
    ;;
  "stop"|"kill")
    script_loc
    stop_AdGuardHome
    killall -q -9 $PROCS S99${PROCS} ${PROCS}.sh 2>/dev/null
    ;;
esac
