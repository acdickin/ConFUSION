toc.dat                                                                                             0000600 0004000 0002000 00000152761 12706517363 0014465 0                                                                                                    ustar 00postgres                        postgres                        0000000 0000000                                                                                                                                                                        PGDMP                            t        	   Comics_db    9.5.1    9.5.1 �    �           0    0    ENCODING    ENCODING        SET client_encoding = 'UTF8';
                       false         �           0    0 
   STDSTRINGS 
   STDSTRINGS     (   SET standard_conforming_strings = 'on';
                       false         �           1262    20579 	   Comics_db    DATABASE     �   CREATE DATABASE "Comics_db" WITH TEMPLATE = template0 ENCODING = 'UTF8' LC_COLLATE = 'English_United States.1252' LC_CTYPE = 'English_United States.1252';
    DROP DATABASE "Comics_db";
             Andrew    false                     2615    20880    pgagent    SCHEMA        CREATE SCHEMA pgagent;
    DROP SCHEMA pgagent;
             postgres    false         �           0    0    SCHEMA pgagent    COMMENT     6   COMMENT ON SCHEMA pgagent IS 'pgAgent system tables';
                  postgres    false    8                     2615    2200    public    SCHEMA        CREATE SCHEMA public;
    DROP SCHEMA public;
             postgres    false         �           0    0    SCHEMA public    COMMENT     6   COMMENT ON SCHEMA public IS 'standard public schema';
                  postgres    false    6         �           0    0    public    ACL     �   REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM postgres;
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO PUBLIC;
                  postgres    false    6                     3079    12355    plpgsql 	   EXTENSION     ?   CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;
    DROP EXTENSION plpgsql;
                  false         �           0    0    EXTENSION plpgsql    COMMENT     @   COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';
                       false    1         �            1255    21049    pga_exception_trigger()    FUNCTION     �  CREATE FUNCTION pga_exception_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE

    v_jobid int4 := 0;

BEGIN

     IF TG_OP = 'DELETE' THEN

        SELECT INTO v_jobid jscjobid FROM pgagent.pga_schedule WHERE jscid = OLD.jexscid;

        -- update pga_job from remaining schedules
        -- the actual calculation of jobnextrun will be performed in the trigger
        UPDATE pgagent.pga_job
           SET jobnextrun = NULL
         WHERE jobenabled AND jobid = v_jobid;
        RETURN OLD;
    ELSE

        SELECT INTO v_jobid jscjobid FROM pgagent.pga_schedule WHERE jscid = NEW.jexscid;

        UPDATE pgagent.pga_job
           SET jobnextrun = NULL
         WHERE jobenabled AND jobid = v_jobid;
        RETURN NEW;
    END IF;
END;
$$;
 /   DROP FUNCTION pgagent.pga_exception_trigger();
       pgagent       postgres    false    8    1         �           0    0     FUNCTION pga_exception_trigger()    COMMENT     p   COMMENT ON FUNCTION pga_exception_trigger() IS 'Update the job''s next run time whenever an exception changes';
            pgagent       postgres    false    222         �            1255    21044    pga_is_leap_year(smallint)    FUNCTION       CREATE FUNCTION pga_is_leap_year(smallint) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    AS $_$
BEGIN
    IF $1 % 4 != 0 THEN
        RETURN FALSE;
    END IF;

    IF $1 % 100 != 0 THEN
        RETURN TRUE;
    END IF;

    RETURN $1 % 400 = 0;
END;
$_$;
 2   DROP FUNCTION pgagent.pga_is_leap_year(smallint);
       pgagent       postgres    false    8    1         �           0    0 #   FUNCTION pga_is_leap_year(smallint)    COMMENT     W   COMMENT ON FUNCTION pga_is_leap_year(smallint) IS 'Returns TRUE if $1 is a leap year';
            pgagent       postgres    false    207         �            1255    21045    pga_job_trigger()    FUNCTION       CREATE FUNCTION pga_job_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.jobenabled THEN
        IF NEW.jobnextrun IS NULL THEN
             SELECT INTO NEW.jobnextrun
                    MIN(pgagent.pga_next_schedule(jscid, jscstart, jscend, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths))
               FROM pgagent.pga_schedule
              WHERE jscenabled AND jscjobid=OLD.jobid;
        END IF;
    ELSE
        NEW.jobnextrun := NULL;
    END IF;
    RETURN NEW;
END;
$$;
 )   DROP FUNCTION pgagent.pga_job_trigger();
       pgagent       postgres    false    8    1         �           0    0    FUNCTION pga_job_trigger()    COMMENT     M   COMMENT ON FUNCTION pga_job_trigger() IS 'Update the job''s next run time.';
            pgagent       postgres    false    208         �            1255    21042 �   pga_next_schedule(integer, timestamp with time zone, timestamp with time zone, boolean[], boolean[], boolean[], boolean[], boolean[])    FUNCTION     �8  CREATE FUNCTION pga_next_schedule(integer, timestamp with time zone, timestamp with time zone, boolean[], boolean[], boolean[], boolean[], boolean[]) RETURNS timestamp with time zone
    LANGUAGE plpgsql
    AS $_$
DECLARE
    jscid           ALIAS FOR $1;
    jscstart        ALIAS FOR $2;
    jscend          ALIAS FOR $3;
    jscminutes      ALIAS FOR $4;
    jschours        ALIAS FOR $5;
    jscweekdays     ALIAS FOR $6;
    jscmonthdays    ALIAS FOR $7;
    jscmonths       ALIAS FOR $8;

    nextrun         timestamp := '1970-01-01 00:00:00-00';
    runafter        timestamp := '1970-01-01 00:00:00-00';

    bingo            bool := FALSE;
    gotit            bool := FALSE;
    foundval        bool := FALSE;
    daytweak        bool := FALSE;
    minutetweak        bool := FALSE;

    i                int2 := 0;
    d                int2 := 0;

    nextminute        int2 := 0;
    nexthour        int2 := 0;
    nextday            int2 := 0;
    nextmonth       int2 := 0;
    nextyear        int2 := 0;


BEGIN
    -- No valid start date has been specified
    IF jscstart IS NULL THEN RETURN NULL; END IF;

    -- The schedule is past its end date
    IF jscend IS NOT NULL AND jscend < now() THEN RETURN NULL; END IF;

    -- Get the time to find the next run after. It will just be the later of
    -- now() + 1m and the start date for the time being, however, we might want to
    -- do more complex things using this value in the future.
    IF date_trunc('MINUTE', jscstart) > date_trunc('MINUTE', (now() + '1 Minute'::interval)) THEN
        runafter := date_trunc('MINUTE', jscstart);
    ELSE
        runafter := date_trunc('MINUTE', (now() + '1 Minute'::interval));
    END IF;

    --
    -- Enter a loop, generating next run timestamps until we find one
    -- that falls on the required weekday, and is not matched by an exception
    --

    WHILE bingo = FALSE LOOP

        --
        -- Get the next run year
        --
        nextyear := date_part('YEAR', runafter);

        --
        -- Get the next run month
        --
        nextmonth := date_part('MONTH', runafter);
        gotit := FALSE;
        FOR i IN (nextmonth) .. 12 LOOP
            IF jscmonths[i] = TRUE THEN
                nextmonth := i;
                gotit := TRUE;
                foundval := TRUE;
                EXIT;
            END IF;
        END LOOP;
        IF gotit = FALSE THEN
            FOR i IN 1 .. (nextmonth - 1) LOOP
                IF jscmonths[i] = TRUE THEN
                    nextmonth := i;

                    -- Wrap into next year
                    nextyear := nextyear + 1;
                    gotit := TRUE;
                    foundval := TRUE;
                    EXIT;
                END IF;
           END LOOP;
        END IF;

        --
        -- Get the next run day
        --
        -- If the year, or month have incremented, get the lowest day,
        -- otherwise look for the next day matching or after today.
        IF (nextyear > date_part('YEAR', runafter) OR nextmonth > date_part('MONTH', runafter)) THEN
            nextday := 1;
            FOR i IN 1 .. 32 LOOP
                IF jscmonthdays[i] = TRUE THEN
                    nextday := i;
                    foundval := TRUE;
                    EXIT;
                END IF;
            END LOOP;
        ELSE
            nextday := date_part('DAY', runafter);
            gotit := FALSE;
            FOR i IN nextday .. 32 LOOP
                IF jscmonthdays[i] = TRUE THEN
                    nextday := i;
                    gotit := TRUE;
                    foundval := TRUE;
                    EXIT;
                END IF;
            END LOOP;
            IF gotit = FALSE THEN
                FOR i IN 1 .. (nextday - 1) LOOP
                    IF jscmonthdays[i] = TRUE THEN
                        nextday := i;

                        -- Wrap into next month
                        IF nextmonth = 12 THEN
                            nextyear := nextyear + 1;
                            nextmonth := 1;
                        ELSE
                            nextmonth := nextmonth + 1;
                        END IF;
                        gotit := TRUE;
                        foundval := TRUE;
                        EXIT;
                    END IF;
                END LOOP;
            END IF;
        END IF;

        -- Was the last day flag selected?
        IF nextday = 32 THEN
            IF nextmonth = 1 THEN
                nextday := 31;
            ELSIF nextmonth = 2 THEN
                IF pgagent.pga_is_leap_year(nextyear) = TRUE THEN
                    nextday := 29;
                ELSE
                    nextday := 28;
                END IF;
            ELSIF nextmonth = 3 THEN
                nextday := 31;
            ELSIF nextmonth = 4 THEN
                nextday := 30;
            ELSIF nextmonth = 5 THEN
                nextday := 31;
            ELSIF nextmonth = 6 THEN
                nextday := 30;
            ELSIF nextmonth = 7 THEN
                nextday := 31;
            ELSIF nextmonth = 8 THEN
                nextday := 31;
            ELSIF nextmonth = 9 THEN
                nextday := 30;
            ELSIF nextmonth = 10 THEN
                nextday := 31;
            ELSIF nextmonth = 11 THEN
                nextday := 30;
            ELSIF nextmonth = 12 THEN
                nextday := 31;
            END IF;
        END IF;

        --
        -- Get the next run hour
        --
        -- If the year, month or day have incremented, get the lowest hour,
        -- otherwise look for the next hour matching or after the current one.
        IF (nextyear > date_part('YEAR', runafter) OR nextmonth > date_part('MONTH', runafter) OR nextday > date_part('DAY', runafter) OR daytweak = TRUE) THEN
            nexthour := 0;
            FOR i IN 1 .. 24 LOOP
                IF jschours[i] = TRUE THEN
                    nexthour := i - 1;
                    foundval := TRUE;
                    EXIT;
                END IF;
            END LOOP;
        ELSE
            nexthour := date_part('HOUR', runafter);
            gotit := FALSE;
            FOR i IN (nexthour + 1) .. 24 LOOP
                IF jschours[i] = TRUE THEN
                    nexthour := i - 1;
                    gotit := TRUE;
                    foundval := TRUE;
                    EXIT;
                END IF;
            END LOOP;
            IF gotit = FALSE THEN
                FOR i IN 1 .. nexthour LOOP
                    IF jschours[i] = TRUE THEN
                        nexthour := i - 1;

                        -- Wrap into next month
                        IF (nextmonth = 1 OR nextmonth = 3 OR nextmonth = 5 OR nextmonth = 7 OR nextmonth = 8 OR nextmonth = 10 OR nextmonth = 12) THEN
                            d = 31;
                        ELSIF (nextmonth = 4 OR nextmonth = 6 OR nextmonth = 9 OR nextmonth = 11) THEN
                            d = 30;
                        ELSE
                            IF pgagent.pga_is_leap_year(nextyear) = TRUE THEN
                                d := 29;
                            ELSE
                                d := 28;
                            END IF;
                        END IF;

                        IF nextday = d THEN
                            nextday := 1;
                            IF nextmonth = 12 THEN
                                nextyear := nextyear + 1;
                                nextmonth := 1;
                            ELSE
                                nextmonth := nextmonth + 1;
                            END IF;
                        ELSE
                            nextday := nextday + 1;
                        END IF;

                        gotit := TRUE;
                        foundval := TRUE;
                        EXIT;
                    END IF;
                END LOOP;
            END IF;
        END IF;

        --
        -- Get the next run minute
        --
        -- If the year, month day or hour have incremented, get the lowest minute,
        -- otherwise look for the next minute matching or after the current one.
        IF (nextyear > date_part('YEAR', runafter) OR nextmonth > date_part('MONTH', runafter) OR nextday > date_part('DAY', runafter) OR nexthour > date_part('HOUR', runafter) OR daytweak = TRUE) THEN
            nextminute := 0;
            IF minutetweak = TRUE THEN
        d := 1;
            ELSE
        d := date_part('YEAR', runafter)::int2;
            END IF;
            FOR i IN d .. 60 LOOP
                IF jscminutes[i] = TRUE THEN
                    nextminute := i - 1;
                    foundval := TRUE;
                    EXIT;
                END IF;
            END LOOP;
        ELSE
            nextminute := date_part('MINUTE', runafter);
            gotit := FALSE;
            FOR i IN (nextminute + 1) .. 60 LOOP
                IF jscminutes[i] = TRUE THEN
                    nextminute := i - 1;
                    gotit := TRUE;
                    foundval := TRUE;
                    EXIT;
                END IF;
            END LOOP;
            IF gotit = FALSE THEN
                FOR i IN 1 .. nextminute LOOP
                    IF jscminutes[i] = TRUE THEN
                        nextminute := i - 1;

                        -- Wrap into next hour
                        IF (nextmonth = 1 OR nextmonth = 3 OR nextmonth = 5 OR nextmonth = 7 OR nextmonth = 8 OR nextmonth = 10 OR nextmonth = 12) THEN
                            d = 31;
                        ELSIF (nextmonth = 4 OR nextmonth = 6 OR nextmonth = 9 OR nextmonth = 11) THEN
                            d = 30;
                        ELSE
                            IF pgagent.pga_is_leap_year(nextyear) = TRUE THEN
                                d := 29;
                            ELSE
                                d := 28;
                            END IF;
                        END IF;

                        IF nexthour = 23 THEN
                            nexthour = 0;
                            IF nextday = d THEN
                                nextday := 1;
                                IF nextmonth = 12 THEN
                                    nextyear := nextyear + 1;
                                    nextmonth := 1;
                                ELSE
                                    nextmonth := nextmonth + 1;
                                END IF;
                            ELSE
                                nextday := nextday + 1;
                            END IF;
                        ELSE
                            nexthour := nexthour + 1;
                        END IF;

                        gotit := TRUE;
                        foundval := TRUE;
                        EXIT;
                    END IF;
                END LOOP;
            END IF;
        END IF;

        -- Build the result, and check it is not the same as runafter - this may
        -- happen if all array entries are set to false. In this case, add a minute.

        nextrun := (nextyear::varchar || '-'::varchar || nextmonth::varchar || '-' || nextday::varchar || ' ' || nexthour::varchar || ':' || nextminute::varchar)::timestamptz;

        IF nextrun = runafter AND foundval = FALSE THEN
                nextrun := nextrun + INTERVAL '1 Minute';
        END IF;

        -- If the result is past the end date, exit.
        IF nextrun > jscend THEN
            RETURN NULL;
        END IF;

        -- Check to ensure that the nextrun time is actually still valid. Its
        -- possible that wrapped values may have carried the nextrun onto an
        -- invalid time or date.
        IF ((jscminutes = '{f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}' OR jscminutes[date_part('MINUTE', nextrun) + 1] = TRUE) AND
            (jschours = '{f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}' OR jschours[date_part('HOUR', nextrun) + 1] = TRUE) AND
            (jscmonthdays = '{f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}' OR jscmonthdays[date_part('DAY', nextrun)] = TRUE OR
            (jscmonthdays = '{f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,t}' AND
             ((date_part('MONTH', nextrun) IN (1,3,5,7,8,10,12) AND date_part('DAY', nextrun) = 31) OR
              (date_part('MONTH', nextrun) IN (4,6,9,11) AND date_part('DAY', nextrun) = 30) OR
              (date_part('MONTH', nextrun) = 2 AND ((pgagent.pga_is_leap_year(date_part('DAY', nextrun)::int2) AND date_part('DAY', nextrun) = 29) OR date_part('DAY', nextrun) = 28))))) AND
            (jscmonths = '{f,f,f,f,f,f,f,f,f,f,f,f}' OR jscmonths[date_part('MONTH', nextrun)] = TRUE)) THEN


            -- Now, check to see if the nextrun time found is a) on an acceptable
            -- weekday, and b) not matched by an exception. If not, set
            -- runafter = nextrun and try again.

            -- Check for a wildcard weekday
            gotit := FALSE;
            FOR i IN 1 .. 7 LOOP
                IF jscweekdays[i] = TRUE THEN
                    gotit := TRUE;
                    EXIT;
                END IF;
            END LOOP;

            -- OK, is the correct weekday selected, or a wildcard?
            IF (jscweekdays[date_part('DOW', nextrun) + 1] = TRUE OR gotit = FALSE) THEN

                -- Check for exceptions
                SELECT INTO d jexid FROM pgagent.pga_exception WHERE jexscid = jscid AND ((jexdate = nextrun::date AND jextime = nextrun::time) OR (jexdate = nextrun::date AND jextime IS NULL) OR (jexdate IS NULL AND jextime = nextrun::time));
                IF FOUND THEN
                    -- Nuts - found an exception. Increment the time and try again
                    runafter := nextrun + INTERVAL '1 Minute';
                    bingo := FALSE;
                    minutetweak := TRUE;
            daytweak := FALSE;
                ELSE
                    bingo := TRUE;
                END IF;
            ELSE
                -- We're on the wrong week day - increment a day and try again.
                runafter := nextrun + INTERVAL '1 Day';
                bingo := FALSE;
                minutetweak := FALSE;
                daytweak := TRUE;
            END IF;

        ELSE
            runafter := nextrun + INTERVAL '1 Minute';
            bingo := FALSE;
            minutetweak := TRUE;
        daytweak := FALSE;
        END IF;

    END LOOP;

    RETURN nextrun;
