#! /usr/bin/bash

debug=false

pyrpl_out_dir="/home/npeschke/gitRepos/pyrpl/pyrpl/fpga"
bitfile="red_pitaya.bin"

source_path="${pyrpl_out_dir}/${bitfile}"

modification_date="$(date --iso-8601="seconds" -r ${source_path})"

host="xchm"
destination_path="/root/bitstreams/${modification_date}_${bitfile}"

ssh ${host} "mkdir -p /root/bitstreams"

scp ${source_path} ${host}:${destination_path}

ssh ${host} "cat ${destination_path} > /dev/xdevcfg"
