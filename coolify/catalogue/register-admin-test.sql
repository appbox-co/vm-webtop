-- Admin-only Coolify VM validation entry. Execute once through Postgres MCP.
-- The Docker importer cannot create VM entries; this follows its child-record
-- contract while retaining the existing VM resource and port conventions.
DO $registration$
DECLARE
    new_app integer;
    new_version integer;
    affected integer;
BEGIN
    IF EXISTS (SELECT 1 FROM apps WHERE lower(display_name) = 'coolify vps'
        OR "Image" = 'coolify-ubuntu-26.04-4.3.23-c315a7b072ea.qcow2') THEN
        RAISE EXCEPTION 'Coolify registration already exists; inspect before retrying';
    END IF;
    IF (SELECT count(*) FROM cylos WHERE id = 11350 AND cyloname = 'grant'
        AND server_id = 578 AND enabled = 1 AND migrating = 0) <> 1 THEN
        RAISE EXCEPTION 'The approved test Appbox placement changed';
    END IF;
    IF (SELECT count(*) FROM appcategories WHERE id IN (16,27,29)
        AND enabled = 1 AND brand_id = 1) <> 3 THEN
        RAISE EXCEPTION 'Expected catalogue categories are unavailable';
    END IF;

    INSERT INTO apps
        (display_name,publisher,description,short_description,created_at,updated_at,
         enabled,show_app,version,featured,app_slots,allow_multiple,ssl,type,
         "Image","Memory","MemorySwap","MemoryReservation","CPUs","Privileged",
         "IsWebApp","RequiresDomain",admin_only,subdomain,brand_id,"LogConfig",
         "NetworkMode",wildcard_ssl,expect_callback,callback_requires_auth,
         "canRestart","canUpdate",migrate_dataset,tcp_passthrough,multiple_domains,
         "TCPPortRange",source_repo,devsite,documentation_url,
         custom_field_preinstall_description,custom_field_postinstall_description)
    VALUES
        ('Coolify VPS','Coollabs','<h2>Deploy applications on your own VPS</h2><p>Coolify manages application deployments, databases and services inside an Ubuntu 26.04 virtual machine.</p><h3>Getting started</h3><p>Sign in with the administrator email and password chosen during installation. Add each project hostname to this VM in Appbox and configure the same hostname in Coolify.</p><h3>Updates and backups</h3><p>This admin-only preview uses Coolify 4.3.23. Automatic updates are disabled while the package is tested. Back up the VM and /data/coolify before making changes.</p>',
         'Deploy applications and services with Coolify on an Ubuntu 26.04 VPS.',
         to_char(now(),'YYYY-MM-DD"T"HH24:MI:SSOF'),to_char(now(),'YYYY-MM-DD"T"HH24:MI:SSOF'),
         1,1,'4.3.23 / Ubuntu 26.04',0,8,1,1,'vm',
         'coolify-ubuntu-26.04-4.3.23-c315a7b072ea.qcow2',8,8,8,4,0,
         1,1,1,'coolify',1,'json-file','default',1,1,1,1,0,0,true,1,'22',
         'https://github.com/appbox-co/vm-webtop/tree/codex/coolify-vps',
         'https://coolify.io','https://coolify.io/docs',
         'Choose your Coolify administrator email and password. Docker workloads run inside this VPS.',
         'Open the app and sign in with your chosen administrator email and password. Add project hostnames to this VM in Appbox before using them in Coolify.')
    RETURNING id INTO new_app;
    GET DIAGNOSTICS affected = ROW_COUNT;
    IF affected <> 1 THEN RAISE EXCEPTION 'Expected one new app'; END IF;

    INSERT INTO app_versions
        (app_id,version,tag,enabled,is_default,admin_only,changes,image,
         memory,memory_swap,memory_reservation,cpus,init,privileged,
         tcp_port_range,app_slots)
    VALUES
        (new_app,'4.3.23 / Ubuntu 26.04','4.3.23-ubuntu26.04-c315a7b',1,1,1,
         'Admin-only test release of Coolify 4.3.23 on Ubuntu 26.04. Includes PostgreSQL, Redis, realtime services and Traefik. Installation creates an administrator from your chosen email and password. Project hostnames must also be assigned to the VM in Appbox. Automatic updates remain disabled during validation.',
         'coolify-ubuntu-26.04-4.3.23-c315a7b072ea.qcow2',8,8,8,4,0,0,'22',8)
    RETURNING id INTO new_version;
    GET DIAGNOSTICS affected = ROW_COUNT;
    IF affected <> 1 THEN RAISE EXCEPTION 'Expected one new version'; END IF;

    INSERT INTO appenvironmentvars (app_id,"Key","Value",template_type)
    VALUES (new_app,'VIRTUAL_PORT','80','none');
    GET DIAGNOSTICS affected = ROW_COUNT;
    IF affected <> 1 THEN RAISE EXCEPTION 'Expected one environment definition'; END IF;

    INSERT INTO customfields
        (type,relid,fname,display_name,fieldtype,default_value,required,options,
         template_type,"minLength","maxLength",sort_order,flex,sensitive,revealable)
    VALUES
        ('app',new_app,'COOLIFY_ADMIN_EMAIL','Administrator email','email',NULL,1,
         '{"showOnInstalled":true}','none',3,254,0,12,false,false),
        ('app',new_app,'PASSWORD','Administrator and SSH password','complexPassword',NULL,1,
         '{"showOnInstalled":true}','none',12,72,1,12,true,true),
        ('app',new_app,'LOGIN_USER','SSH username','staticText','appbox',0,
         '{"showOnInstalled":true}','none',0,NULL,2,6,false,false),
        ('app',new_app,'SERVER_ADDR','SSH host','staticText','%DOMAIN.DOMAIN%',0,
         '{"showOnInstalled":true}','instance',0,NULL,3,6,false,false),
        ('app',new_app,'SSH_PORT','SSH port','staticText','%PORTS|0.EXTERNAL%',0,
         '{"showOnInstalled":true}','instance',0,NULL,4,6,false,false);
    GET DIAGNOSTICS affected = ROW_COUNT;
    IF affected <> 5 THEN RAISE EXCEPTION 'Expected five custom fields'; END IF;

    INSERT INTO links (type,relid1,relid2)
    SELECT 'appcategory',new_app,id FROM appcategories WHERE id IN (16,27,29);
    GET DIAGNOSTICS affected = ROW_COUNT;
    IF affected <> 3 THEN RAISE EXCEPTION 'Expected three category links'; END IF;

    IF NOT EXISTS (SELECT 1 FROM apps a JOIN app_versions v ON v.app_id=a.id
        WHERE a.id=new_app AND v.id=new_version AND a.type='vm'
        AND a.admin_only=1 AND v.admin_only=1 AND a.tcp_passthrough
        AND a."Memory"=v.memory AND a."CPUs"=v.cpus
        AND a.app_slots=v.app_slots AND a."canUpdate"=0
        AND a.callback_requires_auth=1 AND v.changes <> '') THEN
        RAISE EXCEPTION 'Saved Coolify entry failed validation';
    END IF;
END;
$registration$;

SELECT a.id AS app_id,v.id AS version_id,a.display_name,a.type,a.admin_only,
       v.admin_only AS version_admin_only,v.version,v.changes,v.image,
       v.memory,v.cpus,v.app_slots,a.tcp_passthrough
FROM apps a JOIN app_versions v ON v.app_id=a.id
WHERE a.display_name='Coolify VPS';
