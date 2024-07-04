
SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

CREATE EXTENSION IF NOT EXISTS "pg_net" WITH SCHEMA "extensions";

CREATE EXTENSION IF NOT EXISTS "pgsodium" WITH SCHEMA "pgsodium";

COMMENT ON SCHEMA "public" IS 'standard public schema';

CREATE EXTENSION IF NOT EXISTS "pg_graphql" WITH SCHEMA "graphql";

CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";

CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";

CREATE EXTENSION IF NOT EXISTS "pgjwt" WITH SCHEMA "extensions";

CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";

CREATE TYPE "public"."event_types" AS ENUM (
    'sale',
    'work_meeting',
    'empanaton',
    'party',
    'workshop'
);

ALTER TYPE "public"."event_types" OWNER TO "postgres";

CREATE TYPE "public"."file_type" AS ENUM (
    'menu_side_img',
    'pos_product_img',
    'event_flyer'
);

ALTER TYPE "public"."file_type" OWNER TO "postgres";

CREATE TYPE "public"."no_payment_reason_types" AS ENUM (
    'gift',
    'volunteering',
    'pay_later',
    'waste'
);

ALTER TYPE "public"."no_payment_reason_types" OWNER TO "postgres";

CREATE TYPE "public"."note_types" AS ENUM (
    'comment',
    'description',
    'additional_info'
);

ALTER TYPE "public"."note_types" OWNER TO "postgres";

CREATE TYPE "public"."payment_type" AS ENUM (
    'card',
    'cash'
);

ALTER TYPE "public"."payment_type" OWNER TO "postgres";

CREATE TYPE "public"."row_state" AS ENUM (
    'active',
    'inactive',
    'deleted',
    'archived'
);

ALTER TYPE "public"."row_state" OWNER TO "postgres";

CREATE TYPE "public"."stock_operation_type" AS ENUM (
    'add',
    'sub',
    'sub_all'
);

ALTER TYPE "public"."stock_operation_type" OWNER TO "postgres";

CREATE TYPE "public"."transaction_types" AS ENUM (
    'sale',
    'cancellation',
    'transference'
);

ALTER TYPE "public"."transaction_types" OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."get_amount_sold_events"("date_start" character varying, "date_end" character varying) RETURNS TABLE("event_id" "uuid", "event_name" character varying, "event_date" timestamp without time zone, "total_amount" numeric)
    LANGUAGE "plpgsql"
    AS $$
BEGIN

RETURN QUERY select evt.id as event_id, 
                    evt.name as event_name,
                    evt.start as event_date,
                    sum(case when trx.is_chargeable = TRUE OR trx.no_payment_reason = 'pay_later'::no_payment_reason_types then trx.amount  else 0 end) as total_amount
from event_instance evt,
transaction trx
where evt.start  BETWEEN to_date(date_start,'YYYY-MM-DD') AND to_date(date_end,'YYYY-MM-DD')
and trx.event_id = evt.id
group by evt.id
order by evt.start asc;

END; 
$$;

ALTER FUNCTION "public"."get_amount_sold_events"("date_start" character varying, "date_end" character varying) OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."get_products_per_transaction"("event_id_" "uuid") RETURNS TABLE("trx_id" "uuid", "trx_code" integer, "trx_created_at" timestamp without time zone, "product_name" character varying, "product_remaining" numeric, "product_price" numeric, "product_item_count" numeric)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  RETURN QUERY select trx.id as trx_id, 
                      trx.code as trx_code, 
                      trx.created_at as trx_created_at, 
                      pro.name as product_name, 
                      st.remaining as product_remaining, 
                      pr.amount as product_price, 
                      p_trx.item_count as product_item_count
from transaction trx,
      product_transaction p_trx,
      product_event p_evt,
      product pro,
      stock st,
      price pr
where trx.event_id = event_id_
and p_trx.transaction_id = trx.id
and p_evt.id = p_trx.product_event_id
and pro.id = p_evt.product_id
and st.product_event_id = p_evt.id
and st.row_state = 'active'
and pr.product_event_id = p_evt.id
and pr.id = p_trx.price_id
order by trx.created_at desc;

END; 
$$;

ALTER FUNCTION "public"."get_products_per_transaction"("event_id_" "uuid") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."get_products_sold"("date_start" character varying, "date_end" character varying) RETURNS TABLE("product_id" "uuid", "item_quantity" numeric, "total_amount" numeric, "product_name" character varying)
    LANGUAGE "plpgsql"
    AS $$
BEGIN

