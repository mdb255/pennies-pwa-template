-- Local dev only — runs once when the Postgres container is first created.
-- Creates the two application roles and the app schema.

CREATE ROLE <{{ app_name_snake }}>_db_owner WITH LOGIN PASSWORD '<{{ app_name_snake }}>_db_owner_pw';
CREATE ROLE <{{ app_name_snake }}>_svc_user WITH LOGIN PASSWORD '<{{ app_name_snake }}>_svc_user_pw';

GRANT ALL ON DATABASE <{{ app_name_snake }}>_db TO <{{ app_name_snake }}>_db_owner;

CREATE SCHEMA app AUTHORIZATION <{{ app_name_snake }}>_db_owner;

GRANT USAGE ON SCHEMA app TO <{{ app_name_snake }}>_svc_user;

-- Auto-grant permissions on tables/sequences that db_owner creates in future
ALTER DEFAULT PRIVILEGES FOR ROLE <{{ app_name_snake }}>_db_owner IN SCHEMA app
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO <{{ app_name_snake }}>_svc_user;
ALTER DEFAULT PRIVILEGES FOR ROLE <{{ app_name_snake }}>_db_owner IN SCHEMA app
    GRANT USAGE, SELECT ON SEQUENCES TO <{{ app_name_snake }}>_svc_user;
