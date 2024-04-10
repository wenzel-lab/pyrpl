#! /usr/bin/bash

debug=false

pyrpl_out_dir="/home/npeschke/gitRepos/pyrpl/pyrpl/fpga"
bitfile="red_pitaya.bin"

source_path="${pyrpl_out_dir}/${bitfile}"

modification_date="$(date --iso-8601="seconds" -r ${source_path})"

host="pyrpl"
destination_path="/root/${modification_date}_${bitfile}"

scp ${source_path} ${host}:${destination_path}

ssh ${host} "cat ${destination_path} > /dev/xdevcfg"