RETURN QUERY select pro.id as product_id, 
                    sum(pr_trx.item_count) as items_sold, 
                    sum(pri.amount) as total_sold_per_item, 
                    pro.name as product_name
from event_instance evt,
transaction trx,
product_transaction pr_trx,
product_event pro_evt,
product pro,
price pri
where evt.start  BETWEEN to_date(date_start,'YYYY-MM-DD') AND to_date(date_end,'YYYY-MM-DD')
and trx.event_id = evt.id
and pr_trx.transaction_id = trx.id
and pro_evt.id = pr_trx.product_event_id
and pro.id = pro_evt.product_id
and pri.id = pr_trx.price_id
group by pro.id;

END; 
$$;

ALTER FUNCTION "public"."get_products_sold"("date_start" character varying, "date_end" character varying) OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."get_products_stock_per_event"("event_id_" "uuid") RETURNS TABLE("product_name" character varying, "product_remaining" numeric, "product_price" numeric)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  RETURN QUERY select pro.name as product_name, 
                      st.remaining as product_remaining, 
                      pr.amount as product_price
from  product_event p_evt,
      product pro,
      stock st,
      price pr
where p_evt.event_id = event_id_
and pro.id = p_evt.product_id
and st.product_event_id = p_evt.id
and st.row_state = 'active'
and pr.product_event_id = p_evt.id
and pr.row_state = 'active';

END; 
$$;

ALTER FUNCTION "public"."get_products_stock_per_event"("event_id_" "uuid") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."get_totals"("date_start" character varying, "date_end" character varying) RETURNS TABLE("total_transactions" bigint, "total_sold" numeric, "total_units" numeric, "total_events" bigint)
    LANGUAGE "plpgsql"
    AS $$BEGIN
  return query (select  count(distinct trx.id) as total_transactions,
                    (select sum(case when trx.is_chargeable = TRUE OR trx.no_payment_reason = 'pay_later'::no_payment_reason_types then trx.amount  else 0 end) 
                    from transaction trx, event_instance evt  where trx.event_id = evt.id and evt.start  BETWEEN to_date(date_start,'YYYY-MM-DD') AND to_date(date_end,'YYYY-MM-DD'))  as total_amount,
                      sum(p_trx.item_count) as total_units,
                      count (distinct evt.id) as total_events
from transaction trx,
      product_transaction p_trx,
      event_instance evt
where trx.id = p_trx.transaction_id
and trx.event_id = evt.id
and evt.start  BETWEEN to_date(date_start,'YYYY-MM-DD') AND to_date(date_end,'YYYY-MM-DD'));
END;$$;

ALTER FUNCTION "public"."get_totals"("date_start" character varying, "date_end" character varying) OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";

CREATE TABLE IF NOT EXISTS "public"."category" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" character varying NOT NULL,
    "created_by" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "row_state" "public"."row_state" NOT NULL,
    "parent_category_id" "uuid"
);

ALTER TABLE "public"."category" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."event_instance" (
    "id" "uuid" NOT NULL,
    "name" character varying(100) NOT NULL,
    "start" timestamp without time zone NOT NULL,
    "created_at" timestamp without time zone NOT NULL,
    "created_by" "uuid" NOT NULL,
    "row_state" "public"."row_state" DEFAULT 'active'::"public"."row_state" NOT NULL,
    "end" timestamp without time zone,
    "type" "public"."event_types" NOT NULL
);

ALTER TABLE "public"."event_instance" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."file" (
    "id" "uuid" NOT NULL,
    "created_at" timestamp without time zone NOT NULL,
    "created_by" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "row_state" "public"."row_state" NOT NULL,
    "owner_id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "url" character varying NOT NULL,
    "name" character varying NOT NULL,
    "type" "public"."file_type" NOT NULL
);

ALTER TABLE "public"."file" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."note" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "content" character varying NOT NULL,
    "owner_id" "uuid" NOT NULL,
    "created_at" timestamp without time zone NOT NULL,
    "created_by" "uuid" NOT NULL,
    "row_state" "public"."row_state",
    "type" "public"."note_types"
);

ALTER TABLE "public"."note" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."price" (
    "id" "uuid" NOT NULL,
    "amount" numeric NOT NULL,
    "created_at" timestamp without time zone NOT NULL,
    "created_by" "uuid" NOT NULL,
    "row_state" "public"."row_state" NOT NULL,
    "product_event_id" "uuid" NOT NULL
);

