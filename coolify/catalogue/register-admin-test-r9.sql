-- Apply only after the exact sealed image passes both fresh clone, trim and reboot checks,
-- and is copied to the test host with an independently verified checksum.
-- Supersede the r8 admin-only preview (full-size trim stall, callback replay) with r9.
DO $coolify_r9$
DECLARE
    affected integer;
    new_version integer;
BEGIN
    PERFORM id FROM apps WHERE id=283 FOR UPDATE;
    PERFORM id FROM app_versions WHERE id=1371 FOR UPDATE;
    IF (SELECT count(*) FROM apps WHERE id=283 AND display_name='Coolify VPS'
        AND type='vm' AND admin_only=1 AND enabled=1
        AND "Image"='coolify-ubuntu-26.04-4.3.23-eb8908d44450.qcow2') <> 1
       OR (SELECT count(*) FROM app_versions WHERE id=1371 AND app_id=283
           AND admin_only=1 AND enabled=1 AND is_default=1
           AND memory=8 AND memory_swap=8 AND memory_reservation=8
           AND cpus=4 AND app_slots=8) <> 1 THEN
        RAISE EXCEPTION 'Expected private Coolify preview changed';
    END IF;
    IF EXISTS (SELECT 1 FROM app_versions WHERE app_id=283
        AND (tag='4.3.23-ubuntu26.04-9a167fb'
             OR version='4.3.23 / Ubuntu 26.04 r9')) THEN
        RAISE EXCEPTION 'Revised test version already exists';
    END IF;
    INSERT INTO app_versions
        (app_id,version,tag,enabled,is_default,admin_only,changes,image,
         memory,memory_swap,memory_reservation,cpus,init,privileged,cap_add,cap_drop,
         tcp_port_range,udp_port_range,tcp_dynamic_ports,udp_dynamic_ports,
         pids_limit,combined_port_range,combined_dynamic_ports,app_slots,
         min_memory,min_cpus,custom_field_preinstall_description,
         custom_field_postinstall_description)
    SELECT app_id,'4.3.23 / Ubuntu 26.04 r9','4.3.23-ubuntu26.04-9a167fb',1,1,1,
        'Admin-only test build of Coolify 4.3.23 on Ubuntu 26.04. The data disk now releases space as soon as files are deleted, replacing the hourly trim that could slow the VM on large disks. The setup callback no longer repeats after a reboot. The VM uses an XFS data filesystem for Coolify, Docker and projects. At least 34 GiB of storage is required. Automatic updates are disabled during validation. Add each project hostname to this VM in Appbox before using it in Coolify.',
        'coolify-ubuntu-26.04-4.3.23-9a167fb96027.qcow2',
        memory,memory_swap,memory_reservation,cpus,init,privileged,cap_add,cap_drop,
        tcp_port_range,udp_port_range,tcp_dynamic_ports,udp_dynamic_ports,
        pids_limit,combined_port_range,combined_dynamic_ports,app_slots,
        min_memory,min_cpus,custom_field_preinstall_description,
        custom_field_postinstall_description
    FROM app_versions WHERE id=1371 AND app_id=283
    RETURNING id INTO new_version;
    GET DIAGNOSTICS affected = ROW_COUNT;
    IF affected <> 1 THEN RAISE EXCEPTION 'Expected one revised version'; END IF;

    UPDATE app_versions SET enabled=0,is_default=0,deprecated=1,
        deprecation_message='Superseded validation preview; use the revised image for new test installations.',
        updated_at=now()
    WHERE id=1371 AND app_id=283 AND enabled=1 AND is_default=1 AND admin_only=1;
    GET DIAGNOSTICS affected = ROW_COUNT;
    IF affected <> 1 THEN RAISE EXCEPTION 'Expected one superseded preview'; END IF;

    UPDATE apps SET "Image"='coolify-ubuntu-26.04-4.3.23-9a167fb96027.qcow2',
        version='4.3.23 / Ubuntu 26.04 r9',tag='4.3.23-ubuntu26.04-9a167fb',
        updated_at=to_char(now(),'YYYY-MM-DD"T"HH24:MI:SSOF')
    WHERE id=283 AND type='vm' AND admin_only=1
      AND "Image"='coolify-ubuntu-26.04-4.3.23-eb8908d44450.qcow2';
    GET DIAGNOSTICS affected = ROW_COUNT;
    IF affected <> 1 THEN RAISE EXCEPTION 'Expected one private app default'; END IF;
END;
$coolify_r9$;

SELECT a.id AS app_id,v.id AS version_id,a.admin_only,v.admin_only AS version_admin_only,
       v.version,v.image,v.is_default,v.enabled,v.memory,v.memory_swap,
       v.memory_reservation,v.cpus,v.app_slots,v.changes
FROM apps a JOIN app_versions v ON v.app_id=a.id
WHERE a.id=283 ORDER BY v.id;
