-- #429: do the two passability rows bcfishpass added on 2026-09-29 match a
-- dam either build reads? Run against local fwapg (link's builds) and the
-- bcfishpass reference database. Read-only.
--
--   298b0f7e-41d5-479a-95d7-af685224cf3f  Keogh River row
--   1c16395b-0411-4bad-bfc2-3445b1e94bcc  Adams row
--   242fa0e4-82ff-4ff6-9fa1-a2d892d4b41f  Keogh Dam in CABD, for contrast
SELECT 'cabd.dams' AS tbl, cabd_id::text AS id, dam_name_en,
       passability_status_code::text AS status
FROM cabd.dams
WHERE cabd_id::text IN ('298b0f7e-41d5-479a-95d7-af685224cf3f',
                        '1c16395b-0411-4bad-bfc2-3445b1e94bcc',
                        '242fa0e4-82ff-4ff6-9fa1-a2d892d4b41f')
ORDER BY id;
