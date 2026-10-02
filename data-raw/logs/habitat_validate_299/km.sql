-- Stream km per species in the scratch mad run (ADMS on mad, config default).
SELECT h.species_code,
       round(sum(CASE WHEN h.spawning THEN s.length_metre ELSE 0 END)::numeric / 1000, 1) AS spawning_km,
       round(sum(CASE WHEN h.rearing THEN s.length_metre ELSE 0 END)::numeric / 1000, 1) AS rearing_km,
       round(sum(CASE WHEN h.wetland_rearing OR h.lake_rearing THEN s.length_metre ELSE 0 END)::numeric / 1000, 1) AS lake_wetland_rearing_km
  FROM (SELECT 'BT' AS species_code, * FROM zz299_mad.streams_habitat_bt
        UNION ALL SELECT 'CH', * FROM zz299_mad.streams_habitat_ch
        UNION ALL SELECT 'CO', * FROM zz299_mad.streams_habitat_co) h
  JOIN zz299_mad.streams s USING (id_segment, watershed_group_code)
 GROUP BY 1 ORDER BY 1;
