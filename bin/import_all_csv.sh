#!/bin/bash
#
# (c) terreActive AG
#
# Purpose: import CSV files from inventory to OTRS in the correc order
#
# 3456789A123456789B123456789C123456789D123456789E123456789F123456789G12345678
#
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    echo usage:
    echo "$0" --help
    echo "$0"
    echo "$0" --verbose
    echo "$0" --dry-run
    echo "$0" --dry-run --verbose
    echo CSVDIR=/opt/Uploads "$0"
    echo CSVDIR=/opt/Uploads "$0" --verbose
    echo CSVDIR=/opt/Uploads "$0" --dry-run
    echo CSVDIR=/opt/Uploads "$0" --dry-run --verbose
    exit
fi

OPTIONS=("$@")
CMD=/opt/otrs/bin/otrs.Console.pl
CSVDIR=${CSVDIR-"/opt/Uploads"}

do_import() {
    echo $CMD "$1" "${OPTIONS[@]}" --source-path "$CSVDIR/$2"
    $CMD "$1" "${OPTIONS[@]}" --source-path "$CSVDIR/$2"
}

do_import Admin::Group::ImportCSV groups.csv
do_import Admin::Role::ImportCSV roles.csv
$CMD Maint::Cache::Delete
do_import Admin::GroupRole::ImportCSV group_role.csv
do_import Admin::Queue::ImportCSV queue.csv
do_import Admin::User::ImportCSV users.csv
$CMD Maint::Cache::Delete
do_import Admin::RoleUser::ImportCSV role_user.csv
do_import Admin::CustomerCompany::ImportCSV customer_company.csv
do_import Admin::CustomerGroup::ImportCSV customer_group.csv
do_import Admin::CustomerUser::ImportCSV customer_user.csv
do_import Admin::CustomerUserCustomer::ImportCSV customer_user_customer.csv
do_import Admin::Service::ImportCSV service.csv
$CMD Maint::Cache::Delete
do_import Admin::ServiceCustomerUser::ImportCSV service_customer_user.csv
#
# EOF
#
