<?php
// This script runs inside the released Coolify image. Input is JSON on stdin.
require '/var/www/html/vendor/autoload.php';
$app = require '/var/www/html/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

try {
    $input = stream_get_contents(STDIN, 16385);
    if (strlen($input) > 16384) {
        throw new RuntimeException('Input too large');
    }
    $payload = json_decode($input, true, 16, JSON_THROW_ON_ERROR);
    $operation = $payload['operation'] ?? '';
    if ($operation === 'reset-password') {
        $password = $payload['password'] ?? '';
        if (!is_string($password) || strlen($password) < 12 || strlen($password) > 72) {
            throw new RuntimeException('Invalid password');
        }
        $user = App\Models\User::findOrFail(0);
        $user->password = Illuminate\Support\Facades\Hash::make($password);
        $user->save();
        if (!Illuminate\Support\Facades\Hash::check($password, $user->fresh()->password)) {
            throw new RuntimeException('Password update failed');
        }
    } elseif ($operation === 'provision') {
        Illuminate\Support\Facades\DB::transaction(function () use ($payload) {
            $team = App\Models\Team::findOrFail(0);
            $settings = App\Models\InstanceSettings::findOrFail(0);
            $user = App\Models\User::find(0);
            if (!$user) {
                if (empty($payload['initial'])) {
                    throw new RuntimeException('Administrator missing after setup');
                }
                $email = $payload['email'] ?? '';
                $hash = $payload['password_hash'] ?? '';
                if (!filter_var($email, FILTER_VALIDATE_EMAIL)
                    || !preg_match('/^\$2[ayb]\$[0-9]{2}\$[.\/A-Za-z0-9]{53}$/D', $hash)) {
                    throw new RuntimeException('Invalid installation account');
                }
                $user = (new App\Models\User)->forceFill([
                    'id' => 0,
                    'name' => 'Appbox administrator',
                    'email' => $email,
                    'email_verified_at' => now(),
                    'password' => $hash,
                ]);
                $user->save();
                $user->teams()->syncWithoutDetaching([$team->id => ['role' => 'owner']]);
            }
            // Existing accounts and changed passwords survive restarts and upgrades.
            if (!$user->teams()->where('teams.id', 0)->wherePivot('role', 'owner')->exists()) {
                throw new RuntimeException('Administrator owner role missing');
            }
            $settings->is_registration_enabled = false;
            if (!empty($payload['initial'])) {
                $settings->is_auto_update_enabled = false;
            }
            if (empty($settings->fqdn)) {
                $settings->fqdn = 'https://' . $payload['domain'];
            }
            $settings->save();
            $server = App\Models\Server::findOrFail(0);
            if (empty($server->proxy->get('last_saved_proxy_configuration'))) {
                $server->proxy->set('last_saved_proxy_configuration', $payload['proxy_configuration']);
                $server->save();
            }
        });
        $server = App\Models\Server::findOrFail(0);
        $server->setupDynamicProxyConfiguration();
        if (App\Actions\Proxy\CheckProxy::run($server)) {
            App\Actions\Proxy\StartProxy::run($server, false);
        }
    } else {
        throw new RuntimeException('Unknown operation');
    }
    echo "Coolify account and proxy checks completed.\n";
} catch (Throwable $error) {
    // Exception details can contain credentials or SQL values.
    fwrite(STDERR, "Coolify provisioning failed; installation remains incomplete.\n");
    exit(1);
}
