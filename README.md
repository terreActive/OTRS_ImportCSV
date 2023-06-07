# ImportCSV - Provision OTRS database from CSV files

This OTRS/znuny Package allows for both, initial provisioning and
continuous updating of the OTRS database from an external
data source, namly:

* Agent Users
* Customer Users
* Customer Companies
* Groups
* Queues
* Roles
* ... and their relationships

The data are imported using the OTRS Perl API, without direct
Database access. This makes it independent of the DB schema.

See doc/en/ImportCSV.pod for documentation.
