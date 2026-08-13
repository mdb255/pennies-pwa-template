-- One-time bootstrap for the Neon project neon.tf creates. Run once via psql, connected as
-- the temporary bootstrap role (see infra/README.md, "Neon bootstrap"). Mirrors
-- ../back-end/<{{ app_name }}>-api/db/init.sql, but takes the two role passwords as psql
-- variables instead of embedding them, since this file — unlike that one — is meant to hold
-- real production credentials at the moment it runs, not template placeholders.
--
-- Usage:
--   psql "$(tofu output -raw neon_bootstrap_connection_uri)" \
--     -v db_owner_pw="$(openssl rand -base64 24)" \
--     -v svc_user_pw="$(openssl rand -base64 24)" \
--     -f neon-init.sql

CREATE ROLE <{{ app_name_snake }}>_db_owner WITH LOGIN PASSWORD :'db_owner_pw';
CREATE ROLE <{{ app_name_snake }}>_svc_user WITH LOGIN PASSWORD :'svc_user_pw';

GRANT ALL ON DATABASE <{{ app_name_snake }}>_db TO <{{ app_name_snake }}>_db_owner;

CREATE SCHEMA app AUTHORIZATION <{{ app_name_snake }}>_db_owner;

GRANT USAGE ON SCHEMA app TO <{{ app_name_snake }}>_svc_user;

-- Auto-grant permissions on tables/sequences that db_owner creates in future
ALTER DEFAULT PRIVILEGES FOR ROLE <{{ app_name_snake }}>_db_owner IN SCHEMA app
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO <{{ app_name_snake }}>_svc_user;
ALTER DEFAULT PRIVILEGES FOR ROLE <{{ app_name_snake }}>_db_owner IN SCHEMA app
    GRANT USAGE, SELECT ON SEQUENCES TO <{{ app_name_snake }}>_svc_user;
