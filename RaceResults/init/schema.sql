/* Table and Field standards: */
/*  Table names should be singular */
/*  Primary key: usually an integer labeled id */
/*  Foreign keys: referenced as fk_<TABLE>_<FIELD> */
/*  Typo tables: referenced as <TABLE>_alias, and have foreign key into <TABLE> */

PRAGMA foreign_keys = ON;
/* TODO: set collation on the DB as a whole? */

/* Table to store the units used in other tables, so we can handle multiple distance formats and time granulatrities */
/* NOTE: Static table, no updates while processing race results */
CREATE TABLE unit (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL COLLATE NOCASE CHECK(name != ''),
    abreviation TEXT
);
INSERT INTO unit (name, abreviation) VALUES ('Seconds', 'sec');
INSERT INTO unit (name) VALUES ('1/10th Seconds');
INSERT INTO unit (name) VALUES ('1/100th Seconds');
INSERT INTO unit (name, abreviation) VALUES ('Miles', 'mi');
INSERT INTO unit (name, abreviation) VALUES ('Kilometers', 'km');

/* What kind of race is the event? */
/* NOTE: Static table, no updates while processing race results */
CREATE TABLE race_type (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE COLLATE NOCASE CHECK(name != ''),
    abreviation TEXT
);
INSERT INTO race_type (name, abreviation) VALUES ('Time Trial', 'TT');
INSERT INTO race_type (name, abreviation) VALUES ('Team Time Trial', 'TTT');
INSERT INTO race_type (name) VALUES ('Road Race');
INSERT INTO race_type (name, abreviation) VALUES ('Criterium', 'Crit');
INSERT INTO race_type (name) VALUES ('Track');
INSERT INTO race_type (name) VALUES ('Grave Race');

/* List of teams */
CREATE TABLE team (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL COLLATE NOCASE DEFAULT 'Unattached' CHECK(name != ''),
    abreviation TEXT
);

/* Table to map team names to a merged entry */
/* NOTE: used in cases of typos and name changes */
/* TODO: Figure out a good method to determine between a typo of the team name vs a racer's team change */
CREATE TABLE team_alias (
    fk_team_id INTEGER NOT NULL,
    name TEXT NOT NULL COLLATE NOCASE CHECK(name != ''),

    /* Data Constraints */
    FOREIGN KEY(fk_team_id) REFERENCES team(id)
);

/* List of each individual racer */
/* TODO: Do we need to flag gender here? We are flagging age */
/* TODO: Handle racers having both a current virtual and IRL racing team */
CREATE TABLE racer (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    first_name TEXT NOT NULL COLLATE NOCASE CHECK(first_name != ''),
    last_name TEXT NOT NULL COLLATE NOCASE CHECK(last_name != ''),
    year_born INTEGER NOT NULL CHECK(year_born > 1900 AND year_born < 2100),
    fk_team_id INTEGER NOT NULL,                                                            /* Current Team */
    team_start_date DATE NOT NULL,                                                          /* First race we found with the current team listed */
    license_number INTEGER,                                                                 /* Is this needed? */
    license_current BOOLEAN DEFAULT False,                                                  /* And this? */

    /* Data Constraints */
    FOREIGN KEY(fk_team_id) REFERENCES team(id)
);

/* Table to map racer names to a merged entry */
/* NOTE: used in cases of typos and name changes */
CREATE TABLE racer_alias (
    fk_racer_id INTEGER NOT NULL,
    first_name TEXT NOT NULL COLLATE NOCASE CHECK(first_name != ''),
    last_name TEXT NOT NULL COLLATE NOCASE CHECK(last_name != ''),

    /* Data Constraints */
    PRIMARY KEY(first_name, last_name),
    FOREIGN KEY(fk_racer_id) REFERENCES racer(id)
);

/* Multiple to mutiple linking racers to former teams */
/* NOTE: No start_time as it would be equal to the end_time of a previous entry */
CREATE TABLE racer_former_team (
    fk_racer_id INTEGER NOT NULL,
    fk_team_id INTEGER NOT NULL,
    end_time DATETIME NOT NULL,                                                             /* Race date when the racer.fk_team_id field was updated */

    /* Data Constraints */
    UNIQUE(fk_racer_id, fk_team_id, end_time),                                              /* No duplicate rows */
    FOREIGN KEY(fk_racer_id) REFERENCES racer(id),
    FOREIGN KEY(fk_team_id) REFERENCES team(id)
);

/* The list of race categories */
/* NOTE: Static table, no updates while processing race results */
/* NOTE: The assumption here is all races of type X have the same set of categories, though not all categories need to be used per race (no entrants) */
/* NOTE: We support retired race categories with the use of the active field */
/* TODO: Do we need to flag handling age group categories, gender restricted ones, para */
CREATE TABLE race_category (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL NOT NULL COLLATE NOCASE CHECK(name != ''),                       /* Long form name that more likely used in the season series standings */
    abreviation TEXT COLLATE NOCASE,                                                    /* Short form name usually used on the race results */
    fk_race_type_id NOT NULL,
    active BOOLEAN DEFAULT True,

    /* Data Constraints */
    FOREIGN KEY(fk_race_type_id) REFERENCES race_type(id),
    UNIQUE(name, fk_race_type_id)
);

