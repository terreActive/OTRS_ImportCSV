#!/bin/bash
#
# Example script using the OTRS console ImportCVS modules e.g. for a cron job.
# Note that order is important: import roles and users before role_user, and do on.
#
CMD=/opt/otrs/bin/otrs.Console.pl
OPTIONS=""  # "--verbose --dry-run"
SOURCE="--source-path /opt/otrs/var/import"

$CMD Admin::Group::ImportCSV $OPTIONS $SOURCE/groups.csv
$CMD Admin::Role::ImportCSV $OPTIONS $SOURCE/roles.csv
$CMD Admin::GroupRole::ImportCSV $OPTIONS $SOURCE/group_role.csv
$CMD Admin::Queue::ImportCSV $OPTIONS $SOURCE/queue.csv
$CMD Admin::User::ImportCSV $OPTIONS $SOURCE/users.csv
$CMD Admin::RoleUser::ImportCSV $OPTIONS $SOURCE/role_user.csv
$CMD Admin::CustomerCompany::ImportCSV $OPTIONS $SOURCE/customer_company.csv
$CMD Admin::CustomerGroup::ImportCSV $OPTIONS $SOURCE/customer_group.csv
$CMD Admin::CustomerUser::ImportCSV $OPTIONS $SOURCE/customer_user.csv
$CMD Admin::CustomerUserCustomer::ImportCSV $OPTIONS $SOURCE/customer_user_customer.csv
