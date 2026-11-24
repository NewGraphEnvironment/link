# /code-check verdict (#501)

mode: branch
ended: enumeration
rounds: 4
inside-fix: yes
reviewed: 6b19bfde0ded4744d61049b4035910b1c83a2a48
set: the 38 places round 4's grep lists: every call of .lnk_measures_per_record, .lnk_presence_measures, .lnk_record_aliases and .lnk_record_aliases_everywhere, and every observation_key join or count in the files that read them; all safe once its two record counts were fixed
