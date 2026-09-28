-- One-time bootstrap for the Neon project neon.tf creates. Run once via psql, connected as
-- the temporary bootstrap role (see infra/README.md, "Neon bootstrap"). Mirrors
-- ../back-end/<{{ app_name }}>-api/db/init.sql, but takes the two role passwords as psql
-- variables instead of embedding them, since this file — unlike that one — is meant to hold
-- real production credentials at the moment it runs, not template placeholders.
--
-- Idempotent: safe to rerun after a partial failure (apply-infra.sh's step 5 resumes by
-- rerunning this file). Role creation is skipped if the role already exists, keeping its
-- original password rather than the one just passed in.
--
-- Usage:
--   psql "$(tofu output -raw neon_bootstrap_connection_uri)" \
--     -v ON_ERROR_STOP=1 \
--     -v db_owner_pw="$(openssl rand -base64 24)" \
--     -v svc_user_pw="$(openssl rand -base64 24)" \
--     -f neon-init.sql

DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '<{{ app_name_snake }}>_db_owner') THEN
    CREATE ROLE <{{ app_name_snake }}>_db_owner WITH LOGIN PASSWORD :'db_owner_pw';
  END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '<{{ app_name_snake }}>_svc_user') THEN
    CREATE ROLE <{{ app_name_snake }}>_svc_user WITH LOGIN PASSWORD :'svc_user_pw';
  END IF;
END
$$;

GRANT ALL ON DATABASE <{{ app_name_snake }}>_db TO <{{ app_name_snake }}>_db_owner;

-- Neon's connection role has CREATEROLE but isn't a real superuser, so creating db_owner
-- above doesn't implicitly grant this session membership in it. Local docker-compose runs
-- as an actual superuser, so this line is a no-op there.
GRANT <{{ app_name_snake }}>_db_owner TO CURRENT_USER;

CREATE SCHEMA IF NOT EXISTS app AUTHORIZATION <{{ app_name_snake }}>_db_owner;

GRANT USAGE ON SCHEMA app TO <{{ app_name_snake }}>_svc_user;

-- Auto-grant permissions on tables/sequences that db_owner creates in future
ALTER DEFAULT PRIVILEGES FOR ROLE <{{ app_name_snake }}>_db_owner IN SCHEMA app
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO <{{ app_name_snake }}>_svc_user;
ALTER DEFAULT PRIVILEGES FOR ROLE <{{ app_name_snake }}>_db_owner IN SCHEMA app
    GRANT USAGE, SELECT ON SEQUENCES TO <{{ app_name_snake }}>_svc_user;
