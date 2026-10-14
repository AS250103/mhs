#!/bin/bash

show_log() {
    if [[ $1 == -f || $1 == follow ]]; then
        journalctl -u $is_core -f
    else
        journalctl -u $is_core -n 100 --no-pager
    fi
}