END;
$_$;
 �   DROP FUNCTION pgagent.pga_next_schedule(integer, timestamp with time zone, timestamp with time zone, boolean[], boolean[], boolean[], boolean[], boolean[]);
       pgagent       postgres    false    1    8         �           0    0 �   FUNCTION pga_next_schedule(integer, timestamp with time zone, timestamp with time zone, boolean[], boolean[], boolean[], boolean[], boolean[])    COMMENT     �   COMMENT ON FUNCTION pga_next_schedule(integer, timestamp with time zone, timestamp with time zone, boolean[], boolean[], boolean[], boolean[], boolean[]) IS 'Calculates the next runtime for a given schedule';
            pgagent       postgres    false    206         �            1255    21047    pga_schedule_trigger()    FUNCTION     '  CREATE FUNCTION pga_schedule_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        -- update pga_job from remaining schedules
        -- the actual calculation of jobnextrun will be performed in the trigger
        UPDATE pgagent.pga_job
           SET jobnextrun = NULL
         WHERE jobenabled AND jobid=OLD.jscjobid;
        RETURN OLD;
    ELSE
        UPDATE pgagent.pga_job
           SET jobnextrun = NULL
         WHERE jobenabled AND jobid=NEW.jscjobid;
        RETURN NEW;
    END IF;
END;
$$;
 .   DROP FUNCTION pgagent.pga_schedule_trigger();
       pgagent       postgres    false    8    1         �           0    0    FUNCTION pga_schedule_trigger()    COMMENT     m   COMMENT ON FUNCTION pga_schedule_trigger() IS 'Update the job''s next run time whenever a schedule changes';
            pgagent       postgres    false    209         �            1255    21041    pgagent_schema_version()    FUNCTION     �   CREATE FUNCTION pgagent_schema_version() RETURNS smallint
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- RETURNS PGAGENT MAJOR VERSION
    -- WE WILL CHANGE THE MAJOR VERSION, ONLY IF THERE IS A SCHEMA CHANGE
    RETURN 3;
