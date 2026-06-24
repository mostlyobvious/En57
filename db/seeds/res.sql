SET statement_timeout = 0;

SET lock_timeout = 0;

SET idle_in_transaction_session_timeout = 0;

SET transaction_timeout = 0;

SET client_encoding = 'UTF8';

SET standard_conforming_strings = ON;

SELECT pg_catalog.set_config('search_path', '', FALSE);

SET check_function_bodies = FALSE;

SET xmloption = CONTENT;

SET client_min_messages = WARNING;

SET row_security = OFF;

SET default_tablespace = '';

SET default_table_access_method = HEAP;

--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--
CREATE TABLE PUBLIC.AR_INTERNAL_METADATA (
    KEY character varying NOT NULL,
    VALUE character varying,
    CREATED_AT timestamp(6) without time zone NOT NULL,
    UPDATED_AT timestamp(6) without time zone NOT NULL
);

--
-- Name: event_store_events; Type: TABLE; Schema: public; Owner: -
--
CREATE TABLE PUBLIC.EVENT_STORE_EVENTS (
    ID bigint NOT NULL,
    EVENT_ID uuid NOT NULL,
    EVENT_TYPE character varying NOT NULL,
    METADATA jsonb,
    DATA jsonb NOT NULL,
    CREATED_AT timestamp(6) without time zone NOT NULL,
    VALID_AT timestamp(6) without time zone
);

--
-- Name: event_store_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--
CREATE SEQUENCE PUBLIC.EVENT_STORE_EVENTS_ID_SEQ
START WITH 1
INCREMENT BY 1
NO MINVALUE
NO MAXVALUE
CACHE 1;

--
-- Name: event_store_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--
ALTER SEQUENCE PUBLIC.EVENT_STORE_EVENTS_ID_SEQ OWNED BY PUBLIC.EVENT_STORE_EVENTS.ID;

--
-- Name: event_store_events_in_streams; Type: TABLE; Schema: public; Owner: -
--
CREATE TABLE PUBLIC.EVENT_STORE_EVENTS_IN_STREAMS (
    ID bigint NOT NULL,
    STREAM character varying NOT NULL,
    "position" integer,
    EVENT_ID uuid NOT NULL,
    CREATED_AT timestamp(6) without time zone NOT NULL
);

--
-- Name: event_store_events_in_streams_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--
CREATE SEQUENCE PUBLIC.EVENT_STORE_EVENTS_IN_STREAMS_ID_SEQ
START WITH 1
INCREMENT BY 1
NO MINVALUE
NO MAXVALUE
CACHE 1;

--
-- Name: event_store_events_in_streams_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--
ALTER SEQUENCE PUBLIC.EVENT_STORE_EVENTS_IN_STREAMS_ID_SEQ OWNED BY PUBLIC.EVENT_STORE_EVENTS_IN_STREAMS.ID;

--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--
CREATE TABLE PUBLIC.SCHEMA_MIGRATIONS (
    VERSION character varying NOT NULL
);

--
-- Name: event_store_events id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY PUBLIC.EVENT_STORE_EVENTS
ALTER COLUMN ID SET DEFAULT nextval(
    'public.event_store_events_id_seq'::regclass
);

--
-- Name: event_store_events_in_streams id; Type: DEFAULT; Schema: public; Owner: -
--
ALTER TABLE ONLY PUBLIC.EVENT_STORE_EVENTS_IN_STREAMS
ALTER COLUMN ID SET DEFAULT nextval(
    'public.event_store_events_in_streams_id_seq'::regclass
);

--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY PUBLIC.AR_INTERNAL_METADATA
ADD CONSTRAINT AR_INTERNAL_METADATA_PKEY PRIMARY KEY (KEY);

--
-- Name: event_store_events_in_streams event_store_events_in_streams_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY PUBLIC.EVENT_STORE_EVENTS_IN_STREAMS
ADD CONSTRAINT EVENT_STORE_EVENTS_IN_STREAMS_PKEY PRIMARY KEY (ID);

