use mysql;
SET sql_require_primary_key=0;
CREATE USER 'XXXXDB_UXXXX'@'%' IDENTIFIED BY 'XXXXDB_PXXXX' REQUIRE SSL;
flush privileges;

