These files are hand-made rows in the format of Rebrickable's CSV downloads
(https://rebrickable.com/downloads/), for tests. Data format from Rebrickable.com.

The files in downloads/ are plain CSV, so they can be read and changed. The
tests gzip them into a temporary folder, as Rebrickable serves them, before
reading. inventory_parts.csv has CR LF line ends on purpose.

members.csv.gz (two gzip members) and truncated.csv.gz (cut off in its header)
test the gzip reader, so they stay gzipped.