ALTER TABLE "public"."price" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."product" (
    "id" "uuid" NOT NULL,
    "name" character varying(100) NOT NULL,
    "created_at" timestamp without time zone NOT NULL,
    "created_by" "uuid" NOT NULL,
    "row_state" "public"."row_state" DEFAULT 'active'::"public"."row_state" NOT NULL,
    "product_type_id" "uuid"
);

ALTER TABLE "public"."product" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."product_event" (
    "id" "uuid" NOT NULL,
    "event_id" "uuid" NOT NULL,
    "product_id" "uuid" NOT NULL,
    "created_by" "uuid" NOT NULL,
    "created_at" timestamp without time zone NOT NULL,
    "row_state" "public"."row_state" DEFAULT 'active'::"public"."row_state" NOT NULL
);

ALTER TABLE "public"."product_event" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."product_transaction" (
    "id" "uuid" NOT NULL,
    "product_event_id" "uuid" NOT NULL,
    "transaction_id" "uuid" NOT NULL,
    "created_at" timestamp without time zone NOT NULL,
    "created_by" "uuid" NOT NULL,
    "row_state" "public"."row_state" DEFAULT 'active'::"public"."row_state" NOT NULL,
    "item_count" numeric NOT NULL,
    "price_id" "uuid" NOT NULL
);

ALTER TABLE "public"."product_transaction" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."product_type" (
    "name" character varying NOT NULL,
    "description" character varying,
    "created_at" timestamp with time zone NOT NULL,
    "created_by" "uuid" NOT NULL,
    "row_state" "public"."row_state" NOT NULL,
    "id" "uuid" NOT NULL
);

ALTER TABLE "public"."product_type" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."transaction" (
    "id" "uuid" NOT NULL,
    "code" integer NOT NULL,
    "created_at" timestamp without time zone NOT NULL,
    "created_by" "uuid" NOT NULL,
    "row_state" "public"."row_state" DEFAULT 'active'::"public"."row_state" NOT NULL,
    "no_payment_reason" "public"."no_payment_reason_types",
    "is_chargeable" boolean,
    "type" "public"."transaction_types",
    "amount" numeric,
    "event_id" "uuid",
    "payment_type" "public"."payment_type"
);

ALTER TABLE "public"."transaction" OWNER TO "postgres";

ALTER TABLE "public"."transaction" ALTER COLUMN "code" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."sale_code_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE IF NOT EXISTS "public"."stock" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "operation" "public"."stock_operation_type" NOT NULL,
    "operation_amount" numeric NOT NULL,
    "initial" numeric NOT NULL,
    "remaining" numeric NOT NULL,
    "product_event_id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp without time zone NOT NULL,
    "row_state" "public"."row_state" NOT NULL,
    "created_by" "uuid" DEFAULT "gen_random_uuid"() NOT NULL
);

ALTER TABLE "public"."stock" OWNER TO "postgres";

ALTER TABLE ONLY "public"."category"
    ADD CONSTRAINT "category_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."file"
    ADD CONSTRAINT "files_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."note"
    ADD CONSTRAINT "note_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."event_instance"
    ADD CONSTRAINT "pk_event" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."product"
    ADD CONSTRAINT "pk_product" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."product_event"
    ADD CONSTRAINT "pk_product_event" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."product_transaction"
    ADD CONSTRAINT "pk_product_sale" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."transaction"
    ADD CONSTRAINT "pk_sale" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."price"
    ADD CONSTRAINT "price_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."product_type"
    ADD CONSTRAINT "product_type_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."stock"
    ADD CONSTRAINT "stock_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."product_event"
    ADD CONSTRAINT "fk_product_event" FOREIGN KEY ("event_id") REFERENCES "public"."event_instance"("id");

ALTER TABLE ONLY "public"."product_event"
    ADD CONSTRAINT "fk_product_event_product" FOREIGN KEY ("product_id") REFERENCES "public"."product"("id");

ALTER TABLE ONLY "public"."product_transaction"
    ADD CONSTRAINT "fk_product_sale_product" FOREIGN KEY ("product_event_id") REFERENCES "public"."product_event"("id");

ALTER TABLE ONLY "public"."product_transaction"
    ADD CONSTRAINT "fk_product_sale_sale" FOREIGN KEY ("transaction_id") REFERENCES "public"."transaction"("id");

ALTER TABLE ONLY "public"."price"
    ADD CONSTRAINT "price_product_event_id_fkey" FOREIGN KEY ("product_event_id") REFERENCES "public"."product_event"("id");

