#!/usr/local/bin/sqlite3

.separator "\n"

/* SQL report showing the results of an event */
SELECT 
    event.name,
    /* FIXME: Seems %A nor %B work for strftime */
    /*strftime("%A %B %e, %Y", event.event_date)*/
    event.event_date
FROM event
WHERE event.id = %%event_id%%;

.mode box

SELECT
    format("%d:%2.2d:%2.2d.%2.2d", (result.duration / 3600 / 100), ((result.duration / 60 / 100) % 60), ((result.duration / 100.00) % 60), result.duration % 100.00) AS Duration,
    racer.first_name,
    racer.last_name,
    team.name AS 'Team Name',
    race_category.name AS 'Race Category'
FROM result,
    racer,
    race_category,
    team
WHERE result.fk_event_id = %%event_id%%
  AND result.fk_racer_id = racer.id
  AND result.fk_race_category_id = race_category.id
  AND racer.fk_team_id = team.id 
ORDER BY result.duration;
