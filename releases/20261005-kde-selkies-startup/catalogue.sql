-- Apply through the central PostgreSQL MCP after the new image is verified
-- and registered on server 578. Updates only the existing KDE variant.
DO $release$
DECLARE
    current_version jsonb;
    affected integer;
    expected_version constant jsonb := $baseline${
      "id":1221,"tag":"26.04","cpus":4,"init":0,
      "image":"resolute-server-cloudimg-amd64v3-remote-desktop-kde.img",
      "app_id":241,"memory":8,"cap_add":null,"changes":null,"enabled":1,
      "user_id":null,"version":"Remote Desktop 26.04 KDE Plasma",
      "cap_drop":null,"min_cpus":null,"app_slots":8,"admin_only":0,
      "deprecated":0,"is_default":0,"min_memory":null,"pids_limit":null,
      "privileged":0,"memory_swap":8,"tcp_port_range":"22,32400,3389",
      "udp_port_range":null,"tcp_dynamic_ports":null,"udp_dynamic_ports":null,
      "memory_reservation":8,"combined_port_range":null,"deprecation_message":null,
      "combined_dynamic_ports":100,"installed_image_digest":null,
      "custom_field_preinstall_description":null,"custom_field_postinstall_description":null
    }$baseline$::jsonb;
BEGIN
    SELECT to_jsonb(v) - 'created_at' - 'updated_at'
      INTO current_version
      FROM app_versions v WHERE id=1221 AND app_id=241 FOR UPDATE;
    IF current_version IS DISTINCT FROM expected_version THEN
        RAISE EXCEPTION 'KDE catalogue baseline changed; release was not applied';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM server_images
        WHERE server_id=578
          AND image_name='resolute-server-cloudimg-amd64v3-remote-desktop-kde-20261005.img'
          AND file_size > 0
    ) THEN
        RAISE EXCEPTION 'New KDE image is not registered on seed server 578';
    END IF;
    UPDATE app_versions
       SET image='resolute-server-cloudimg-amd64v3-remote-desktop-kde-20261005.img',
           changes='Fixed remote desktop startup failures on virtual machines with large home directories. Applies to new installations; contact support to update an existing virtual machine.',
           updated_at=NOW()
     WHERE id=1221 AND app_id=241
       AND image='resolute-server-cloudimg-amd64v3-remote-desktop-kde.img'
       AND changes IS NULL;
    GET DIAGNOSTICS affected = ROW_COUNT;
    IF affected <> 1 THEN
        RAISE EXCEPTION 'Expected one KDE version update; affected %', affected;
    END IF;
END;
$release$;