ALTER TABLE ONLY "public"."product"
    ADD CONSTRAINT "product_product_type_id_fkey" FOREIGN KEY ("product_type_id") REFERENCES "public"."product_type"("id");

ALTER TABLE ONLY "public"."product_transaction"
    ADD CONSTRAINT "product_transaction_price_id_fkey" FOREIGN KEY ("price_id") REFERENCES "public"."price"("id");

ALTER TABLE ONLY "public"."stock"
    ADD CONSTRAINT "stock_product_event_id_fkey" FOREIGN KEY ("product_event_id") REFERENCES "public"."product_event"("id");

ALTER TABLE ONLY "public"."transaction"
    ADD CONSTRAINT "transaction_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "public"."event_instance"("id");

CREATE POLICY "all_read" ON "public"."transaction" FOR SELECT TO "anon" USING (true);

ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";

GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";

GRANT ALL ON FUNCTION "public"."get_amount_sold_events"("date_start" character varying, "date_end" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."get_amount_sold_events"("date_start" character varying, "date_end" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_amount_sold_events"("date_start" character varying, "date_end" character varying) TO "service_role";

GRANT ALL ON FUNCTION "public"."get_products_per_transaction"("event_id_" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_products_per_transaction"("event_id_" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_products_per_transaction"("event_id_" "uuid") TO "service_role";

GRANT ALL ON FUNCTION "public"."get_products_sold"("date_start" character varying, "date_end" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."get_products_sold"("date_start" character varying, "date_end" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_products_sold"("date_start" character varying, "date_end" character varying) TO "service_role";

GRANT ALL ON FUNCTION "public"."get_products_stock_per_event"("event_id_" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_products_stock_per_event"("event_id_" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_products_stock_per_event"("event_id_" "uuid") TO "service_role";

GRANT ALL ON FUNCTION "public"."get_totals"("date_start" character varying, "date_end" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."get_totals"("date_start" character varying, "date_end" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_totals"("date_start" character varying, "date_end" character varying) TO "service_role";

GRANT ALL ON TABLE "public"."category" TO "anon";
GRANT ALL ON TABLE "public"."category" TO "authenticated";
GRANT ALL ON TABLE "public"."category" TO "service_role";

GRANT ALL ON TABLE "public"."event_instance" TO "anon";
GRANT ALL ON TABLE "public"."event_instance" TO "authenticated";
GRANT ALL ON TABLE "public"."event_instance" TO "service_role";

GRANT ALL ON TABLE "public"."file" TO "anon";
GRANT ALL ON TABLE "public"."file" TO "authenticated";
GRANT ALL ON TABLE "public"."file" TO "service_role";

GRANT ALL ON TABLE "public"."note" TO "anon";
GRANT ALL ON TABLE "public"."note" TO "authenticated";
GRANT ALL ON TABLE "public"."note" TO "service_role";

GRANT ALL ON TABLE "public"."price" TO "anon";
GRANT ALL ON TABLE "public"."price" TO "authenticated";
GRANT ALL ON TABLE "public"."price" TO "service_role";

GRANT ALL ON TABLE "public"."product" TO "anon";
GRANT ALL ON TABLE "public"."product" TO "authenticated";
GRANT ALL ON TABLE "public"."product" TO "service_role";

GRANT ALL ON TABLE "public"."product_event" TO "anon";
GRANT ALL ON TABLE "public"."product_event" TO "authenticated";
GRANT ALL ON TABLE "public"."product_event" TO "service_role";

GRANT ALL ON TABLE "public"."product_transaction" TO "anon";
GRANT ALL ON TABLE "public"."product_transaction" TO "authenticated";
GRANT ALL ON TABLE "public"."product_transaction" TO "service_role";

GRANT ALL ON TABLE "public"."product_type" TO "anon";
GRANT ALL ON TABLE "public"."product_type" TO "authenticated";
GRANT ALL ON TABLE "public"."product_type" TO "service_role";

GRANT ALL ON TABLE "public"."transaction" TO "anon";
GRANT ALL ON TABLE "public"."transaction" TO "authenticated";
GRANT ALL ON TABLE "public"."transaction" TO "service_role";

GRANT ALL ON SEQUENCE "public"."sale_code_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."sale_code_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."sale_code_seq" TO "service_role";

GRANT ALL ON TABLE "public"."stock" TO "anon";
GRANT ALL ON TABLE "public"."stock" TO "authenticated";
GRANT ALL ON TABLE "public"."stock" TO "service_role";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "service_role";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "service_role";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "service_role";

RESET ALL;