END;
$$;
 0   DROP FUNCTION pgagent.pgagent_schema_version();
       pgagent       postgres    false    8    1         �            1259    20986    pga_exception    TABLE     �   CREATE TABLE pga_exception (
    jexid integer NOT NULL,
    jexscid integer NOT NULL,
    jexdate date,
    jextime time without time zone
);
 "   DROP TABLE pgagent.pga_exception;
       pgagent         postgres    false    8         �            1259    20984    pga_exception_jexid_seq    SEQUENCE     y   CREATE SEQUENCE pga_exception_jexid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 /   DROP SEQUENCE pgagent.pga_exception_jexid_seq;
       pgagent       postgres    false    198    8         �           0    0    pga_exception_jexid_seq    SEQUENCE OWNED BY     E   ALTER SEQUENCE pga_exception_jexid_seq OWNED BY pga_exception.jexid;
            pgagent       postgres    false    197         �            1259    20904    pga_job    TABLE     �  CREATE TABLE pga_job (
    jobid integer NOT NULL,
    jobjclid integer NOT NULL,
    jobname text NOT NULL,
    jobdesc text DEFAULT ''::text NOT NULL,
    jobhostagent text DEFAULT ''::text NOT NULL,
    jobenabled boolean DEFAULT true NOT NULL,
    jobcreated timestamp with time zone DEFAULT now() NOT NULL,
    jobchanged timestamp with time zone DEFAULT now() NOT NULL,
    jobagentid integer,
    jobnextrun timestamp with time zone,
    joblastrun timestamp with time zone
);
    DROP TABLE pgagent.pga_job;
       pgagent         postgres    false    8         �           0    0    TABLE pga_job    COMMENT     .   COMMENT ON TABLE pga_job IS 'Job main entry';
            pgagent       postgres    false    192         �           0    0    COLUMN pga_job.jobagentid    COMMENT     S   COMMENT ON COLUMN pga_job.jobagentid IS 'Agent that currently executes this job.';
            pgagent       postgres    false    192         �            1259    20902    pga_job_jobid_seq    SEQUENCE     s   CREATE SEQUENCE pga_job_jobid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 )   DROP SEQUENCE pgagent.pga_job_jobid_seq;
       pgagent       postgres    false    8    192         �           0    0    pga_job_jobid_seq    SEQUENCE OWNED BY     9   ALTER SEQUENCE pga_job_jobid_seq OWNED BY pga_job.jobid;
            pgagent       postgres    false    191         �            1259    20881    pga_jobagent    TABLE     �   CREATE TABLE pga_jobagent (
    jagpid integer NOT NULL,
    jaglogintime timestamp with time zone DEFAULT now() NOT NULL,
    jagstation text NOT NULL
);
 !   DROP TABLE pgagent.pga_jobagent;
       pgagent         postgres    false    8         �           0    0    TABLE pga_jobagent    COMMENT     6   COMMENT ON TABLE pga_jobagent IS 'Active job agents';
            pgagent       postgres    false    188         �            1259    20892    pga_jobclass    TABLE     U   CREATE TABLE pga_jobclass (
    jclid integer NOT NULL,
    jclname text NOT NULL
);
 !   DROP TABLE pgagent.pga_jobclass;
       pgagent         postgres    false    8         �           0    0    TABLE pga_jobclass    COMMENT     7   COMMENT ON TABLE pga_jobclass IS 'Job classification';
            pgagent       postgres    false    190         �            1259    20890    pga_jobclass_jclid_seq    SEQUENCE     x   CREATE SEQUENCE pga_jobclass_jclid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 .   DROP SEQUENCE pgagent.pga_jobclass_jclid_seq;
       pgagent       postgres    false    190    8         �           0    0    pga_jobclass_jclid_seq    SEQUENCE OWNED BY     C   ALTER SEQUENCE pga_jobclass_jclid_seq OWNED BY pga_jobclass.jclid;
            pgagent       postgres    false    189         �            1259    21001 
   pga_joblog    TABLE     v  CREATE TABLE pga_joblog (
    jlgid integer NOT NULL,
    jlgjobid integer NOT NULL,
    jlgstatus character(1) DEFAULT 'r'::bpchar NOT NULL,
    jlgstart timestamp with time zone DEFAULT now() NOT NULL,
    jlgduration interval,
    CONSTRAINT pga_joblog_jlgstatus_check CHECK ((jlgstatus = ANY (ARRAY['r'::bpchar, 's'::bpchar, 'f'::bpchar, 'i'::bpchar, 'd'::bpchar])))
);
    DROP TABLE pgagent.pga_joblog;
       pgagent         postgres    false    8         �           0    0    TABLE pga_joblog    COMMENT     0   COMMENT ON TABLE pga_joblog IS 'Job run logs.';
            pgagent       postgres    false    200         �           0    0    COLUMN pga_joblog.jlgstatus    COMMENT     �   COMMENT ON COLUMN pga_joblog.jlgstatus IS 'Status of job: r=running, s=successfully finished, f=failed, i=no steps to execute, d=aborted';
            pgagent       postgres    false    200         �            1259    20999    pga_joblog_jlgid_seq    SEQUENCE     v   CREATE SEQUENCE pga_joblog_jlgid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 ,   DROP SEQUENCE pgagent.pga_joblog_jlgid_seq;
       pgagent       postgres    false    200    8         �           0    0    pga_joblog_jlgid_seq    SEQUENCE OWNED BY     ?   ALTER SEQUENCE pga_joblog_jlgid_seq OWNED BY pga_joblog.jlgid;
            pgagent       postgres    false    199         �            1259    20930    pga_jobstep    TABLE       CREATE TABLE pga_jobstep (
    jstid integer NOT NULL,
    jstjobid integer NOT NULL,
    jstname text NOT NULL,
    jstdesc text DEFAULT ''::text NOT NULL,
    jstenabled boolean DEFAULT true NOT NULL,
    jstkind character(1) NOT NULL,
    jstcode text NOT NULL,
    jstconnstr text DEFAULT ''::text NOT NULL,
    jstdbname name DEFAULT ''::name NOT NULL,
    jstonerror character(1) DEFAULT 'f'::bpchar NOT NULL,
    jscnextrun timestamp with time zone,
    CONSTRAINT pga_jobstep_check CHECK ((((jstconnstr <> ''::text) AND (jstkind = 's'::bpchar)) OR ((jstconnstr = ''::text) AND ((jstkind = 'b'::bpchar) OR (jstdbname <> ''::name))))),
    CONSTRAINT pga_jobstep_check1 CHECK ((((jstdbname <> ''::name) AND (jstkind = 's'::bpchar)) OR ((jstdbname = ''::name) AND ((jstkind = 'b'::bpchar) OR (jstconnstr <> ''::text))))),
    CONSTRAINT pga_jobstep_jstkind_check CHECK ((jstkind = ANY (ARRAY['b'::bpchar, 's'::bpchar]))),
    CONSTRAINT pga_jobstep_jstonerror_check CHECK ((jstonerror = ANY (ARRAY['f'::bpchar, 's'::bpchar, 'i'::bpchar])))
);
     DROP TABLE pgagent.pga_jobstep;
       pgagent         postgres    false    8         �           0    0    TABLE pga_jobstep    COMMENT     ;   COMMENT ON TABLE pga_jobstep IS 'Job step to be executed';
            pgagent       postgres    false    194         �           0    0    COLUMN pga_jobstep.jstkind    COMMENT     L   COMMENT ON COLUMN pga_jobstep.jstkind IS 'Kind of jobstep: s=sql, b=batch';
            pgagent       postgres    false    194          	           0    0    COLUMN pga_jobstep.jstonerror    COMMENT     �   COMMENT ON COLUMN pga_jobstep.jstonerror IS 'What to do if step returns an error: f=fail the job, s=mark step as succeeded and continue, i=mark as fail but ignore it and proceed';
            pgagent       postgres    false    194         �            1259    20928    pga_jobstep_jstid_seq    SEQUENCE     w   CREATE SEQUENCE pga_jobstep_jstid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 -   DROP SEQUENCE pgagent.pga_jobstep_jstid_seq;
       pgagent       postgres    false    194    8         	           0    0    pga_jobstep_jstid_seq    SEQUENCE OWNED BY     A   ALTER SEQUENCE pga_jobstep_jstid_seq OWNED BY pga_jobstep.jstid;
            pgagent       postgres    false    193         �            1259    21018    pga_jobsteplog    TABLE     �  CREATE TABLE pga_jobsteplog (
    jslid integer NOT NULL,
    jsljlgid integer NOT NULL,
    jsljstid integer NOT NULL,
    jslstatus character(1) DEFAULT 'r'::bpchar NOT NULL,
    jslresult integer,
    jslstart timestamp with time zone DEFAULT now() NOT NULL,
    jslduration interval,
    jsloutput text,
    CONSTRAINT pga_jobsteplog_jslstatus_check CHECK ((jslstatus = ANY (ARRAY['r'::bpchar, 's'::bpchar, 'i'::bpchar, 'f'::bpchar, 'd'::bpchar])))
);
 #   DROP TABLE pgagent.pga_jobsteplog;
       pgagent         postgres    false    8         	           0    0    TABLE pga_jobsteplog    COMMENT     9   COMMENT ON TABLE pga_jobsteplog IS 'Job step run logs.';
            pgagent       postgres    false    202         	           0    0    COLUMN pga_jobsteplog.jslstatus    COMMENT     �   COMMENT ON COLUMN pga_jobsteplog.jslstatus IS 'Status of job step: r=running, s=successfully finished,  f=failed stopping job, i=ignored failure, d=aborted';
            pgagent       postgres    false    202         	           0    0    COLUMN pga_jobsteplog.jslresult    COMMENT     I   COMMENT ON COLUMN pga_jobsteplog.jslresult IS 'Return code of job step';
            pgagent       postgres    false    202         �            1259    21016    pga_jobsteplog_jslid_seq    SEQUENCE     z   CREATE SEQUENCE pga_jobsteplog_jslid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 0   DROP SEQUENCE pgagent.pga_jobsteplog_jslid_seq;
       pgagent       postgres    false    202    8         	           0    0    pga_jobsteplog_jslid_seq    SEQUENCE OWNED BY     G   ALTER SEQUENCE pga_jobsteplog_jslid_seq OWNED BY pga_jobsteplog.jslid;
            pgagent       postgres    false    201         �            1259    20956    pga_schedule    TABLE       CREATE TABLE pga_schedule (
    jscid integer NOT NULL,
    jscjobid integer NOT NULL,
    jscname text NOT NULL,
    jscdesc text DEFAULT ''::text NOT NULL,
    jscenabled boolean DEFAULT true NOT NULL,
    jscstart timestamp with time zone DEFAULT now() NOT NULL,
    jscend timestamp with time zone,
    jscminutes boolean[] DEFAULT '{f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}'::boolean[] NOT NULL,
    jschours boolean[] DEFAULT '{f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}'::boolean[] NOT NULL,
    jscweekdays boolean[] DEFAULT '{f,f,f,f,f,f,f}'::boolean[] NOT NULL,
    jscmonthdays boolean[] DEFAULT '{f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}'::boolean[] NOT NULL,
    jscmonths boolean[] DEFAULT '{f,f,f,f,f,f,f,f,f,f,f,f}'::boolean[] NOT NULL,
    CONSTRAINT pga_schedule_jschours_size CHECK ((array_upper(jschours, 1) = 24)),
    CONSTRAINT pga_schedule_jscminutes_size CHECK ((array_upper(jscminutes, 1) = 60)),
    CONSTRAINT pga_schedule_jscmonthdays_size CHECK ((array_upper(jscmonthdays, 1) = 32)),
    CONSTRAINT pga_schedule_jscmonths_size CHECK ((array_upper(jscmonths, 1) = 12)),
    CONSTRAINT pga_schedule_jscweekdays_size CHECK ((array_upper(jscweekdays, 1) = 7))
);
 !   DROP TABLE pgagent.pga_schedule;
       pgagent         postgres    false    8         	           0    0    TABLE pga_schedule    COMMENT     <   COMMENT ON TABLE pga_schedule IS 'Job schedule exceptions';
            pgagent       postgres    false    196         �            1259    20954    pga_schedule_jscid_seq    SEQUENCE     x   CREATE SEQUENCE pga_schedule_jscid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 .   DROP SEQUENCE pgagent.pga_schedule_jscid_seq;
       pgagent       postgres    false    196    8         	           0    0    pga_schedule_jscid_seq    SEQUENCE OWNED BY     C   ALTER SEQUENCE pga_schedule_jscid_seq OWNED BY pga_schedule.jscid;
            pgagent       postgres    false    195         �            1259    21054    admin    TABLE     J   CREATE TABLE admin (
    adminid integer NOT NULL,
    loginid integer
);
    DROP TABLE public.admin;
       public         Andrew    false    6         �            1259    21052    admin_adminid_seq    SEQUENCE     s   CREATE SEQUENCE admin_adminid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 (   DROP SEQUENCE public.admin_adminid_seq;
       public       Andrew    false    204    6         	           0    0    admin_adminid_seq    SEQUENCE OWNED BY     9   ALTER SEQUENCE admin_adminid_seq OWNED BY admin.adminid;
            public       Andrew    false    203         �            1259    20644    char    TABLE     �   CREATE TABLE "char" (
    charid integer NOT NULL,
    charname text,
    charreal text,
    picture character(30),
    earthname text,
    extra jsonb
);
    DROP TABLE public."char";
       public         Andrew    false    6         �            1259    20642    char_charid_seq    SEQUENCE     q   CREATE SEQUENCE char_charid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 &   DROP SEQUENCE public.char_charid_seq;
       public       Andrew    false    183    6         		           0    0    char_charid_seq    SEQUENCE OWNED BY     7   ALTER SEQUENCE char_charid_seq OWNED BY "char".charid;
            public       Andrew    false    182         �            1259    20663    fav    TABLE     [   CREATE TABLE fav (
    favid integer NOT NULL,
    userid integer,
    charid integer[]
);
    DROP TABLE public.fav;
       public         Andrew    false    6         �            1259    20661    fav_favid_seq    SEQUENCE     o   CREATE SEQUENCE fav_favid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 $   DROP SEQUENCE public.fav_favid_seq;
       public       Andrew    false    6    185         
	           0    0    fav_favid_seq    SEQUENCE OWNED BY     1   ALTER SEQUENCE fav_favid_seq OWNED BY fav.favid;
            public       Andrew    false    184         �            1259    20672    login    TABLE     �   CREATE TABLE login (
    loginid integer NOT NULL,
    firstname text,
    lastname text,
    login text,
    hashedpassword character(75),
    profileimg character(30),
    email text
);
    DROP TABLE public.login;
       public         Andrew    false    6         �            1259    20670    login_loginid_seq    SEQUENCE     s   CREATE SEQUENCE login_loginid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 (   DROP SEQUENCE public.login_loginid_seq;
       public       Andrew    false    187    6         	           0    0    login_loginid_seq    SEQUENCE OWNED BY     9   ALTER SEQUENCE login_loginid_seq OWNED BY login.loginid;
            public       Andrew    false    186         0           2604    20989    jexid    DEFAULT     l   ALTER TABLE ONLY pga_exception ALTER COLUMN jexid SET DEFAULT nextval('pga_exception_jexid_seq'::regclass);
 C   ALTER TABLE pgagent.pga_exception ALTER COLUMN jexid DROP DEFAULT;
       pgagent       postgres    false    197    198    198                    2604    20907    jobid    DEFAULT     `   ALTER TABLE ONLY pga_job ALTER COLUMN jobid SET DEFAULT nextval('pga_job_jobid_seq'::regclass);
 =   ALTER TABLE pgagent.pga_job ALTER COLUMN jobid DROP DEFAULT;
       pgagent       postgres    false    191    192    192                    2604    20895    jclid    DEFAULT     j   ALTER TABLE ONLY pga_jobclass ALTER COLUMN jclid SET DEFAULT nextval('pga_jobclass_jclid_seq'::regclass);
 B   ALTER TABLE pgagent.pga_jobclass ALTER COLUMN jclid DROP DEFAULT;
       pgagent       postgres    false    190    189    190         1           2604    21004    jlgid    DEFAULT     f   ALTER TABLE ONLY pga_joblog ALTER COLUMN jlgid SET DEFAULT nextval('pga_joblog_jlgid_seq'::regclass);
 @   ALTER TABLE pgagent.pga_joblog ALTER COLUMN jlgid DROP DEFAULT;
       pgagent       postgres    false    200    199    200                    2604    20933    jstid    DEFAULT     h   ALTER TABLE ONLY pga_jobstep ALTER COLUMN jstid SET DEFAULT nextval('pga_jobstep_jstid_seq'::regclass);
 A   ALTER TABLE pgagent.pga_jobstep ALTER COLUMN jstid DROP DEFAULT;
       pgagent       postgres    false    193    194    194         5           2604    21021    jslid    DEFAULT     n   ALTER TABLE ONLY pga_jobsteplog ALTER COLUMN jslid SET DEFAULT nextval('pga_jobsteplog_jslid_seq'::regclass);
 D   ALTER TABLE pgagent.pga_jobsteplog ALTER COLUMN jslid DROP DEFAULT;
       pgagent       postgres    false    202    201    202         "           2604    20959    jscid    DEFAULT     j   ALTER TABLE ONLY pga_schedule ALTER COLUMN jscid SET DEFAULT nextval('pga_schedule_jscid_seq'::regclass);
 B   ALTER TABLE pgagent.pga_schedule ALTER COLUMN jscid DROP DEFAULT;
       pgagent       postgres    false    195    196    196         9           2604    21057    adminid    DEFAULT     `   ALTER TABLE ONLY admin ALTER COLUMN adminid SET DEFAULT nextval('admin_adminid_seq'::regclass);
 <   ALTER TABLE public.admin ALTER COLUMN adminid DROP DEFAULT;
       public       Andrew    false    203    204    204                    2604    20647    charid    DEFAULT     ^   ALTER TABLE ONLY "char" ALTER COLUMN charid SET DEFAULT nextval('char_charid_seq'::regclass);
 <   ALTER TABLE public."char" ALTER COLUMN charid DROP DEFAULT;
       public       Andrew    false    183    182    183                    2604    20666    favid    DEFAULT     X   ALTER TABLE ONLY fav ALTER COLUMN favid SET DEFAULT nextval('fav_favid_seq'::regclass);
 8   ALTER TABLE public.fav ALTER COLUMN favid DROP DEFAULT;
       public       Andrew    false    184    185    185                    2604    20675    loginid    DEFAULT     `   ALTER TABLE ONLY login ALTER COLUMN loginid SET DEFAULT nextval('login_loginid_seq'::regclass);
 <   ALTER TABLE public.login ALTER COLUMN loginid DROP DEFAULT;
       public       Andrew    false    187    186    187         �          0    20986    pga_exception 
   TABLE DATA               B   COPY pga_exception (jexid, jexscid, jexdate, jextime) FROM stdin;
    pgagent       postgres    false    198       2271.dat 	           0    0    pga_exception_jexid_seq    SEQUENCE SET     ?   SELECT pg_catalog.setval('pga_exception_jexid_seq', 1, false);
            pgagent       postgres    false    197         �          0    20904    pga_job 
   TABLE DATA               �   COPY pga_job (jobid, jobjclid, jobname, jobdesc, jobhostagent, jobenabled, jobcreated, jobchanged, jobagentid, jobnextrun, joblastrun) FROM stdin;
    pgagent       postgres    false    192       2265.dat 	           0    0    pga_job_jobid_seq    SEQUENCE SET     9   SELECT pg_catalog.setval('pga_job_jobid_seq', 1, false);
            pgagent       postgres    false    191         �          0    20881    pga_jobagent 
   TABLE DATA               A   COPY pga_jobagent (jagpid, jaglogintime, jagstation) FROM stdin;
    pgagent       postgres    false    188       2261.dat �          0    20892    pga_jobclass 
   TABLE DATA               /   COPY pga_jobclass (jclid, jclname) FROM stdin;
    pgagent       postgres    false    190       2263.dat 	           0    0    pga_jobclass_jclid_seq    SEQUENCE SET     =   SELECT pg_catalog.setval('pga_jobclass_jclid_seq', 5, true);
            pgagent       postgres    false    189         �          0    21001 
   pga_joblog 
   TABLE DATA               P   COPY pga_joblog (jlgid, jlgjobid, jlgstatus, jlgstart, jlgduration) FROM stdin;
    pgagent       postgres    false    200       2273.dat 	           0    0    pga_joblog_jlgid_seq    SEQUENCE SET     <   SELECT pg_catalog.setval('pga_joblog_jlgid_seq', 1, false);
            pgagent       postgres    false    199         �          0    20930    pga_jobstep 
   TABLE DATA               �   COPY pga_jobstep (jstid, jstjobid, jstname, jstdesc, jstenabled, jstkind, jstcode, jstconnstr, jstdbname, jstonerror, jscnextrun) FROM stdin;
    pgagent       postgres    false    194       2267.dat 	           0    0    pga_jobstep_jstid_seq    SEQUENCE SET     =   SELECT pg_catalog.setval('pga_jobstep_jstid_seq', 1, false);
            pgagent       postgres    false    193         �          0    21018    pga_jobsteplog 
   TABLE DATA               t   COPY pga_jobsteplog (jslid, jsljlgid, jsljstid, jslstatus, jslresult, jslstart, jslduration, jsloutput) FROM stdin;
    pgagent       postgres    false    202       2275.dat 	           0    0    pga_jobsteplog_jslid_seq    SEQUENCE SET     @   SELECT pg_catalog.setval('pga_jobsteplog_jslid_seq', 1, false);
            pgagent       postgres    false    201         �          0    20956    pga_schedule 
   TABLE DATA               �   COPY pga_schedule (jscid, jscjobid, jscname, jscdesc, jscenabled, jscstart, jscend, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) FROM stdin;
    pgagent       postgres    false    196       2269.dat 	           0    0    pga_schedule_jscid_seq    SEQUENCE SET     >   SELECT pg_catalog.setval('pga_schedule_jscid_seq', 1, false);
            pgagent       postgres    false    195         �          0    21054    admin 
   TABLE DATA               *   COPY admin (adminid, loginid) FROM stdin;
    public       Andrew    false    204       2277.dat 	           0    0    admin_adminid_seq    SEQUENCE SET     9   SELECT pg_catalog.setval('admin_adminid_seq', 1, false);
            public       Andrew    false    203         �          0    20644    char 
   TABLE DATA               P   COPY "char" (charid, charname, charreal, picture, earthname, extra) FROM stdin;
    public       Andrew    false    183       2256.dat 	           0    0    char_charid_seq    SEQUENCE SET     7   SELECT pg_catalog.setval('char_charid_seq', 1, false);
            public       Andrew    false    182         �          0    20663    fav 
   TABLE DATA               -   COPY fav (favid, userid, charid) FROM stdin;
    public       Andrew    false    185       2258.dat 	           0    0    fav_favid_seq    SEQUENCE SET     5   SELECT pg_catalog.setval('fav_favid_seq', 1, false);
            public       Andrew    false    184         �          0    20672    login 
   TABLE DATA               `   COPY login (loginid, firstname, lastname, login, hashedpassword, profileimg, email) FROM stdin;
    public       Andrew    false    187       2260.dat 	           0    0    login_loginid_seq    SEQUENCE SET     8   SELECT pg_catalog.setval('login_loginid_seq', 6, true);
            public       Andrew    false    186         J           2606    20991    pga_exception_pkey 
   CONSTRAINT     Z   ALTER TABLE ONLY pga_exception
    ADD CONSTRAINT pga_exception_pkey PRIMARY KEY (jexid);
 K   ALTER TABLE ONLY pgagent.pga_exception DROP CONSTRAINT pga_exception_pkey;
       pgagent         postgres    false    198    198         @           2606    20917    pga_job_pkey 
   CONSTRAINT     N   ALTER TABLE ONLY pga_job
    ADD CONSTRAINT pga_job_pkey PRIMARY KEY (jobid);
 ?   ALTER TABLE ONLY pgagent.pga_job DROP CONSTRAINT pga_job_pkey;
       pgagent         postgres    false    192    192         ;           2606    20889    pga_jobagent_pkey 
   CONSTRAINT     Y   ALTER TABLE ONLY pga_jobagent
    ADD CONSTRAINT pga_jobagent_pkey PRIMARY KEY (jagpid);
 I   ALTER TABLE ONLY pgagent.pga_jobagent DROP CONSTRAINT pga_jobagent_pkey;
       pgagent         postgres    false    188    188         >           2606    20900    pga_jobclass_pkey 
   CONSTRAINT     X   ALTER TABLE ONLY pga_jobclass
    ADD CONSTRAINT pga_jobclass_pkey PRIMARY KEY (jclid);
 I   ALTER TABLE ONLY pgagent.pga_jobclass DROP CONSTRAINT pga_jobclass_pkey;
       pgagent         postgres    false    190    190         M           2606    21009    pga_joblog_pkey 
   CONSTRAINT     T   ALTER TABLE ONLY pga_joblog
    ADD CONSTRAINT pga_joblog_pkey PRIMARY KEY (jlgid);
 E   ALTER TABLE ONLY pgagent.pga_joblog DROP CONSTRAINT pga_joblog_pkey;
       pgagent         postgres    false    200    200         C           2606    20947    pga_jobstep_pkey 
   CONSTRAINT     V   ALTER TABLE ONLY pga_jobstep
    ADD CONSTRAINT pga_jobstep_pkey PRIMARY KEY (jstid);
 G   ALTER TABLE ONLY pgagent.pga_jobstep DROP CONSTRAINT pga_jobstep_pkey;
       pgagent         postgres    false    194    194         P           2606    21029    pga_jobsteplog_pkey 
   CONSTRAINT     \   ALTER TABLE ONLY pga_jobsteplog
    ADD CONSTRAINT pga_jobsteplog_pkey PRIMARY KEY (jslid);
 M   ALTER TABLE ONLY pgagent.pga_jobsteplog DROP CONSTRAINT pga_jobsteplog_pkey;
       pgagent         postgres    false    202    202         F           2606    20977    pga_schedule_pkey 
   CONSTRAINT     X   ALTER TABLE ONLY pga_schedule
    ADD CONSTRAINT pga_schedule_pkey PRIMARY KEY (jscid);
 I   ALTER TABLE ONLY pgagent.pga_schedule DROP CONSTRAINT pga_schedule_pkey;
       pgagent         postgres    false    196    196         G           1259    20998    pga_exception_datetime    INDEX     \   CREATE UNIQUE INDEX pga_exception_datetime ON pga_exception USING btree (jexdate, jextime);
 +   DROP INDEX pgagent.pga_exception_datetime;
       pgagent         postgres    false    198    198         H           1259    20997    pga_exception_jexscid    INDEX     K   CREATE INDEX pga_exception_jexscid ON pga_exception USING btree (jexscid);
 *   DROP INDEX pgagent.pga_exception_jexscid;
       pgagent         postgres    false    198         <           1259    20901    pga_jobclass_name    INDEX     M   CREATE UNIQUE INDEX pga_jobclass_name ON pga_jobclass USING btree (jclname);
 &   DROP INDEX pgagent.pga_jobclass_name;
       pgagent         postgres    false    190         K           1259    21015    pga_joblog_jobid    INDEX     D   CREATE INDEX pga_joblog_jobid ON pga_joblog USING btree (jlgjobid);
 %   DROP INDEX pgagent.pga_joblog_jobid;
       pgagent         postgres    false    200         D           1259    20983    pga_jobschedule_jobid    INDEX     K   CREATE INDEX pga_jobschedule_jobid ON pga_schedule USING btree (jscjobid);
 *   DROP INDEX pgagent.pga_jobschedule_jobid;
       pgagent         postgres    false    196         A           1259    20953    pga_jobstep_jobid    INDEX     F   CREATE INDEX pga_jobstep_jobid ON pga_jobstep USING btree (jstjobid);
 &   DROP INDEX pgagent.pga_jobstep_jobid;
       pgagent         postgres    false    194         N           1259    21040    pga_jobsteplog_jslid    INDEX     L   CREATE INDEX pga_jobsteplog_jslid ON pga_jobsteplog USING btree (jsljlgid);
 )   DROP INDEX pgagent.pga_jobsteplog_jslid;
       pgagent         postgres    false    202         Q           1259    21060    unique_admin    INDEX     A   CREATE UNIQUE INDEX unique_admin ON admin USING btree (adminid);
     DROP INDEX public.unique_admin;
       public         Andrew    false    204         \           2620    21050    pga_exception_trigger    TRIGGER     �   CREATE TRIGGER pga_exception_trigger AFTER INSERT OR DELETE OR UPDATE ON pga_exception FOR EACH ROW EXECUTE PROCEDURE pga_exception_trigger();
 =   DROP TRIGGER pga_exception_trigger ON pgagent.pga_exception;
       pgagent       postgres    false    222    198         	           0    0 .   TRIGGER pga_exception_trigger ON pga_exception    COMMENT     ~   COMMENT ON TRIGGER pga_exception_trigger ON pga_exception IS 'Update the job''s next run time whenever an exception changes';
            pgagent       postgres    false    2140         Z           2620    21046    pga_job_trigger    TRIGGER     j   CREATE TRIGGER pga_job_trigger BEFORE UPDATE ON pga_job FOR EACH ROW EXECUTE PROCEDURE pga_job_trigger();
 1   DROP TRIGGER pga_job_trigger ON pgagent.pga_job;
       pgagent       postgres    false    208    192         	           0    0 "   TRIGGER pga_job_trigger ON pga_job    COMMENT     U   COMMENT ON TRIGGER pga_job_trigger ON pga_job IS 'Update the job''s next run time.';
            pgagent       postgres    false    2138         [           2620    21048    pga_schedule_trigger    TRIGGER     �   CREATE TRIGGER pga_schedule_trigger AFTER INSERT OR DELETE OR UPDATE ON pga_schedule FOR EACH ROW EXECUTE PROCEDURE pga_schedule_trigger();
 ;   DROP TRIGGER pga_schedule_trigger ON pgagent.pga_schedule;
       pgagent       postgres    false    209    196         	           0    0 ,   TRIGGER pga_schedule_trigger ON pga_schedule    COMMENT     z   COMMENT ON TRIGGER pga_schedule_trigger ON pga_schedule IS 'Update the job''s next run time whenever a schedule changes';
            pgagent       postgres    false    2139         V           2606    20992    pga_exception_jexscid_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY pga_exception
    ADD CONSTRAINT pga_exception_jexscid_fkey FOREIGN KEY (jexscid) REFERENCES pga_schedule(jscid) ON UPDATE RESTRICT ON DELETE CASCADE;
 S   ALTER TABLE ONLY pgagent.pga_exception DROP CONSTRAINT pga_exception_jexscid_fkey;
       pgagent       postgres    false    196    2118    198         S           2606    20923    pga_job_jobagentid_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY pga_job
    ADD CONSTRAINT pga_job_jobagentid_fkey FOREIGN KEY (jobagentid) REFERENCES pga_jobagent(jagpid) ON UPDATE RESTRICT ON DELETE SET NULL;
 J   ALTER TABLE ONLY pgagent.pga_job DROP CONSTRAINT pga_job_jobagentid_fkey;
       pgagent       postgres    false    192    2107    188         R           2606    20918    pga_job_jobjclid_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY pga_job
    ADD CONSTRAINT pga_job_jobjclid_fkey FOREIGN KEY (jobjclid) REFERENCES pga_jobclass(jclid) ON UPDATE RESTRICT ON DELETE RESTRICT;
 H   ALTER TABLE ONLY pgagent.pga_job DROP CONSTRAINT pga_job_jobjclid_fkey;
       pgagent       postgres    false    190    192    2110         W           2606    21010    pga_joblog_jlgjobid_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY pga_joblog
    ADD CONSTRAINT pga_joblog_jlgjobid_fkey FOREIGN KEY (jlgjobid) REFERENCES pga_job(jobid) ON UPDATE RESTRICT ON DELETE CASCADE;
 N   ALTER TABLE ONLY pgagent.pga_joblog DROP CONSTRAINT pga_joblog_jlgjobid_fkey;
       pgagent       postgres    false    192    200    2112         T           2606    20948    pga_jobstep_jstjobid_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY pga_jobstep
    ADD CONSTRAINT pga_jobstep_jstjobid_fkey FOREIGN KEY (jstjobid) REFERENCES pga_job(jobid) ON UPDATE RESTRICT ON DELETE CASCADE;
 P   ALTER TABLE ONLY pgagent.pga_jobstep DROP CONSTRAINT pga_jobstep_jstjobid_fkey;
       pgagent       postgres    false    192    2112    194         X           2606    21030    pga_jobsteplog_jsljlgid_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY pga_jobsteplog
    ADD CONSTRAINT pga_jobsteplog_jsljlgid_fkey FOREIGN KEY (jsljlgid) REFERENCES pga_joblog(jlgid) ON UPDATE RESTRICT ON DELETE CASCADE;
 V   ALTER TABLE ONLY pgagent.pga_jobsteplog DROP CONSTRAINT pga_jobsteplog_jsljlgid_fkey;
       pgagent       postgres    false    2125    202    200         Y           2606    21035    pga_jobsteplog_jsljstid_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY pga_jobsteplog
    ADD CONSTRAINT pga_jobsteplog_jsljstid_fkey FOREIGN KEY (jsljstid) REFERENCES pga_jobstep(jstid) ON UPDATE RESTRICT ON DELETE CASCADE;
 V   ALTER TABLE ONLY pgagent.pga_jobsteplog DROP CONSTRAINT pga_jobsteplog_jsljstid_fkey;
       pgagent       postgres    false    2115    202    194         U           2606    20978    pga_schedule_jscjobid_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY pga_schedule
    ADD CONSTRAINT pga_schedule_jscjobid_fkey FOREIGN KEY (jscjobid) REFERENCES pga_job(jobid) ON UPDATE RESTRICT ON DELETE CASCADE;
 R   ALTER TABLE ONLY pgagent.pga_schedule DROP CONSTRAINT pga_schedule_jscjobid_fkey;
       pgagent       postgres    false    2112    196    192                       2271.dat                                                                                            0000600 0004000 0002000 00000000005 12706517363 0014252 0                                                                                                    ustar 00postgres                        postgres                        0000000 0000000                                                                                                                                                                        \.


                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           2265.dat                                                                                            0000600 0004000 0002000 00000000005 12706517363 0014255 0                                                                                                    ustar 00postgres                        postgres                        0000000 0000000                                                                                                                                                                        \.


                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           2261.dat                                                                                            0000600 0004000 0002000 00000000005 12706517363 0014251 0                                                                                                    ustar 00postgres                        postgres                        0000000 0000000                                                                                                                                                                        \.


                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           2263.dat                                                                                            0000600 0004000 0002000 00000000134 12706517363 0014256 0                                                                                                    ustar 00postgres                        postgres                        0000000 0000000                                                                                                                                                                        1	Routine Maintenance
2	Data Import
3	Data Export
4	Data Summarisation
5	Miscellaneous
\.


                                                                                                                                                                                                                                                                                                                                                                                                                                    2273.dat                                                                                            0000600 0004000 0002000 00000000005 12706517363 0014254 0                                                                                                    ustar 00postgres                        postgres                        0000000 0000000                                                                                                                                                                        \.


                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           2267.dat                                                                                            0000600 0004000 0002000 00000000005 12706517363 0014257 0                                                                                                    ustar 00postgres                        postgres                        0000000 0000000                                                                                                                                                                        \.


                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           2275.dat                                                                                            0000600 0004000 0002000 00000000005 12706517363 0014256 0                                                                                                    ustar 00postgres                        postgres                        0000000 0000000                                                                                                                                                                        \.


                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           2269.dat                                                                                            0000600 0004000 0002000 00000000005 12706517363 0014261 0                                                                                                    ustar 00postgres                        postgres                        0000000 0000000                                                                                                                                                                        \.


                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           2277.dat                                                                                            0000600 0004000 0002000 00000000011 12706517363 0014255 0                                                                                                    ustar 00postgres                        postgres                        0000000 0000000                                                                                                                                                                        1	1
\.


                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       2256.dat                                                                                            0000600 0004000 0002000 00000002463 12706517363 0014267 0                                                                                                    ustar 00postgres                        postgres                        0000000 0000000                                                                                                                                                                        2	batman	bruce wayne	batman.jpg                    		{"powers": ["Superhuman Detective Skills", "Superhuman strength of will and dedication", "Nearly-superhuman wealth"], "nemisis": "The Joker"}
3	iron man	tony stark	iornman.jpg                   		{"powers": ["super strength", "the ability to fly", "durability", "Suits Weapons"], "nemisis": "Mandarin ", "weapons": ["repulsor rays", "pulse beams", " missile launchers", "lasers", " tasers", "flamethrowers", "unibeam"]}
4	the vision		vision.jpg                    		{"powers": ["Superhuman agility", "Superhuman intelligence", "Superhuman strength", "Superhuman speed", "Flight", "Density control", "Intangibility", "Shapeshifting", "Mass manipulation", "Regeneration", "Solar energy projection", "Technopathy"], "nemisis": "Ultron"}
1	superman	kal-el	superman.jpg                  	Clark Kent	{"powers": ["flight", "superhuman strength", "x-ray vision", "heat vision", "cold breath", "super-speed", "enhanced hearing", "nigh-invulnerability"], "nemisis": "Lex Luthor"}
5	wolverine	james "logan" howlett	wolverine.jpg                 		{"powers": ["Master martial artist", "Regenerative healing factor", "Adamantium-plated skeletal structure and retractable claws", "Superhuman senses, reflexes, and animal-like attributes", "Extended longevity"], "nemisis": "Sabretooth"}
\.


                                                                                                                                                                                                             2258.dat                                                                                            0000600 0004000 0002000 00000000031 12706517363 0014256 0                                                                                                    ustar 00postgres                        postgres                        0000000 0000000                                                                                                                                                                        1	1	{1}
2	3	{5,1,3}
\.


                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       2260.dat                                                                                            0000600 0004000 0002000 00000001221 12706517363 0014251 0                                                                                                    ustar 00postgres                        postgres                        0000000 0000000                                                                                                                                                                        1	a	a	a	369fbe49b773e093ad60d35021fa2496b9d12b27                                   	\N	a@gmail.com
2	cat	cat	cat	3b10e97f52cec17b08918b992cc42f6f76666e28                                   	\N	cat@gmail.com
3	Andrew	Dickinson	acdickin	fcbac1a0ebe1a2642084ae9e67999d2991808aed                                   	\N	acdickin@gmail.com
4	b	b	b	8bb55f74c57d2910f8bbb195f9e35379aff015ea                                   	\N	b@f.com
5	apple	apple	apple	b954082236f856dbd684c9ad17a08fea6100b96f                                   	\N	apple@gmail.com
6	dood	dood	dood	62ce3feed72c13e2270d4aa0f4bd3bd7b54637c2                                   	\N	dood@dood.org
\.


                                                                                                                                                                                                                                                                                                                                                                               restore.sql                                                                                         0000600 0004000 0002000 00000143563 12706517363 0015412 0                                                                                                    ustar 00postgres                        postgres                        0000000 0000000                                                                                                                                                                        --
-- NOTE:
--
-- File paths need to be edited. Search for $$PATH$$ and
-- replace it with the path to the directory containing
-- the extracted data files.
--
--
-- PostgreSQL database dump
--

-- Dumped from database version 9.5.1
-- Dumped by pg_dump version 9.5.1

SET statement_timeout = 0;
SET lock_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET row_security = off;

SET search_path = pgagent, pg_catalog;

ALTER TABLE ONLY pgagent.pga_schedule DROP CONSTRAINT pga_schedule_jscjobid_fkey;
ALTER TABLE ONLY pgagent.pga_jobsteplog DROP CONSTRAINT pga_jobsteplog_jsljstid_fkey;
ALTER TABLE ONLY pgagent.pga_jobsteplog DROP CONSTRAINT pga_jobsteplog_jsljlgid_fkey;
ALTER TABLE ONLY pgagent.pga_jobstep DROP CONSTRAINT pga_jobstep_jstjobid_fkey;
ALTER TABLE ONLY pgagent.pga_joblog DROP CONSTRAINT pga_joblog_jlgjobid_fkey;
ALTER TABLE ONLY pgagent.pga_job DROP CONSTRAINT pga_job_jobjclid_fkey;
ALTER TABLE ONLY pgagent.pga_job DROP CONSTRAINT pga_job_jobagentid_fkey;
ALTER TABLE ONLY pgagent.pga_exception DROP CONSTRAINT pga_exception_jexscid_fkey;
DROP TRIGGER pga_schedule_trigger ON pgagent.pga_schedule;
DROP TRIGGER pga_job_trigger ON pgagent.pga_job;
DROP TRIGGER pga_exception_trigger ON pgagent.pga_exception;
SET search_path = public, pg_catalog;

DROP INDEX public.unique_admin;
SET search_path = pgagent, pg_catalog;

DROP INDEX pgagent.pga_jobsteplog_jslid;
DROP INDEX pgagent.pga_jobstep_jobid;
DROP INDEX pgagent.pga_jobschedule_jobid;
DROP INDEX pgagent.pga_joblog_jobid;
DROP INDEX pgagent.pga_jobclass_name;
DROP INDEX pgagent.pga_exception_jexscid;
DROP INDEX pgagent.pga_exception_datetime;
ALTER TABLE ONLY pgagent.pga_schedule DROP CONSTRAINT pga_schedule_pkey;
ALTER TABLE ONLY pgagent.pga_jobsteplog DROP CONSTRAINT pga_jobsteplog_pkey;
ALTER TABLE ONLY pgagent.pga_jobstep DROP CONSTRAINT pga_jobstep_pkey;
ALTER TABLE ONLY pgagent.pga_joblog DROP CONSTRAINT pga_joblog_pkey;
ALTER TABLE ONLY pgagent.pga_jobclass DROP CONSTRAINT pga_jobclass_pkey;
ALTER TABLE ONLY pgagent.pga_jobagent DROP CONSTRAINT pga_jobagent_pkey;
ALTER TABLE ONLY pgagent.pga_job DROP CONSTRAINT pga_job_pkey;
ALTER TABLE ONLY pgagent.pga_exception DROP CONSTRAINT pga_exception_pkey;
SET search_path = public, pg_catalog;

SET search_path = pgagent, pg_catalog;

SET search_path = public, pg_catalog;

ALTER TABLE public.login ALTER COLUMN loginid DROP DEFAULT;
ALTER TABLE public.fav ALTER COLUMN favid DROP DEFAULT;
ALTER TABLE public."char" ALTER COLUMN charid DROP DEFAULT;
ALTER TABLE public.admin ALTER COLUMN adminid DROP DEFAULT;
SET search_path = pgagent, pg_catalog;

ALTER TABLE pgagent.pga_schedule ALTER COLUMN jscid DROP DEFAULT;
ALTER TABLE pgagent.pga_jobsteplog ALTER COLUMN jslid DROP DEFAULT;
ALTER TABLE pgagent.pga_jobstep ALTER COLUMN jstid DROP DEFAULT;
ALTER TABLE pgagent.pga_joblog ALTER COLUMN jlgid DROP DEFAULT;
ALTER TABLE pgagent.pga_jobclass ALTER COLUMN jclid DROP DEFAULT;
ALTER TABLE pgagent.pga_job ALTER COLUMN jobid DROP DEFAULT;
ALTER TABLE pgagent.pga_exception ALTER COLUMN jexid DROP DEFAULT;
SET search_path = public, pg_catalog;

DROP SEQUENCE public.login_loginid_seq;
DROP TABLE public.login;
DROP SEQUENCE public.fav_favid_seq;
DROP TABLE public.fav;
DROP SEQUENCE public.char_charid_seq;
DROP TABLE public."char";
DROP SEQUENCE public.admin_adminid_seq;
DROP TABLE public.admin;
SET search_path = pgagent, pg_catalog;

DROP SEQUENCE pgagent.pga_schedule_jscid_seq;
DROP TABLE pgagent.pga_schedule;
DROP SEQUENCE pgagent.pga_jobsteplog_jslid_seq;
DROP TABLE pgagent.pga_jobsteplog;
DROP SEQUENCE pgagent.pga_jobstep_jstid_seq;
DROP TABLE pgagent.pga_jobstep;
DROP SEQUENCE pgagent.pga_joblog_jlgid_seq;
DROP TABLE pgagent.pga_joblog;
DROP SEQUENCE pgagent.pga_jobclass_jclid_seq;
DROP TABLE pgagent.pga_jobclass;
DROP TABLE pgagent.pga_jobagent;
DROP SEQUENCE pgagent.pga_job_jobid_seq;
DROP TABLE pgagent.pga_job;
DROP SEQUENCE pgagent.pga_exception_jexid_seq;
DROP TABLE pgagent.pga_exception;
DROP FUNCTION pgagent.pgagent_schema_version();
DROP FUNCTION pgagent.pga_schedule_trigger();
DROP FUNCTION pgagent.pga_next_schedule(integer, timestamp with time zone, timestamp with time zone, boolean[], boolean[], boolean[], boolean[], boolean[]);
DROP FUNCTION pgagent.pga_job_trigger();
DROP FUNCTION pgagent.pga_is_leap_year(smallint);
DROP FUNCTION pgagent.pga_exception_trigger();
DROP EXTENSION plpgsql;
DROP SCHEMA public;
DROP SCHEMA pgagent;
--
-- Name: pgagent; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA pgagent;


ALTER SCHEMA pgagent OWNER TO postgres;

--
-- Name: SCHEMA pgagent; Type: COMMENT; Schema: -; Owner: postgres
--

COMMENT ON SCHEMA pgagent IS 'pgAgent system tables';


--
-- Name: public; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA public;


ALTER SCHEMA public OWNER TO postgres;

--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: postgres
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


SET search_path = pgagent, pg_catalog;

--
-- Name: pga_exception_trigger(); Type: FUNCTION; Schema: pgagent; Owner: postgres
--

CREATE FUNCTION pga_exception_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE

    v_jobid int4 := 0;

BEGIN

     IF TG_OP = 'DELETE' THEN

        SELECT INTO v_jobid jscjobid FROM pgagent.pga_schedule WHERE jscid = OLD.jexscid;

        -- update pga_job from remaining schedules
        -- the actual calculation of jobnextrun will be performed in the trigger
        UPDATE pgagent.pga_job
           SET jobnextrun = NULL
         WHERE jobenabled AND jobid = v_jobid;
        RETURN OLD;
    ELSE

        SELECT INTO v_jobid jscjobid FROM pgagent.pga_schedule WHERE jscid = NEW.jexscid;

        UPDATE pgagent.pga_job
           SET jobnextrun = NULL
         WHERE jobenabled AND jobid = v_jobid;
        RETURN NEW;
    END IF;
END;
$$;


ALTER FUNCTION pgagent.pga_exception_trigger() OWNER TO postgres;

--
-- Name: FUNCTION pga_exception_trigger(); Type: COMMENT; Schema: pgagent; Owner: postgres
--

COMMENT ON FUNCTION pga_exception_trigger() IS 'Update the job''s next run time whenever an exception changes';


--
-- Name: pga_is_leap_year(smallint); Type: FUNCTION; Schema: pgagent; Owner: postgres
--

CREATE FUNCTION pga_is_leap_year(smallint) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    AS $_$
BEGIN
    IF $1 % 4 != 0 THEN
        RETURN FALSE;
    END IF;

    IF $1 % 100 != 0 THEN
        RETURN TRUE;
    END IF;

    RETURN $1 % 400 = 0;
END;
$_$;


ALTER FUNCTION pgagent.pga_is_leap_year(smallint) OWNER TO postgres;

--
-- Name: FUNCTION pga_is_leap_year(smallint); Type: COMMENT; Schema: pgagent; Owner: postgres
--

COMMENT ON FUNCTION pga_is_leap_year(smallint) IS 'Returns TRUE if $1 is a leap year';


--
-- Name: pga_job_trigger(); Type: FUNCTION; Schema: pgagent; Owner: postgres
--

CREATE FUNCTION pga_job_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.jobenabled THEN
        IF NEW.jobnextrun IS NULL THEN
             SELECT INTO NEW.jobnextrun
                    MIN(pgagent.pga_next_schedule(jscid, jscstart, jscend, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths))
               FROM pgagent.pga_schedule
              WHERE jscenabled AND jscjobid=OLD.jobid;
        END IF;
    ELSE
        NEW.jobnextrun := NULL;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION pgagent.pga_job_trigger() OWNER TO postgres;

--
-- Name: FUNCTION pga_job_trigger(); Type: COMMENT; Schema: pgagent; Owner: postgres
--

COMMENT ON FUNCTION pga_job_trigger() IS 'Update the job''s next run time.';


--
-- Name: pga_next_schedule(integer, timestamp with time zone, timestamp with time zone, boolean[], boolean[], boolean[], boolean[], boolean[]); Type: FUNCTION; Schema: pgagent; Owner: postgres
--

CREATE FUNCTION pga_next_schedule(integer, timestamp with time zone, timestamp with time zone, boolean[], boolean[], boolean[], boolean[], boolean[]) RETURNS timestamp with time zone
    LANGUAGE plpgsql
    AS $_$
DECLARE
    jscid           ALIAS FOR $1;
    jscstart        ALIAS FOR $2;
    jscend          ALIAS FOR $3;
    jscminutes      ALIAS FOR $4;
    jschours        ALIAS FOR $5;
    jscweekdays     ALIAS FOR $6;
    jscmonthdays    ALIAS FOR $7;
    jscmonths       ALIAS FOR $8;

    nextrun         timestamp := '1970-01-01 00:00:00-00';
    runafter        timestamp := '1970-01-01 00:00:00-00';

    bingo            bool := FALSE;
    gotit            bool := FALSE;
    foundval        bool := FALSE;
    daytweak        bool := FALSE;
    minutetweak        bool := FALSE;

    i                int2 := 0;
    d                int2 := 0;

    nextminute        int2 := 0;
    nexthour        int2 := 0;
    nextday            int2 := 0;
    nextmonth       int2 := 0;
    nextyear        int2 := 0;


BEGIN
    -- No valid start date has been specified
    IF jscstart IS NULL THEN RETURN NULL; END IF;

    -- The schedule is past its end date
    IF jscend IS NOT NULL AND jscend < now() THEN RETURN NULL; END IF;

    -- Get the time to find the next run after. It will just be the later of
    -- now() + 1m and the start date for the time being, however, we might want to
    -- do more complex things using this value in the future.
    IF date_trunc('MINUTE', jscstart) > date_trunc('MINUTE', (now() + '1 Minute'::interval)) THEN
        runafter := date_trunc('MINUTE', jscstart);
    ELSE
        runafter := date_trunc('MINUTE', (now() + '1 Minute'::interval));
    END IF;

    --
    -- Enter a loop, generating next run timestamps until we find one
    -- that falls on the required weekday, and is not matched by an exception
    --

    WHILE bingo = FALSE LOOP

        --
        -- Get the next run year
        --
        nextyear := date_part('YEAR', runafter);

        --
        -- Get the next run month
        --
        nextmonth := date_part('MONTH', runafter);
        gotit := FALSE;
        FOR i IN (nextmonth) .. 12 LOOP
            IF jscmonths[i] = TRUE THEN
                nextmonth := i;
                gotit := TRUE;
                foundval := TRUE;
                EXIT;
            END IF;
        END LOOP;
        IF gotit = FALSE THEN
            FOR i IN 1 .. (nextmonth - 1) LOOP
                IF jscmonths[i] = TRUE THEN
                    nextmonth := i;

                    -- Wrap into next year
                    nextyear := nextyear + 1;
                    gotit := TRUE;
                    foundval := TRUE;
                    EXIT;
                END IF;
           END LOOP;
        END IF;

        --
        -- Get the next run day
        --
        -- If the year, or month have incremented, get the lowest day,
        -- otherwise look for the next day matching or after today.
        IF (nextyear > date_part('YEAR', runafter) OR nextmonth > date_part('MONTH', runafter)) THEN
            nextday := 1;
            FOR i IN 1 .. 32 LOOP
                IF jscmonthdays[i] = TRUE THEN
                    nextday := i;
                    foundval := TRUE;
                    EXIT;
                END IF;
            END LOOP;
        ELSE
            nextday := date_part('DAY', runafter);
            gotit := FALSE;
            FOR i IN nextday .. 32 LOOP
                IF jscmonthdays[i] = TRUE THEN
                    nextday := i;
                    gotit := TRUE;
                    foundval := TRUE;
                    EXIT;
                END IF;
            END LOOP;
            IF gotit = FALSE THEN
                FOR i IN 1 .. (nextday - 1) LOOP
                    IF jscmonthdays[i] = TRUE THEN
                        nextday := i;

                        -- Wrap into next month
                        IF nextmonth = 12 THEN
                            nextyear := nextyear + 1;
                            nextmonth := 1;
                        ELSE
                            nextmonth := nextmonth + 1;
                        END IF;
                        gotit := TRUE;
                        foundval := TRUE;
                        EXIT;
                    END IF;
                END LOOP;
            END IF;
        END IF;

        -- Was the last day flag selected?
        IF nextday = 32 THEN
            IF nextmonth = 1 THEN
                nextday := 31;
            ELSIF nextmonth = 2 THEN
                IF pgagent.pga_is_leap_year(nextyear) = TRUE THEN
                    nextday := 29;
                ELSE
                    nextday := 28;
                END IF;
            ELSIF nextmonth = 3 THEN
                nextday := 31;
            ELSIF nextmonth = 4 THEN
                nextday := 30;
            ELSIF nextmonth = 5 THEN
                nextday := 31;
            ELSIF nextmonth = 6 THEN
                nextday := 30;
            ELSIF nextmonth = 7 THEN
                nextday := 31;
            ELSIF nextmonth = 8 THEN
                nextday := 31;
            ELSIF nextmonth = 9 THEN
                nextday := 30;
            ELSIF nextmonth = 10 THEN
                nextday := 31;
            ELSIF nextmonth = 11 THEN
                nextday := 30;
            ELSIF nextmonth = 12 THEN
                nextday := 31;
            END IF;
        END IF;

        --
        -- Get the next run hour
        --
        -- If the year, month or day have incremented, get the lowest hour,
        -- otherwise look for the next hour matching or after the current one.
        IF (nextyear > date_part('YEAR', runafter) OR nextmonth > date_part('MONTH', runafter) OR nextday > date_part('DAY', runafter) OR daytweak = TRUE) THEN
            nexthour := 0;
            FOR i IN 1 .. 24 LOOP
                IF jschours[i] = TRUE THEN
                    nexthour := i - 1;
                    foundval := TRUE;
                    EXIT;
                END IF;
            END LOOP;
        ELSE
            nexthour := date_part('HOUR', runafter);
            gotit := FALSE;
            FOR i IN (nexthour + 1) .. 24 LOOP
                IF jschours[i] = TRUE THEN
                    nexthour := i - 1;
                    gotit := TRUE;
                    foundval := TRUE;
                    EXIT;
                END IF;
            END LOOP;
            IF gotit = FALSE THEN
                FOR i IN 1 .. nexthour LOOP
                    IF jschours[i] = TRUE THEN
                        nexthour := i - 1;

                        -- Wrap into next month
                        IF (nextmonth = 1 OR nextmonth = 3 OR nextmonth = 5 OR nextmonth = 7 OR nextmonth = 8 OR nextmonth = 10 OR nextmonth = 12) THEN
                            d = 31;
                        ELSIF (nextmonth = 4 OR nextmonth = 6 OR nextmonth = 9 OR nextmonth = 11) THEN
                            d = 30;
                        ELSE
                            IF pgagent.pga_is_leap_year(nextyear) = TRUE THEN
                                d := 29;
                            ELSE
                                d := 28;
                            END IF;
                        END IF;

                        IF nextday = d THEN
                            nextday := 1;
                            IF nextmonth = 12 THEN
                                nextyear := nextyear + 1;
                                nextmonth := 1;
                            ELSE
                                nextmonth := nextmonth + 1;
                            END IF;
                        ELSE
                            nextday := nextday + 1;
                        END IF;

                        gotit := TRUE;
                        foundval := TRUE;
                        EXIT;
                    END IF;
                END LOOP;
            END IF;
        END IF;

        --
        -- Get the next run minute
        --
        -- If the year, month day or hour have incremented, get the lowest minute,
        -- otherwise look for the next minute matching or after the current one.
        IF (nextyear > date_part('YEAR', runafter) OR nextmonth > date_part('MONTH', runafter) OR nextday > date_part('DAY', runafter) OR nexthour > date_part('HOUR', runafter) OR daytweak = TRUE) THEN
            nextminute := 0;
            IF minutetweak = TRUE THEN
        d := 1;
            ELSE
        d := date_part('YEAR', runafter)::int2;
            END IF;
            FOR i IN d .. 60 LOOP
                IF jscminutes[i] = TRUE THEN
                    nextminute := i - 1;
                    foundval := TRUE;
                    EXIT;
                END IF;
            END LOOP;
        ELSE
            nextminute := date_part('MINUTE', runafter);
            gotit := FALSE;
            FOR i IN (nextminute + 1) .. 60 LOOP
                IF jscminutes[i] = TRUE THEN
                    nextminute := i - 1;
                    gotit := TRUE;
                    foundval := TRUE;
                    EXIT;
                END IF;
            END LOOP;
            IF gotit = FALSE THEN
                FOR i IN 1 .. nextminute LOOP
                    IF jscminutes[i] = TRUE THEN
                        nextminute := i - 1;

                        -- Wrap into next hour
                        IF (nextmonth = 1 OR nextmonth = 3 OR nextmonth = 5 OR nextmonth = 7 OR nextmonth = 8 OR nextmonth = 10 OR nextmonth = 12) THEN
                            d = 31;
                        ELSIF (nextmonth = 4 OR nextmonth = 6 OR nextmonth = 9 OR nextmonth = 11) THEN
                            d = 30;
                        ELSE
                            IF pgagent.pga_is_leap_year(nextyear) = TRUE THEN
                                d := 29;
                            ELSE
                                d := 28;
                            END IF;
                        END IF;

                        IF nexthour = 23 THEN
                            nexthour = 0;
                            IF nextday = d THEN
                                nextday := 1;
                                IF nextmonth = 12 THEN
                                    nextyear := nextyear + 1;
                                    nextmonth := 1;
                                ELSE
                                    nextmonth := nextmonth + 1;
                                END IF;
                            ELSE
                                nextday := nextday + 1;
                            END IF;
                        ELSE
                            nexthour := nexthour + 1;
                        END IF;

                        gotit := TRUE;
                        foundval := TRUE;
                        EXIT;
                    END IF;
                END LOOP;
            END IF;
        END IF;

        -- Build the result, and check it is not the same as runafter - this may
        -- happen if all array entries are set to false. In this case, add a minute.

        nextrun := (nextyear::varchar || '-'::varchar || nextmonth::varchar || '-' || nextday::varchar || ' ' || nexthour::varchar || ':' || nextminute::varchar)::timestamptz;

        IF nextrun = runafter AND foundval = FALSE THEN
                nextrun := nextrun + INTERVAL '1 Minute';
        END IF;

        -- If the result is past the end date, exit.
        IF nextrun > jscend THEN
            RETURN NULL;
        END IF;

        -- Check to ensure that the nextrun time is actually still valid. Its
        -- possible that wrapped values may have carried the nextrun onto an
        -- invalid time or date.
        IF ((jscminutes = '{f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}' OR jscminutes[date_part('MINUTE', nextrun) + 1] = TRUE) AND
            (jschours = '{f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}' OR jschours[date_part('HOUR', nextrun) + 1] = TRUE) AND
            (jscmonthdays = '{f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}' OR jscmonthdays[date_part('DAY', nextrun)] = TRUE OR
            (jscmonthdays = '{f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,t}' AND
             ((date_part('MONTH', nextrun) IN (1,3,5,7,8,10,12) AND date_part('DAY', nextrun) = 31) OR
              (date_part('MONTH', nextrun) IN (4,6,9,11) AND date_part('DAY', nextrun) = 30) OR
              (date_part('MONTH', nextrun) = 2 AND ((pgagent.pga_is_leap_year(date_part('DAY', nextrun)::int2) AND date_part('DAY', nextrun) = 29) OR date_part('DAY', nextrun) = 28))))) AND
            (jscmonths = '{f,f,f,f,f,f,f,f,f,f,f,f}' OR jscmonths[date_part('MONTH', nextrun)] = TRUE)) THEN


            -- Now, check to see if the nextrun time found is a) on an acceptable
            -- weekday, and b) not matched by an exception. If not, set
            -- runafter = nextrun and try again.

            -- Check for a wildcard weekday
            gotit := FALSE;
            FOR i IN 1 .. 7 LOOP
                IF jscweekdays[i] = TRUE THEN
                    gotit := TRUE;
                    EXIT;
                END IF;
            END LOOP;

            -- OK, is the correct weekday selected, or a wildcard?
            IF (jscweekdays[date_part('DOW', nextrun) + 1] = TRUE OR gotit = FALSE) THEN

                -- Check for exceptions
                SELECT INTO d jexid FROM pgagent.pga_exception WHERE jexscid = jscid AND ((jexdate = nextrun::date AND jextime = nextrun::time) OR (jexdate = nextrun::date AND jextime IS NULL) OR (jexdate IS NULL AND jextime = nextrun::time));
                IF FOUND THEN
                    -- Nuts - found an exception. Increment the time and try again
                    runafter := nextrun + INTERVAL '1 Minute';
                    bingo := FALSE;
                    minutetweak := TRUE;
            daytweak := FALSE;
                ELSE
                    bingo := TRUE;
                END IF;
            ELSE
                -- We're on the wrong week day - increment a day and try again.
                runafter := nextrun + INTERVAL '1 Day';
                bingo := FALSE;
                minutetweak := FALSE;
                daytweak := TRUE;
            END IF;

        ELSE
            runafter := nextrun + INTERVAL '1 Minute';
            bingo := FALSE;
            minutetweak := TRUE;
        daytweak := FALSE;
        END IF;

    END LOOP;

    RETURN nextrun;
END;
$_$;


ALTER FUNCTION pgagent.pga_next_schedule(integer, timestamp with time zone, timestamp with time zone, boolean[], boolean[], boolean[], boolean[], boolean[]) OWNER TO postgres;

--
-- Name: FUNCTION pga_next_schedule(integer, timestamp with time zone, timestamp with time zone, boolean[], boolean[], boolean[], boolean[], boolean[]); Type: COMMENT; Schema: pgagent; Owner: postgres
--

COMMENT ON FUNCTION pga_next_schedule(integer, timestamp with time zone, timestamp with time zone, boolean[], boolean[], boolean[], boolean[], boolean[]) IS 'Calculates the next runtime for a given schedule';


--
-- Name: pga_schedule_trigger(); Type: FUNCTION; Schema: pgagent; Owner: postgres
--

CREATE FUNCTION pga_schedule_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        -- update pga_job from remaining schedules
        -- the actual calculation of jobnextrun will be performed in the trigger
        UPDATE pgagent.pga_job
           SET jobnextrun = NULL
         WHERE jobenabled AND jobid=OLD.jscjobid;
        RETURN OLD;
    ELSE
        UPDATE pgagent.pga_job
           SET jobnextrun = NULL
         WHERE jobenabled AND jobid=NEW.jscjobid;
        RETURN NEW;
    END IF;
END;
$$;


ALTER FUNCTION pgagent.pga_schedule_trigger() OWNER TO postgres;

--
-- Name: FUNCTION pga_schedule_trigger(); Type: COMMENT; Schema: pgagent; Owner: postgres
--

COMMENT ON FUNCTION pga_schedule_trigger() IS 'Update the job''s next run time whenever a schedule changes';


--
-- Name: pgagent_schema_version(); Type: FUNCTION; Schema: pgagent; Owner: postgres
--

CREATE FUNCTION pgagent_schema_version() RETURNS smallint
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- RETURNS PGAGENT MAJOR VERSION
    -- WE WILL CHANGE THE MAJOR VERSION, ONLY IF THERE IS A SCHEMA CHANGE
    RETURN 3;
END;
$$;


ALTER FUNCTION pgagent.pgagent_schema_version() OWNER TO postgres;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: pga_exception; Type: TABLE; Schema: pgagent; Owner: postgres
--

CREATE TABLE pga_exception (
    jexid integer NOT NULL,
    jexscid integer NOT NULL,
    jexdate date,
    jextime time without time zone
);


ALTER TABLE pga_exception OWNER TO postgres;

--
-- Name: pga_exception_jexid_seq; Type: SEQUENCE; Schema: pgagent; Owner: postgres
--

CREATE SEQUENCE pga_exception_jexid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE pga_exception_jexid_seq OWNER TO postgres;

--
-- Name: pga_exception_jexid_seq; Type: SEQUENCE OWNED BY; Schema: pgagent; Owner: postgres
--

ALTER SEQUENCE pga_exception_jexid_seq OWNED BY pga_exception.jexid;


--
-- Name: pga_job; Type: TABLE; Schema: pgagent; Owner: postgres
--

CREATE TABLE pga_job (
    jobid integer NOT NULL,
    jobjclid integer NOT NULL,
    jobname text NOT NULL,
    jobdesc text DEFAULT ''::text NOT NULL,
    jobhostagent text DEFAULT ''::text NOT NULL,
    jobenabled boolean DEFAULT true NOT NULL,
    jobcreated timestamp with time zone DEFAULT now() NOT NULL,
    jobchanged timestamp with time zone DEFAULT now() NOT NULL,
    jobagentid integer,
    jobnextrun timestamp with time zone,
    joblastrun timestamp with time zone
);


ALTER TABLE pga_job OWNER TO postgres;

--
-- Name: TABLE pga_job; Type: COMMENT; Schema: pgagent; Owner: postgres
--

COMMENT ON TABLE pga_job IS 'Job main entry';


--
-- Name: COLUMN pga_job.jobagentid; Type: COMMENT; Schema: pgagent; Owner: postgres
--

COMMENT ON COLUMN pga_job.jobagentid IS 'Agent that currently executes this job.';


--
-- Name: pga_job_jobid_seq; Type: SEQUENCE; Schema: pgagent; Owner: postgres
--

CREATE SEQUENCE pga_job_jobid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE pga_job_jobid_seq OWNER TO postgres;

--
-- Name: pga_job_jobid_seq; Type: SEQUENCE OWNED BY; Schema: pgagent; Owner: postgres
--

ALTER SEQUENCE pga_job_jobid_seq OWNED BY pga_job.jobid;


--
-- Name: pga_jobagent; Type: TABLE; Schema: pgagent; Owner: postgres
--

CREATE TABLE pga_jobagent (
    jagpid integer NOT NULL,
    jaglogintime timestamp with time zone DEFAULT now() NOT NULL,
    jagstation text NOT NULL
);


ALTER TABLE pga_jobagent OWNER TO postgres;

--
-- Name: TABLE pga_jobagent; Type: COMMENT; Schema: pgagent; Owner: postgres
--

COMMENT ON TABLE pga_jobagent IS 'Active job agents';


--
-- Name: pga_jobclass; Type: TABLE; Schema: pgagent; Owner: postgres
--

CREATE TABLE pga_jobclass (
    jclid integer NOT NULL,
    jclname text NOT NULL
);


ALTER TABLE pga_jobclass OWNER TO postgres;

--
-- Name: TABLE pga_jobclass; Type: COMMENT; Schema: pgagent; Owner: postgres
--

COMMENT ON TABLE pga_jobclass IS 'Job classification';


--
-- Name: pga_jobclass_jclid_seq; Type: SEQUENCE; Schema: pgagent; Owner: postgres
--

CREATE SEQUENCE pga_jobclass_jclid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE pga_jobclass_jclid_seq OWNER TO postgres;

--
-- Name: pga_jobclass_jclid_seq; Type: SEQUENCE OWNED BY; Schema: pgagent; Owner: postgres
--

ALTER SEQUENCE pga_jobclass_jclid_seq OWNED BY pga_jobclass.jclid;


--
-- Name: pga_joblog; Type: TABLE; Schema: pgagent; Owner: postgres
--

CREATE TABLE pga_joblog (
    jlgid integer NOT NULL,
    jlgjobid integer NOT NULL,
    jlgstatus character(1) DEFAULT 'r'::bpchar NOT NULL,
    jlgstart timestamp with time zone DEFAULT now() NOT NULL,
    jlgduration interval,
    CONSTRAINT pga_joblog_jlgstatus_check CHECK ((jlgstatus = ANY (ARRAY['r'::bpchar, 's'::bpchar, 'f'::bpchar, 'i'::bpchar, 'd'::bpchar])))
);


ALTER TABLE pga_joblog OWNER TO postgres;

--
-- Name: TABLE pga_joblog; Type: COMMENT; Schema: pgagent; Owner: postgres
--

COMMENT ON TABLE pga_joblog IS 'Job run logs.';


--
-- Name: COLUMN pga_joblog.jlgstatus; Type: COMMENT; Schema: pgagent; Owner: postgres
--

COMMENT ON COLUMN pga_joblog.jlgstatus IS 'Status of job: r=running, s=successfully finished, f=failed, i=no steps to execute, d=aborted';


--
-- Name: pga_joblog_jlgid_seq; Type: SEQUENCE; Schema: pgagent; Owner: postgres
--

CREATE SEQUENCE pga_joblog_jlgid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE pga_joblog_jlgid_seq OWNER TO postgres;

--
-- Name: pga_joblog_jlgid_seq; Type: SEQUENCE OWNED BY; Schema: pgagent; Owner: postgres
--

ALTER SEQUENCE pga_joblog_jlgid_seq OWNED BY pga_joblog.jlgid;


--
-- Name: pga_jobstep; Type: TABLE; Schema: pgagent; Owner: postgres
--

CREATE TABLE pga_jobstep (
    jstid integer NOT NULL,
    jstjobid integer NOT NULL,
    jstname text NOT NULL,
    jstdesc text DEFAULT ''::text NOT NULL,
    jstenabled boolean DEFAULT true NOT NULL,
    jstkind character(1) NOT NULL,
    jstcode text NOT NULL,
    jstconnstr text DEFAULT ''::text NOT NULL,
    jstdbname name DEFAULT ''::name NOT NULL,
    jstonerror character(1) DEFAULT 'f'::bpchar NOT NULL,
    jscnextrun timestamp with time zone,
    CONSTRAINT pga_jobstep_check CHECK ((((jstconnstr <> ''::text) AND (jstkind = 's'::bpchar)) OR ((jstconnstr = ''::text) AND ((jstkind = 'b'::bpchar) OR (jstdbname <> ''::name))))),
    CONSTRAINT pga_jobstep_check1 CHECK ((((jstdbname <> ''::name) AND (jstkind = 's'::bpchar)) OR ((jstdbname = ''::name) AND ((jstkind = 'b'::bpchar) OR (jstconnstr <> ''::text))))),
    CONSTRAINT pga_jobstep_jstkind_check CHECK ((jstkind = ANY (ARRAY['b'::bpchar, 's'::bpchar]))),
    CONSTRAINT pga_jobstep_jstonerror_check CHECK ((jstonerror = ANY (ARRAY['f'::bpchar, 's'::bpchar, 'i'::bpchar])))
);


ALTER TABLE pga_jobstep OWNER TO postgres;

--
-- Name: TABLE pga_jobstep; Type: COMMENT; Schema: pgagent; Owner: postgres
--

COMMENT ON TABLE pga_jobstep IS 'Job step to be executed';


--
-- Name: COLUMN pga_jobstep.jstkind; Type: COMMENT; Schema: pgagent; Owner: postgres
--

COMMENT ON COLUMN pga_jobstep.jstkind IS 'Kind of jobstep: s=sql, b=batch';


--
-- Name: COLUMN pga_jobstep.jstonerror; Type: COMMENT; Schema: pgagent; Owner: postgres
--

COMMENT ON COLUMN pga_jobstep.jstonerror IS 'What to do if step returns an error: f=fail the job, s=mark step as succeeded and continue, i=mark as fail but ignore it and proceed';


--
-- Name: pga_jobstep_jstid_seq; Type: SEQUENCE; Schema: pgagent; Owner: postgres
--

CREATE SEQUENCE pga_jobstep_jstid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE pga_jobstep_jstid_seq OWNER TO postgres;

--
-- Name: pga_jobstep_jstid_seq; Type: SEQUENCE OWNED BY; Schema: pgagent; Owner: postgres
--

ALTER SEQUENCE pga_jobstep_jstid_seq OWNED BY pga_jobstep.jstid;


--
-- Name: pga_jobsteplog; Type: TABLE; Schema: pgagent; Owner: postgres
--

CREATE TABLE pga_jobsteplog (
    jslid integer NOT NULL,
    jsljlgid integer NOT NULL,
    jsljstid integer NOT NULL,
    jslstatus character(1) DEFAULT 'r'::bpchar NOT NULL,
    jslresult integer,
    jslstart timestamp with time zone DEFAULT now() NOT NULL,
    jslduration interval,
    jsloutput text,
    CONSTRAINT pga_jobsteplog_jslstatus_check CHECK ((jslstatus = ANY (ARRAY['r'::bpchar, 's'::bpchar, 'i'::bpchar, 'f'::bpchar, 'd'::bpchar])))
);


ALTER TABLE pga_jobsteplog OWNER TO postgres;

--
-- Name: TABLE pga_jobsteplog; Type: COMMENT; Schema: pgagent; Owner: postgres
--

COMMENT ON TABLE pga_jobsteplog IS 'Job step run logs.';


--
-- Name: COLUMN pga_jobsteplog.jslstatus; Type: COMMENT; Schema: pgagent; Owner: postgres
--

COMMENT ON COLUMN pga_jobsteplog.jslstatus IS 'Status of job step: r=running, s=successfully finished,  f=failed stopping job, i=ignored failure, d=aborted';


--
-- Name: COLUMN pga_jobsteplog.jslresult; Type: COMMENT; Schema: pgagent; Owner: postgres
--

COMMENT ON COLUMN pga_jobsteplog.jslresult IS 'Return code of job step';


--
-- Name: pga_jobsteplog_jslid_seq; Type: SEQUENCE; Schema: pgagent; Owner: postgres
--

CREATE SEQUENCE pga_jobsteplog_jslid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE pga_jobsteplog_jslid_seq OWNER TO postgres;

--
-- Name: pga_jobsteplog_jslid_seq; Type: SEQUENCE OWNED BY; Schema: pgagent; Owner: postgres
--

ALTER SEQUENCE pga_jobsteplog_jslid_seq OWNED BY pga_jobsteplog.jslid;


--
-- Name: pga_schedule; Type: TABLE; Schema: pgagent; Owner: postgres
--

CREATE TABLE pga_schedule (
    jscid integer NOT NULL,
    jscjobid integer NOT NULL,
    jscname text NOT NULL,
    jscdesc text DEFAULT ''::text NOT NULL,
    jscenabled boolean DEFAULT true NOT NULL,
    jscstart timestamp with time zone DEFAULT now() NOT NULL,
    jscend timestamp with time zone,
    jscminutes boolean[] DEFAULT '{f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}'::boolean[] NOT NULL,
    jschours boolean[] DEFAULT '{f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}'::boolean[] NOT NULL,
    jscweekdays boolean[] DEFAULT '{f,f,f,f,f,f,f}'::boolean[] NOT NULL,
    jscmonthdays boolean[] DEFAULT '{f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}'::boolean[] NOT NULL,
    jscmonths boolean[] DEFAULT '{f,f,f,f,f,f,f,f,f,f,f,f}'::boolean[] NOT NULL,
    CONSTRAINT pga_schedule_jschours_size CHECK ((array_upper(jschours, 1) = 24)),
    CONSTRAINT pga_schedule_jscminutes_size CHECK ((array_upper(jscminutes, 1) = 60)),
    CONSTRAINT pga_schedule_jscmonthdays_size CHECK ((array_upper(jscmonthdays, 1) = 32)),
    CONSTRAINT pga_schedule_jscmonths_size CHECK ((array_upper(jscmonths, 1) = 12)),
    CONSTRAINT pga_schedule_jscweekdays_size CHECK ((array_upper(jscweekdays, 1) = 7))
);


ALTER TABLE pga_schedule OWNER TO postgres;

--
-- Name: TABLE pga_schedule; Type: COMMENT; Schema: pgagent; Owner: postgres
--

COMMENT ON TABLE pga_schedule IS 'Job schedule exceptions';


--
-- Name: pga_schedule_jscid_seq; Type: SEQUENCE; Schema: pgagent; Owner: postgres
--

CREATE SEQUENCE pga_schedule_jscid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE pga_schedule_jscid_seq OWNER TO postgres;

--
-- Name: pga_schedule_jscid_seq; Type: SEQUENCE OWNED BY; Schema: pgagent; Owner: postgres
--

ALTER SEQUENCE pga_schedule_jscid_seq OWNED BY pga_schedule.jscid;


SET search_path = public, pg_catalog;

--
-- Name: admin; Type: TABLE; Schema: public; Owner: Andrew
--

CREATE TABLE admin (
    adminid integer NOT NULL,
    loginid integer
);


ALTER TABLE admin OWNER TO "Andrew";

--
-- Name: admin_adminid_seq; Type: SEQUENCE; Schema: public; Owner: Andrew
--

CREATE SEQUENCE admin_adminid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE admin_adminid_seq OWNER TO "Andrew";

--
-- Name: admin_adminid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: Andrew
--

ALTER SEQUENCE admin_adminid_seq OWNED BY admin.adminid;


--
-- Name: char; Type: TABLE; Schema: public; Owner: Andrew
--

CREATE TABLE "char" (
    charid integer NOT NULL,
    charname text,
    charreal text,
    picture character(30),
    earthname text,
    extra jsonb
);


ALTER TABLE "char" OWNER TO "Andrew";

--
-- Name: char_charid_seq; Type: SEQUENCE; Schema: public; Owner: Andrew
--

CREATE SEQUENCE char_charid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE char_charid_seq OWNER TO "Andrew";

--
-- Name: char_charid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: Andrew
--

ALTER SEQUENCE char_charid_seq OWNED BY "char".charid;


--
-- Name: fav; Type: TABLE; Schema: public; Owner: Andrew
--

CREATE TABLE fav (
    favid integer NOT NULL,
    userid integer,
    charid integer[]
);


ALTER TABLE fav OWNER TO "Andrew";

--
-- Name: fav_favid_seq; Type: SEQUENCE; Schema: public; Owner: Andrew
--

CREATE SEQUENCE fav_favid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE fav_favid_seq OWNER TO "Andrew";

--
-- Name: fav_favid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: Andrew
--

ALTER SEQUENCE fav_favid_seq OWNED BY fav.favid;


--
-- Name: login; Type: TABLE; Schema: public; Owner: Andrew
--

CREATE TABLE login (
    loginid integer NOT NULL,
    firstname text,
    lastname text,
    login text,
    hashedpassword character(75),
    profileimg character(30),
    email text
);


ALTER TABLE login OWNER TO "Andrew";

--
-- Name: login_loginid_seq; Type: SEQUENCE; Schema: public; Owner: Andrew
--

CREATE SEQUENCE login_loginid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE login_loginid_seq OWNER TO "Andrew";

--
-- Name: login_loginid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: Andrew
--

ALTER SEQUENCE login_loginid_seq OWNED BY login.loginid;


SET search_path = pgagent, pg_catalog;

--
-- Name: jexid; Type: DEFAULT; Schema: pgagent; Owner: postgres
--

ALTER TABLE ONLY pga_exception ALTER COLUMN jexid SET DEFAULT nextval('pga_exception_jexid_seq'::regclass);


--
-- Name: jobid; Type: DEFAULT; Schema: pgagent; Owner: postgres
--

ALTER TABLE ONLY pga_job ALTER COLUMN jobid SET DEFAULT nextval('pga_job_jobid_seq'::regclass);


--
-- Name: jclid; Type: DEFAULT; Schema: pgagent; Owner: postgres
--

ALTER TABLE ONLY pga_jobclass ALTER COLUMN jclid SET DEFAULT nextval('pga_jobclass_jclid_seq'::regclass);


--
-- Name: jlgid; Type: DEFAULT; Schema: pgagent; Owner: postgres
--

ALTER TABLE ONLY pga_joblog ALTER COLUMN jlgid SET DEFAULT nextval('pga_joblog_jlgid_seq'::regclass);


--
-- Name: jstid; Type: DEFAULT; Schema: pgagent; Owner: postgres
--

ALTER TABLE ONLY pga_jobstep ALTER COLUMN jstid SET DEFAULT nextval('pga_jobstep_jstid_seq'::regclass);


--
-- Name: jslid; Type: DEFAULT; Schema: pgagent; Owner: postgres
--

ALTER TABLE ONLY pga_jobsteplog ALTER COLUMN jslid SET DEFAULT nextval('pga_jobsteplog_jslid_seq'::regclass);


--
-- Name: jscid; Type: DEFAULT; Schema: pgagent; Owner: postgres
--

ALTER TABLE ONLY pga_schedule ALTER COLUMN jscid SET DEFAULT nextval('pga_schedule_jscid_seq'::regclass);


SET search_path = public, pg_catalog;

--
-- Name: adminid; Type: DEFAULT; Schema: public; Owner: Andrew
--

ALTER TABLE ONLY admin ALTER COLUMN adminid SET DEFAULT nextval('admin_adminid_seq'::regclass);


--
-- Name: charid; Type: DEFAULT; Schema: public; Owner: Andrew
--

ALTER TABLE ONLY "char" ALTER COLUMN charid SET DEFAULT nextval('char_charid_seq'::regclass);


--
-- Name: favid; Type: DEFAULT; Schema: public; Owner: Andrew
--

ALTER TABLE ONLY fav ALTER COLUMN favid SET DEFAULT nextval('fav_favid_seq'::regclass);


--
-- Name: loginid; Type: DEFAULT; Schema: public; Owner: Andrew
--

ALTER TABLE ONLY login ALTER COLUMN loginid SET DEFAULT nextval('login_loginid_seq'::regclass);


SET search_path = pgagent, pg_catalog;

--
-- Data for Name: pga_exception; Type: TABLE DATA; Schema: pgagent; Owner: postgres
--

COPY pga_exception (jexid, jexscid, jexdate, jextime) FROM stdin;
\.
COPY pga_exception (jexid, jexscid, jexdate, jextime) FROM '$$PATH$$/2271.dat';

--
-- Name: pga_exception_jexid_seq; Type: SEQUENCE SET; Schema: pgagent; Owner: postgres
--

SELECT pg_catalog.setval('pga_exception_jexid_seq', 1, false);


--
-- Data for Name: pga_job; Type: TABLE DATA; Schema: pgagent; Owner: postgres
--

COPY pga_job (jobid, jobjclid, jobname, jobdesc, jobhostagent, jobenabled, jobcreated, jobchanged, jobagentid, jobnextrun, joblastrun) FROM stdin;
\.
COPY pga_job (jobid, jobjclid, jobname, jobdesc, jobhostagent, jobenabled, jobcreated, jobchanged, jobagentid, jobnextrun, joblastrun) FROM '$$PATH$$/2265.dat';

--
-- Name: pga_job_jobid_seq; Type: SEQUENCE SET; Schema: pgagent; Owner: postgres
--

SELECT pg_catalog.setval('pga_job_jobid_seq', 1, false);


--
-- Data for Name: pga_jobagent; Type: TABLE DATA; Schema: pgagent; Owner: postgres
--

COPY pga_jobagent (jagpid, jaglogintime, jagstation) FROM stdin;
\.
COPY pga_jobagent (jagpid, jaglogintime, jagstation) FROM '$$PATH$$/2261.dat';

--
-- Data for Name: pga_jobclass; Type: TABLE DATA; Schema: pgagent; Owner: postgres
--

COPY pga_jobclass (jclid, jclname) FROM stdin;
\.
COPY pga_jobclass (jclid, jclname) FROM '$$PATH$$/2263.dat';

--
-- Name: pga_jobclass_jclid_seq; Type: SEQUENCE SET; Schema: pgagent; Owner: postgres
--

SELECT pg_catalog.setval('pga_jobclass_jclid_seq', 5, true);


--
-- Data for Name: pga_joblog; Type: TABLE DATA; Schema: pgagent; Owner: postgres
--

COPY pga_joblog (jlgid, jlgjobid, jlgstatus, jlgstart, jlgduration) FROM stdin;
\.
COPY pga_joblog (jlgid, jlgjobid, jlgstatus, jlgstart, jlgduration) FROM '$$PATH$$/2273.dat';

--
-- Name: pga_joblog_jlgid_seq; Type: SEQUENCE SET; Schema: pgagent; Owner: postgres
--

SELECT pg_catalog.setval('pga_joblog_jlgid_seq', 1, false);


--
-- Data for Name: pga_jobstep; Type: TABLE DATA; Schema: pgagent; Owner: postgres
--

COPY pga_jobstep (jstid, jstjobid, jstname, jstdesc, jstenabled, jstkind, jstcode, jstconnstr, jstdbname, jstonerror, jscnextrun) FROM stdin;
\.
COPY pga_jobstep (jstid, jstjobid, jstname, jstdesc, jstenabled, jstkind, jstcode, jstconnstr, jstdbname, jstonerror, jscnextrun) FROM '$$PATH$$/2267.dat';

--
-- Name: pga_jobstep_jstid_seq; Type: SEQUENCE SET; Schema: pgagent; Owner: postgres
--

SELECT pg_catalog.setval('pga_jobstep_jstid_seq', 1, false);


--
-- Data for Name: pga_jobsteplog; Type: TABLE DATA; Schema: pgagent; Owner: postgres
--

COPY pga_jobsteplog (jslid, jsljlgid, jsljstid, jslstatus, jslresult, jslstart, jslduration, jsloutput) FROM stdin;
\.
COPY pga_jobsteplog (jslid, jsljlgid, jsljstid, jslstatus, jslresult, jslstart, jslduration, jsloutput) FROM '$$PATH$$/2275.dat';

--
-- Name: pga_jobsteplog_jslid_seq; Type: SEQUENCE SET; Schema: pgagent; Owner: postgres
--

SELECT pg_catalog.setval('pga_jobsteplog_jslid_seq', 1, false);


--
-- Data for Name: pga_schedule; Type: TABLE DATA; Schema: pgagent; Owner: postgres
--

COPY pga_schedule (jscid, jscjobid, jscname, jscdesc, jscenabled, jscstart, jscend, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) FROM stdin;
\.
COPY pga_schedule (jscid, jscjobid, jscname, jscdesc, jscenabled, jscstart, jscend, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) FROM '$$PATH$$/2269.dat';

--
-- Name: pga_schedule_jscid_seq; Type: SEQUENCE SET; Schema: pgagent; Owner: postgres
--

SELECT pg_catalog.setval('pga_schedule_jscid_seq', 1, false);


SET search_path = public, pg_catalog;

--
-- Data for Name: admin; Type: TABLE DATA; Schema: public; Owner: Andrew
--

COPY admin (adminid, loginid) FROM stdin;
\.
COPY admin (adminid, loginid) FROM '$$PATH$$/2277.dat';

--
-- Name: admin_adminid_seq; Type: SEQUENCE SET; Schema: public; Owner: Andrew
--

SELECT pg_catalog.setval('admin_adminid_seq', 1, false);


--
-- Data for Name: char; Type: TABLE DATA; Schema: public; Owner: Andrew
--

COPY "char" (charid, charname, charreal, picture, earthname, extra) FROM stdin;
\.
COPY "char" (charid, charname, charreal, picture, earthname, extra) FROM '$$PATH$$/2256.dat';

--
-- Name: char_charid_seq; Type: SEQUENCE SET; Schema: public; Owner: Andrew
--

SELECT pg_catalog.setval('char_charid_seq', 1, false);


--
-- Data for Name: fav; Type: TABLE DATA; Schema: public; Owner: Andrew
--

COPY fav (favid, userid, charid) FROM stdin;
\.
COPY fav (favid, userid, charid) FROM '$$PATH$$/2258.dat';

--
-- Name: fav_favid_seq; Type: SEQUENCE SET; Schema: public; Owner: Andrew
--

SELECT pg_catalog.setval('fav_favid_seq', 1, false);


--
-- Data for Name: login; Type: TABLE DATA; Schema: public; Owner: Andrew
--

COPY login (loginid, firstname, lastname, login, hashedpassword, profileimg, email) FROM stdin;
\.
COPY login (loginid, firstname, lastname, login, hashedpassword, profileimg, email) FROM '$$PATH$$/2260.dat';

--
-- Name: login_loginid_seq; Type: SEQUENCE SET; Schema: public; Owner: Andrew
--

SELECT pg_catalog.setval('login_loginid_seq', 6, true);


SET search_path = pgagent, pg_catalog;

--
-- Name: pga_exception_pkey; Type: CONSTRAINT; Schema: pgagent; Owner: postgres
--

ALTER TABLE ONLY pga_exception
    ADD CONSTRAINT pga_exception_pkey PRIMARY KEY (jexid);


--
-- Name: pga_job_pkey; Type: CONSTRAINT; Schema: pgagent; Owner: postgres
--

ALTER TABLE ONLY pga_job
    ADD CONSTRAINT pga_job_pkey PRIMARY KEY (jobid);


--
-- Name: pga_jobagent_pkey; Type: CONSTRAINT; Schema: pgagent; Owner: postgres
--

ALTER TABLE ONLY pga_jobagent
    ADD CONSTRAINT pga_jobagent_pkey PRIMARY KEY (jagpid);


--
-- Name: pga_jobclass_pkey; Type: CONSTRAINT; Schema: pgagent; Owner: postgres
--

ALTER TABLE ONLY pga_jobclass
    ADD CONSTRAINT pga_jobclass_pkey PRIMARY KEY (jclid);


--
-- Name: pga_joblog_pkey; Type: CONSTRAINT; Schema: pgagent; Owner: postgres
--

ALTER TABLE ONLY pga_joblog
    ADD CONSTRAINT pga_joblog_pkey PRIMARY KEY (jlgid);


--
-- Name: pga_jobstep_pkey; Type: CONSTRAINT; Schema: pgagent; Owner: postgres
--

ALTER TABLE ONLY pga_jobstep
    ADD CONSTRAINT pga_jobstep_pkey PRIMARY KEY (jstid);


--
-- Name: pga_jobsteplog_pkey; Type: CONSTRAINT; Schema: pgagent; Owner: postgres
--

ALTER TABLE ONLY pga_jobsteplog
    ADD CONSTRAINT pga_jobsteplog_pkey PRIMARY KEY (jslid);


--
-- Name: pga_schedule_pkey; Type: CONSTRAINT; Schema: pgagent; Owner: postgres
--

ALTER TABLE ONLY pga_schedule
    ADD CONSTRAINT pga_schedule_pkey PRIMARY KEY (jscid);


--
-- Name: pga_exception_datetime; Type: INDEX; Schema: pgagent; Owner: postgres
--

CREATE UNIQUE INDEX pga_exception_datetime ON pga_exception USING btree (jexdate, jextime);


--
-- Name: pga_exception_jexscid; Type: INDEX; Schema: pgagent; Owner: postgres
--

CREATE INDEX pga_exception_jexscid ON pga_exception USING btree (jexscid);


--
-- Name: pga_jobclass_name; Type: INDEX; Schema: pgagent; Owner: postgres
--

CREATE UNIQUE INDEX pga_jobclass_name ON pga_jobclass USING btree (jclname);


--
-- Name: pga_joblog_jobid; Type: INDEX; Schema: pgagent; Owner: postgres
--

CREATE INDEX pga_joblog_jobid ON pga_joblog USING btree (jlgjobid);


--
-- Name: pga_jobschedule_jobid; Type: INDEX; Schema: pgagent; Owner: postgres
--

CREATE INDEX pga_jobschedule_jobid ON pga_schedule USING btree (jscjobid);


--
-- Name: pga_jobstep_jobid; Type: INDEX; Schema: pgagent; Owner: postgres
--

CREATE INDEX pga_jobstep_jobid ON pga_jobstep USING btree (jstjobid);


--
-- Name: pga_jobsteplog_jslid; Type: INDEX; Schema: pgagent; Owner: postgres
--

CREATE INDEX pga_jobsteplog_jslid ON pga_jobsteplog USING btree (jsljlgid);


SET search_path = public, pg_catalog;

--
-- Name: unique_admin; Type: INDEX; Schema: public; Owner: Andrew
--

CREATE UNIQUE INDEX unique_admin ON admin USING btree (adminid);


SET search_path = pgagent, pg_catalog;

--
-- Name: pga_exception_trigger; Type: TRIGGER; Schema: pgagent; Owner: postgres
--

CREATE TRIGGER pga_exception_trigger AFTER INSERT OR DELETE OR UPDATE ON pga_exception FOR EACH ROW EXECUTE PROCEDURE pga_exception_trigger();


--
-- Name: TRIGGER pga_exception_trigger ON pga_exception; Type: COMMENT; Schema: pgagent; Owner: postgres
--

COMMENT ON TRIGGER pga_exception_trigger ON pga_exception IS 'Update the job''s next run time whenever an exception changes';


--
-- Name: pga_job_trigger; Type: TRIGGER; Schema: pgagent; Owner: postgres
--

CREATE TRIGGER pga_job_trigger BEFORE UPDATE ON pga_job FOR EACH ROW EXECUTE PROCEDURE pga_job_trigger();


--
-- Name: TRIGGER pga_job_trigger ON pga_job; Type: COMMENT; Schema: pgagent; Owner: postgres
--

COMMENT ON TRIGGER pga_job_trigger ON pga_job IS 'Update the job''s next run time.';


--
-- Name: pga_schedule_trigger; Type: TRIGGER; Schema: pgagent; Owner: postgres
--

CREATE TRIGGER pga_schedule_trigger AFTER INSERT OR DELETE OR UPDATE ON pga_schedule FOR EACH ROW EXECUTE PROCEDURE pga_schedule_trigger();


--
-- Name: TRIGGER pga_schedule_trigger ON pga_schedule; Type: COMMENT; Schema: pgagent; Owner: postgres
--

COMMENT ON TRIGGER pga_schedule_trigger ON pga_schedule IS 'Update the job''s next run time whenever a schedule changes';


--
-- Name: pga_exception_jexscid_fkey; Type: FK CONSTRAINT; Schema: pgagent; Owner: postgres
--

ALTER TABLE ONLY pga_exception
    ADD CONSTRAINT pga_exception_jexscid_fkey FOREIGN KEY (jexscid) REFERENCES pga_schedule(jscid) ON UPDATE RESTRICT ON DELETE CASCADE;


--
-- Name: pga_job_jobagentid_fkey; Type: FK CONSTRAINT; Schema: pgagent; Owner: postgres
--

ALTER TABLE ONLY pga_job
    ADD CONSTRAINT pga_job_jobagentid_fkey FOREIGN KEY (jobagentid) REFERENCES pga_jobagent(jagpid) ON UPDATE RESTRICT ON DELETE SET NULL;


--
-- Name: pga_job_jobjclid_fkey; Type: FK CONSTRAINT; Schema: pgagent; Owner: postgres
--

ALTER TABLE ONLY pga_job
    ADD CONSTRAINT pga_job_jobjclid_fkey FOREIGN KEY (jobjclid) REFERENCES pga_jobclass(jclid) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: pga_joblog_jlgjobid_fkey; Type: FK CONSTRAINT; Schema: pgagent; Owner: postgres
--

ALTER TABLE ONLY pga_joblog
    ADD CONSTRAINT pga_joblog_jlgjobid_fkey FOREIGN KEY (jlgjobid) REFERENCES pga_job(jobid) ON UPDATE RESTRICT ON DELETE CASCADE;


--
-- Name: pga_jobstep_jstjobid_fkey; Type: FK CONSTRAINT; Schema: pgagent; Owner: postgres
--

ALTER TABLE ONLY pga_jobstep
    ADD CONSTRAINT pga_jobstep_jstjobid_fkey FOREIGN KEY (jstjobid) REFERENCES pga_job(jobid) ON UPDATE RESTRICT ON DELETE CASCADE;


--
-- Name: pga_jobsteplog_jsljlgid_fkey; Type: FK CONSTRAINT; Schema: pgagent; Owner: postgres
--

ALTER TABLE ONLY pga_jobsteplog
    ADD CONSTRAINT pga_jobsteplog_jsljlgid_fkey FOREIGN KEY (jsljlgid) REFERENCES pga_joblog(jlgid) ON UPDATE RESTRICT ON DELETE CASCADE;


--
-- Name: pga_jobsteplog_jsljstid_fkey; Type: FK CONSTRAINT; Schema: pgagent; Owner: postgres
--

ALTER TABLE ONLY pga_jobsteplog
    ADD CONSTRAINT pga_jobsteplog_jsljstid_fkey FOREIGN KEY (jsljstid) REFERENCES pga_jobstep(jstid) ON UPDATE RESTRICT ON DELETE CASCADE;


--
-- Name: pga_schedule_jscjobid_fkey; Type: FK CONSTRAINT; Schema: pgagent; Owner: postgres
--

ALTER TABLE ONLY pga_schedule
    ADD CONSTRAINT pga_schedule_jscjobid_fkey FOREIGN KEY (jscjobid) REFERENCES pga_job(jobid) ON UPDATE RESTRICT ON DELETE CASCADE;


--
-- Name: public; Type: ACL; Schema: -; Owner: postgres
--

REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM postgres;
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO PUBLIC;


--
-- PostgreSQL database dump complete
--

                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             