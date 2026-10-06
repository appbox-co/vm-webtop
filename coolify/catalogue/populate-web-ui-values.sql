-- Populate only the new non-sensitive link for the existing private test VM.
-- Existing installs need a value row; future installs use the field default.
DO $coolify_web_ui_value$
DECLARE
    web_ui_field integer;
    affected integer;
BEGIN
    PERFORM id FROM apps WHERE id=283 FOR UPDATE;
    IF (SELECT count(*) FROM apps WHERE id=283 AND display_name='Coolify VPS'
        AND type='vm' AND enabled=1 AND admin_only=1) <> 1 THEN
        RAISE EXCEPTION 'Expected private Coolify preview changed';
    END IF;
    IF (SELECT count(*) FROM customfields WHERE type='app' AND relid=283
        AND fname='URL' AND display_name='Web UI' AND fieldtype='externalURL'
        AND default_value='https://%DOMAIN.DOMAIN%'
        AND template_type='instance' AND required=0
        AND app_version_id IS NULL AND version IS NULL
        AND sensitive=false AND revealable=false) <> 1 THEN
        RAISE EXCEPTION 'Expected Web UI field changed';
    END IF;
    SELECT id INTO web_ui_field FROM customfields
    WHERE type='app' AND relid=283 AND fname='URL';
    PERFORM id FROM appinstance WHERE app_id=283 FOR UPDATE;
    IF (SELECT count(*) FROM appinstance WHERE app_id=283) <> 1
       OR (SELECT count(*) FROM appinstance WHERE app_id=283
           AND installing=0 AND state=1 AND enabled=1) <> 1
       OR EXISTS (SELECT 1 FROM customfieldvalues WHERE fieldid=web_ui_field) THEN
        RAISE EXCEPTION 'Expected one installed test VM with no Web UI value';
    END IF;

    INSERT INTO customfieldvalues (fieldid,relid,relid2,value)
    SELECT web_ui_field,id,app_id,'https://%DOMAIN.DOMAIN%'
    FROM appinstance WHERE app_id=283 AND installing=0 AND state=1 AND enabled=1;
    GET DIAGNOSTICS affected = ROW_COUNT;
    IF affected <> 1 THEN RAISE EXCEPTION 'Expected one installed Web UI value'; END IF;
END;
$coolify_web_ui_value$;

SELECT f.id AS field_id,f.fname,f.fieldtype,v.value,
       count(*) OVER () AS affected_value_rows
FROM customfields f JOIN customfieldvalues v ON v.fieldid=f.id
WHERE f.type='app' AND f.relid=283 AND f.fname='URL' AND v.relid2=283;