--
-- Name: event_store_events event_store_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY PUBLIC.EVENT_STORE_EVENTS
ADD CONSTRAINT EVENT_STORE_EVENTS_PKEY PRIMARY KEY (ID);

--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY PUBLIC.SCHEMA_MIGRATIONS
ADD CONSTRAINT SCHEMA_MIGRATIONS_PKEY PRIMARY KEY (VERSION);

--
-- Name: index_event_store_events_in_streams_on_created_at; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX INDEX_EVENT_STORE_EVENTS_IN_STREAMS_ON_CREATED_AT ON PUBLIC.EVENT_STORE_EVENTS_IN_STREAMS USING BTREE (
    CREATED_AT
);

--
-- Name: index_event_store_events_in_streams_on_event_id; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX INDEX_EVENT_STORE_EVENTS_IN_STREAMS_ON_EVENT_ID ON PUBLIC.EVENT_STORE_EVENTS_IN_STREAMS USING BTREE (
    EVENT_ID
);

--
-- Name: index_event_store_events_in_streams_on_stream_and_event_id; Type: INDEX; Schema: public; Owner: -
--
CREATE UNIQUE INDEX INDEX_EVENT_STORE_EVENTS_IN_STREAMS_ON_STREAM_AND_EVENT_ID ON PUBLIC.EVENT_STORE_EVENTS_IN_STREAMS USING BTREE (
    STREAM, EVENT_ID
);

--
-- Name: index_event_store_events_in_streams_on_stream_and_position; Type: INDEX; Schema: public; Owner: -
--
CREATE UNIQUE INDEX INDEX_EVENT_STORE_EVENTS_IN_STREAMS_ON_STREAM_AND_POSITION ON PUBLIC.EVENT_STORE_EVENTS_IN_STREAMS USING BTREE (
    STREAM, "position"
);

--
-- Name: index_event_store_events_on_as_of; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX INDEX_EVENT_STORE_EVENTS_ON_AS_OF ON PUBLIC.EVENT_STORE_EVENTS USING BTREE (
    coalesce(VALID_AT, CREATED_AT)
);

--
-- Name: index_event_store_events_on_created_at; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX INDEX_EVENT_STORE_EVENTS_ON_CREATED_AT ON PUBLIC.EVENT_STORE_EVENTS USING BTREE (
    CREATED_AT
);

--
-- Name: index_event_store_events_on_event_id; Type: INDEX; Schema: public; Owner: -
--
CREATE UNIQUE INDEX INDEX_EVENT_STORE_EVENTS_ON_EVENT_ID ON PUBLIC.EVENT_STORE_EVENTS USING BTREE (
    EVENT_ID
);

--
-- Name: index_event_store_events_on_event_type; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX INDEX_EVENT_STORE_EVENTS_ON_EVENT_TYPE ON PUBLIC.EVENT_STORE_EVENTS USING BTREE (
    EVENT_TYPE
);

--
-- Name: index_event_store_events_on_valid_at; Type: INDEX; Schema: public; Owner: -
--
CREATE INDEX INDEX_EVENT_STORE_EVENTS_ON_VALID_AT ON PUBLIC.EVENT_STORE_EVENTS USING BTREE (
    VALID_AT
);

--
-- Name: event_store_events_in_streams fk_rails_c8d52b5857; Type: FK CONSTRAINT; Schema: public; Owner: -
--
ALTER TABLE ONLY PUBLIC.EVENT_STORE_EVENTS_IN_STREAMS
ADD CONSTRAINT FK_RAILS_C8D52B5857 FOREIGN KEY (
    EVENT_ID
) REFERENCES PUBLIC.EVENT_STORE_EVENTS (EVENT_ID);

--
-- PostgreSQL database dump complete
--
SET search_path TO "$user", PUBLIC;

INSERT INTO "schema_migrations" (VERSION)
VALUES ('20260521134825');
