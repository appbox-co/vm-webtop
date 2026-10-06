-- Add the dashboard link to the existing private Coolify preview.
-- Apply through Postgres MCP after this migration is committed and delivered.
DO $coolify_web_ui$
DECLARE
    affected integer;
BEGIN
    PERFORM id FROM apps WHERE id=283 FOR UPDATE;
    IF (SELECT count(*) FROM apps WHERE id=283 AND display_name='Coolify VPS'
        AND type='vm' AND enabled=1 AND admin_only=1
        AND "Image"='coolify-ubuntu-26.04-4.3.23-eb8908d44450.qcow2') <> 1 THEN
        RAISE EXCEPTION 'Expected private Coolify r8 preview changed';
    END IF;
    IF (SELECT count(*) FROM customfields WHERE type='app' AND relid=283) <> 5
       OR (SELECT count(*) FROM customfields WHERE type='app' AND relid=283
           AND app_version_id IS NULL AND version IS NULL
           AND fname IN ('COOLIFY_ADMIN_EMAIL','PASSWORD','LOGIN_USER',
                         'SERVER_ADDR','SSH_PORT')) <> 5 THEN
        RAISE EXCEPTION 'Expected Coolify fields changed; inspect before retrying';
    END IF;

    INSERT INTO customfields
        (type,relid,fname,display_name,fieldtype,default_value,required,options,
         template_type,"minLength","maxLength",sort_order,flex,sensitive,revealable)
    VALUES
        ('app',283,'URL','Web UI','externalURL','https://%DOMAIN.DOMAIN%',0,
         '{"showOnInstalled":true}','instance',0,NULL,5,12,false,false);
    GET DIAGNOSTICS affected = ROW_COUNT;
    IF affected <> 1 THEN RAISE EXCEPTION 'Expected one Web UI field'; END IF;
END;
$coolify_web_ui$;

SELECT id,relid,fname,display_name,fieldtype,default_value,template_type,
       options,required,sort_order,flex,sensitive,revealable
FROM customfields WHERE type='app' AND relid=283 AND fname='URL';
