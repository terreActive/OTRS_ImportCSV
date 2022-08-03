#!/bin/bash
#
# Example script using the OTRS console ImportCVS modules e.g. for a cron job.
# Note that order is important: import roles and users before role_user, and do on.
#
CMD=/opt/otrs/bin/otrs.Console.pl
OPTIONS=""  # "--verbose --dry-run"
SOURCE="--source-path /opt/Uploads"

do_import() {
    echo $CMD $1 $OPTIONS $SOURCE/$2
    $CMD $1 $OPTIONS $SOURCE/$2
}

do_import Admin::Group::ImportCSV groups.csv
do_import Admin::Role::ImportCSV roles.csv
do_import Admin::GroupRole::ImportCSV group_role.csv
do_import Admin::Queue::ImportCSV queue.csv
do_import Admin::User::ImportCSV users.csv
do_import Admin::RoleUser::ImportCSV role_user.csv
do_import Admin::CustomerCompany::ImportCSV customer_company.csv
do_import Admin::CustomerGroup::ImportCSV customer_group.csv
do_import Admin::CustomerUser::ImportCSV customer_user.csv
do_import Admin::CustomerUserCustomer::ImportCSV customer_user_customer.csv
do_import Admin::Service::ImportCSV customer_user_customer.csv
do_import Admin::ServiceCustomerUser::ImportCSV customer_user_customer.csv
