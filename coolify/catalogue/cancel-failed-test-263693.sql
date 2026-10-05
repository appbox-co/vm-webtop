-- Cancel only the disposable Coolify validation installation created by this task.
-- Preconditions checked on cylo13: no local job for this instance, cloud-init
-- blocked in resize2fs, no administrator/proxy-ready message, ports 22/443 closed.
-- Keep the instance inactive, then use normal Appbox uninstall for runtime/data
-- cleanup and slot restoration. This does not mark the test installation healthy.
DO $cancel_failed_test$
DECLARE
    target appinstance%ROWTYPE;
    affected integer;
BEGIN
    SELECT * INTO STRICT target FROM appinstance
    WHERE id=263693 AND cylo_id=11350 AND app_id=283
    FOR UPDATE;
    IF target.enabled <> 1 OR target.installing <> 1 OR target.deleting <> 0
       OR target.updating <> 0 OR target.state <> 0
       OR target.vm_control_status IS NOT NULL
       OR target.version <> '4.3.23 / Ubuntu 26.04 r2'
       OR target.created_at::timestamptz <> '2026-10-05T13:16:54Z'::timestamptz THEN
        RAISE EXCEPTION 'Failed test state changed; inspect before cancelling';
    END IF;
    IF (SELECT count(*) FROM domains WHERE instance_id=263693
        AND domain='coolify-r2.grant.appboxes.co') <> 1
       OR (SELECT count(*) FROM domains WHERE instance_id=263693) <> 1
       OR (SELECT count(*) FROM apps WHERE id=283 AND display_name='Coolify VPS'
           AND type='vm' AND admin_only=1) <> 1
       OR (SELECT count(*) FROM cylos WHERE id=11350 AND cyloname='grant'
           AND server_id=578 AND enabled=1 AND migrating=0) <> 1 THEN
        RAISE EXCEPTION 'Task-owned failed test identity changed';
    END IF;
    UPDATE appinstance SET installing=0,enabled=0,
        updated_at=to_char(now(),'YYYY-MM-DD"T"HH24:MI:SSOF')
    WHERE id=263693 AND cylo_id=11350 AND app_id=283
      AND enabled=1 AND installing=1 AND deleting=0 AND updating=0 AND state=0;
    GET DIAGNOSTICS affected = ROW_COUNT;
    IF affected <> 1 THEN RAISE EXCEPTION 'Expected exactly one cancelled test'; END IF;
END;
$cancel_failed_test$;
SELECT id,cylo_id,app_id,installing,enabled,deleting,state
FROM appinstance WHERE id=263693;
