-- Supersede the failed admin-only preview with the revised, sealed VM image.
DO $coolify_r2$
DECLARE
    affected integer;
    new_version integer;
BEGIN
    PERFORM id FROM apps WHERE id=283 FOR UPDATE;
    PERFORM id FROM app_versions WHERE id=1363 FOR UPDATE;
    IF (SELECT count(*) FROM apps WHERE id=283 AND display_name='Coolify VPS'
        AND type='vm' AND admin_only=1 AND enabled=1
        AND "Image"='coolify-ubuntu-26.04-4.3.23-c315a7b072ea.qcow2') <> 1
       OR (SELECT count(*) FROM app_versions WHERE id=1363 AND app_id=283
           AND admin_only=1 AND enabled=1 AND is_default=1
           AND memory=8 AND memory_swap=8 AND memory_reservation=8
           AND cpus=4 AND app_slots=8) <> 1 THEN
        RAISE EXCEPTION 'Expected private Coolify preview changed';
    END IF;
    IF EXISTS (SELECT 1 FROM app_versions WHERE app_id=283
        AND (tag='4.3.23-ubuntu26.04-78efef5'
             OR version='4.3.23 / Ubuntu 26.04 r2')) THEN
        RAISE EXCEPTION 'Revised test version already exists';
    END IF;
    INSERT INTO app_versions
        (app_id,version,tag,enabled,is_default,admin_only,changes,image,
         memory,memory_swap,memory_reservation,cpus,init,privileged,cap_add,cap_drop,
         tcp_port_range,udp_port_range,tcp_dynamic_ports,udp_dynamic_ports,
         pids_limit,combined_port_range,combined_dynamic_ports,app_slots,
         min_memory,min_cpus,custom_field_preinstall_description,
         custom_field_postinstall_description)
    SELECT app_id,'4.3.23 / Ubuntu 26.04 r2','4.3.23-ubuntu26.04-78efef5',1,1,1,
        'Revised admin-only preview of Coolify 4.3.23 on Ubuntu 26.04. The HTTPS proxy now accepts Appbox PROXY protocol headers from the VM bridge gateway. The root filesystem uses periodic trimming instead of synchronous discard. Automatic updates remain disabled during validation. Assign project hostnames to the VM in Appbox before using them in Coolify.',
        'coolify-ubuntu-26.04-4.3.23-78efef59c0b8.qcow2',
        memory,memory_swap,memory_reservation,cpus,init,privileged,cap_add,cap_drop,
        tcp_port_range,udp_port_range,tcp_dynamic_ports,udp_dynamic_ports,
        pids_limit,combined_port_range,combined_dynamic_ports,app_slots,
        min_memory,min_cpus,custom_field_preinstall_description,
        custom_field_postinstall_description
    FROM app_versions WHERE id=1363 AND app_id=283
    RETURNING id INTO new_version;
    GET DIAGNOSTICS affected = ROW_COUNT;
    IF affected <> 1 THEN RAISE EXCEPTION 'Expected one revised version'; END IF;

    UPDATE app_versions SET enabled=0,is_default=0,deprecated=1,
        deprecation_message='Superseded validation preview; use the revised image for new test installations.',
        updated_at=now()
    WHERE id=1363 AND app_id=283 AND enabled=1 AND is_default=1 AND admin_only=1;
    GET DIAGNOSTICS affected = ROW_COUNT;
    IF affected <> 1 THEN RAISE EXCEPTION 'Expected one superseded preview'; END IF;

    UPDATE apps SET "Image"='coolify-ubuntu-26.04-4.3.23-78efef59c0b8.qcow2',
        version='4.3.23 / Ubuntu 26.04 r2',tag='4.3.23-ubuntu26.04-78efef5',
        description=$description$## Deploy applications on your own VPS

Coolify manages application deployments, databases and services inside an Ubuntu 26.04 virtual machine.

### Getting started

Sign in with the administrator email and password chosen during installation. Add each project hostname to this VM in Appbox and configure the same hostname in Coolify.

### Updates and backups

This admin-only preview uses Coolify 4.3.23. Automatic updates are disabled while the package is tested. Back up the VM and `/data/coolify` before making changes.$description$,
        updated_at=to_char(now(),'YYYY-MM-DD"T"HH24:MI:SSOF')
    WHERE id=283 AND type='vm' AND admin_only=1
      AND "Image"='coolify-ubuntu-26.04-4.3.23-c315a7b072ea.qcow2';
    GET DIAGNOSTICS affected = ROW_COUNT;
    IF affected <> 1 THEN RAISE EXCEPTION 'Expected one private app default'; END IF;
END;
$coolify_r2$;

SELECT a.id AS app_id,v.id AS version_id,a.admin_only,v.admin_only AS version_admin_only,
       v.version,v.image,v.is_default,v.enabled,v.memory,v.memory_swap,
       v.memory_reservation,v.cpus,v.app_slots,v.changes
FROM apps a JOIN app_versions v ON v.app_id=a.id
WHERE a.id=283 ORDER BY v.id;
