#!/usr/bin/env bats

source "$BATS_TEST_DIRNAME/../tasks/functions/utility.sh"
source "$BATS_TEST_DIRNAME/../tasks/functions/govc.sh"

@test "buildIpath creates a vsphere inventory path when provided datacenter, folder, and vmname" {
    run buildIpath 'dc' 'folder' 'vmname'
    [ "$output" = "/dc/vm/folder/vmname" ]
}

@test "buildIpath creates a vsphere inventory path when provided datacenter and vmname" {
    run buildIpath 'dc' '' 'vmname'
    [ "$output" = "/dc/vm/vmname" ]
}

@test "buildIpath creates a vsphere inventory path when provided datacenter and folder" {
    run buildIpath 'dc' 'folder' ''
    [ "$output" = "/dc/vm/folder" ]
}

@test "buildIpath returns an error when provided datacenter but no folder or vmname" {
    run buildIpath 'dc' '' ''
    [ "$status" -eq 1 ]
}
