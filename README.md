# SQL-Data-Migrations

MS SQL server data migration scripts

1. BLOB to PDF - Migrate BLOB pdf data saved in the Database to Filesystem while replacing the Target table PDF column with PDF file name.
2. BLOB to JPEG - Migrate BLOB jpeg data saved in the Database to Filesystem while replace the Target table JPEG column with JPEG file name.
3. Clean Customer DB - Clean customer database with single address line while identifying and separating single line address into multiple fields as building, street and city. This includes deletion of duplicate address entries and re-arranging foreign key relationships of data after removal.
