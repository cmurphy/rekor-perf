CREATE TABLE IF NOT EXISTS EntryIndex (
        PK BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        EntryKey varchar(512) NOT NULL,
        EntryUUID char(80) NOT NULL,
        PRIMARY KEY(PK),
        UNIQUE(EntryKey, EntryUUID)
);

LOAD DATA LOCAL INFILE './indices.csv'
INTO TABLE EntryIndex
FIELDS TERMINATED BY ','
LINES TERMINATED BY '\n' (EntryKey, EntryUUID);