/* Same typo correction for race_category */
/* NOTE: Static table, no updates while processing race results */
CREATE TABLE race_category_alias (
    fk_race_category_id INTEGER NOT NULL,
    name TEXT NOT NULL COLLATE NOCASE CHECK(name != ''),

    /* Data Constraints */
    FOREIGN KEY(fk_race_category_id) REFERENCES race_category(id)
);

/* Table to list the points per finishing position */
/* NOTE: Static table, no updates while processing race results */
/* NOTE: We support having retired points calcuations */
CREATE TABLE race_points (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT UNIQUE NOT NULL NOT NULL COLLATE NOCASE CHECK(name != ''),
    places INTEGER NOT NULL CHECK(places >= 3),                                             /* How many places we go down */
    first INTEGER NOT NULL,                                                                 /* What points do 1st get */
    second INTEGER NOT NULL CHECK(second < first),                                          /* and 2nd? */
    third INTEGER NOT NULL CHECK(third < second),                                           /* and 3rd? */
    decrement INTEGER NOT NULL DEFAULT 1,                                                   /* How many points we go down for 4th to places */
    dnf INTEGER DEFAULT 0,                                                                  /* Do we award points for a do not finish? (NULL is no, any value is the number of points we give) */
    dns INTEGER DEFAULT NULL,                                                               /* Do we award points for a do not start (same rule as dnf) */
    active BOOLEAN DEFAULT True
);
INSERT INTO race_points (name, places, first, second, third) VALUES ('20 places', 20, 25, 22, 20);
INSERT INTO race_points (name, places, first, second, third) VALUES ('10 places', 10, 12, 10, 8);
INSERT INTO race_points (name, places, first, second, third, decrement) VALUES ('3 places', 3, 5, 3, 1, 0);

/* A mapping of each racer to their current (and past) categories */
/* Every racer could be in 2 or more active categories */
/* Active categories will be determined by having NULL in the upgrade_ent_time field */
/* TODO: some triggers/constraints on some of the values */
/*       Age group categories should never go down and never have 2 currently active age group categories (with the same bike) */
/*       Ability categories should also never go down, though this may change as racers age */
/*       Check that when upgrade_end_time is set, it is always > upgrade_time */
CREATE TABLE link_racer_race_category (
    fk_racer_id INTEGER NOT NULL,
    fk_race_category_id INTEGER NOT NULL,
    upgrade_time DATETIME NOT NULL,
    upgrade_end_time DATETIME,

    /* Data Constraints */
    PRIMARY KEY(fk_racer_id, fk_race_category_id),                                          /* Compound primary keys imply UNIQUE */
    FOREIGN KEY(fk_racer_id) REFERENCES racer(id),
    FOREIGN KEY(fk_race_category_id) REFERENCES race_category(id)
);

/* TODO: validate the fk_race_points_id is valid for the given fk_race_type_id */
CREATE TABLE event (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL COLLATE NOCASE CHECK(name != ''),
    event_date DATE NOT NULL CHECK(event_date REGEXP '^[12][0-9][0-9][0-9]-[01][0-9]-[0-3][0-9]$'),
    google_spreadsheet_id TEXT,                                                             /* Used in fetching the results data */
    fk_race_type_id INTEGER NOT NULL,                                                       /* This will determine which race_category are applicable */
    fk_race_points_id INTEGER NOT NULL,                                                     /* What calcuations this race is using for standings, FIXME: should be per race_category */

    /* Data Constraints */
    UNIQUE(name, event_date, fk_race_type_id)                                               /* The event can happen each year but we don't want 2 entries for the same instance */
    FOREIGN KEY(fk_race_type_id) REFERENCES race_type(id)
);

/* NOTE: A specific racer can have multiple results per event */
/* NOTE: In the Team TT case, we will have multiple rows, one for each member of the team (aka racer) */
/* TODO: Do we need to save the bib/race number? */
/* TODO: Do we need to flag distance here? */
/*       If the event.fk_race_type_id is a Team TT, then the fk_racer_race_category_id should be NOT NULL */
/*       Verify there are a max of 2 of the (fk_event_id, fk_racer_id) tuple */
CREATE TABLE result (
    id INTEGER PRIMARY KEY AUTOINCREMENT,                                                   /* Is this needed? */
    fk_event_id INTEGER NOT NULL,
    fk_racer_id INTEGER NOT NULL,
    fk_race_category_id INTEGER NOT NULL,                                                   /* This is the category for the race itself */
    fk_racer_race_category_id INTEGER,                                                      /* This is the category for the racer in the season standings */
    start_time TIME NOT NULL CHECK(start_time REGEXP '^([0-9]+:)?[0-5][0-9]:[0-5][0-9]$'),  /* Should we store as a timestamp? */
    duration INTEGER NOT NULL,
    fk_unit_id INTEGER NOT NULL,

    /* Data Constraints */
    UNIQUE(fk_event_id, fk_racer_id, fk_race_category_id),                                  /* Within each event, a racer can race twice but not in the same category */
    FOREIGN KEY(fk_racer_id) REFERENCES racer(id),
    FOREIGN KEY(fk_event_id) REFERENCES event(id),
    FOREIGN KEY(fk_race_category_id) REFERENCES race_category(id),
    FOREIGN KEY(fk_unit_id) REFERENCES unit(id)
);
