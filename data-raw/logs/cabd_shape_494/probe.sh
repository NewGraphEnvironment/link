# $1 = table; prints layout, types, ogc_fid stats, md5
q="SELECT string_agg(attname||':'||format_type(atttypid,atttypmod), ', ' ORDER BY attnum) FROM pg_attribute WHERE attrelid='$1'::regclass AND attnum>0 AND NOT attisdropped"
echo "cols: $(psql "$U" -At -c "$q" | cut -c1-160)..."
echo "pos(geom)=$(psql "$U" -At -c "SELECT attnum FROM pg_attribute WHERE attrelid='$1'::regclass AND attname='geom'") ncols=$(psql "$U" -At -c "SELECT count(*) FROM pg_attribute WHERE attrelid='$1'::regclass AND attnum>0 AND NOT attisdropped")"
echo "ogc_fid: $(psql "$U" -At -c "SELECT count(*)||' '||min(ogc_fid)||' '||max(ogc_fid) FROM $1")"
echo "md5: $(psql "$U" -At -c "SELECT md5(coalesce(string_agg(t::text, E'\n' ORDER BY t::text COLLATE \"C\"),'')) FROM $1 t")"
echo "typesig: $(psql "$U" -At -c "SELECT md5(string_agg(attname||':'||format_type(atttypid,atttypmod), ',' ORDER BY attnum)) FROM pg_attribute WHERE attrelid='$1'::regclass AND attnum>0 AND NOT attisdropped")"
