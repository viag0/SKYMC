#!/bin/bash

set -e

GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
NC="\033[0m"

echo -e "${GREEN}"
echo "==============================================="
echo "  SkyMC Addons Installer for Pterodactyl"
echo "  Project: skymc.xyz"
echo "==============================================="
echo -e "${NC}"

read -rp "[?] Panel directory path [/var/www/pterodactyl]: " PANEL_DIR
PANEL_DIR=${PANEL_DIR:-/var/www/pterodactyl}

read -rp "[?] SkyMC addons directory [/var/skymc]: " SKY_DIR
SKY_DIR=${SKY_DIR:-/var/skymc}

echo -e "${YELLOW}[*] Using panel directory: ${PANEL_DIR}${NC}"
echo -e "${YELLOW}[*] Using SkyMC directory: ${SKY_DIR}${NC}"

if [ ! -d "$PANEL_DIR" ]; then
  echo -e "${RED}[!] Panel directory not found: $PANEL_DIR${NC}"
  exit 1
fi

if [ ! -f "$PANEL_DIR/artisan" ]; then
  echo -e "${RED}[!] artisan not found in panel dir. This doesn't look like a Laravel/Pterodactyl install.${NC}"
  exit 1
fi

cd "$PANEL_DIR"

mkdir -p "$SKY_DIR/addons"
chown -R www-data:www-data "$SKY_DIR" || true

# -----------------------------------------------
# 3) تحديث .env بقيمة SKYMC_ADDONS_PATH
# -----------------------------------------------
ENV_FILE="$PANEL_DIR/.env"
if [ -f "$ENV_FILE" ]; then
  if grep -q '^SKYMC_ADDONS_PATH=' "$ENV_FILE"; then
    sed -i "s#^SKYMC_ADDONS_PATH=.*#SKYMC_ADDONS_PATH=${SKY_DIR}/addons#g" "$ENV_FILE"
  else
    echo "SKYMC_ADDONS_PATH=${SKY_DIR}/addons" >> "$ENV_FILE"
  fi
  echo -e "${YELLOW}[*] Updated .env with SKYMC_ADDONS_PATH=${SKY_DIR}/addons${NC}"
else
  echo -e "${RED}[!] .env not found, make sure to set SKYMC_ADDONS_PATH=${SKY_DIR}/addons manually.${NC}"
fi

# -----------------------------------------------
# 3.5) Config file: config/skymc.php
# -----------------------------------------------
echo -e "${YELLOW}[*] Creating config/skymc.php...${NC}"
mkdir -p config
cat << 'PHP' > config/skymc.php
<?php

return [
    /*
    |--------------------------------------------------------------------------
    | SkyMC Addons Path
    |--------------------------------------------------------------------------
    |
    | This is the base path on the filesystem where SkyMC addons are stored.
    | It can be overridden via SKYMC_ADDONS_PATH in the .env file.
    |
    */

    'addons_path' => env('SKYMC_ADDONS_PATH', '/var/skymc/addons'),
];
PHP

# -----------------------------------------------
# 4) Model: App/Models/SkyAddon.php
# -----------------------------------------------
echo -e "${YELLOW}[*] Creating SkyAddon model...${NC}"
cat << 'PHP' > app/Models/SkyAddon.php
<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class SkyAddon extends Model
{
    protected $table = 'sky_addons';

    protected $fillable = [
        'name',
        'slug',
        'enabled',
    ];

    protected $casts = [
        'enabled' => 'boolean',
    ];
}
PHP

# -----------------------------------------------
# 5) Migration
# -----------------------------------------------
echo -e "${YELLOW}[*] Creating migration for sky_addons...${NC}"
MIGRATION_FILE="database/migrations/2025_01_01_000000_create_sky_addons_table.php"
if [ -f "$MIGRATION_FILE" ]; then
  echo -e "${YELLOW}[!] Migration already exists, skipping.${NC}"
else
  cat << 'PHP' > "$MIGRATION_FILE"
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('sky_addons', function (Blueprint $table) {
            $table->id();
            $table->string('name');
            $table->string('slug')->unique();
            $table->boolean('enabled')->default(false);
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('sky_addons');
    }
};
PHP
fi

echo -e "${YELLOW}[*] Creating SkyAddonController...${NC}"
cat << 'PHP' > app/Http/Controllers/SkyAddonController.php
<?php

namespace App\Http\Controllers;

use App\Models\SkyAddon;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Response;

class SkyAddonController extends Controller
{
    public function index()
    {
        $addons = SkyAddon::orderBy('name')->get();

        return view('admin.addons.index', [
            'addons' => $addons,
        ]);
    }

    public function toggle(Request $request)
    {
        $request->validate([
            'id' => 'required|integer|exists:sky_addons,id',
        ]);

        $addon = SkyAddon::findOrFail($request->input('id'));
        $addon->enabled = ! $addon->enabled;
        $addon->save();

        return back()->with('success', 'Addon status updated.');
    }

    public function delete(Request $request)
    {
        $request->validate([
            'id' => 'required|integer|exists:sky_addons,id',
        ]);

        $addon = SkyAddon::findOrFail($request->input('id'));

        $base = config('skymc.addons_path', env('SKYMC_ADDONS_PATH', '/var/skymc/addons'));
        $targetDir = $base . '/' . $addon->slug;

        if (is_dir($targetDir)) {
            $this->deleteDirectory($targetDir);
        }

        $addon->delete();

        return back()->with('success', 'Addon deleted.');
    }

    protected function deleteDirectory($dir)
    {
        if (! file_exists($dir)) {
            return;
        }

        if (! is_dir($dir)) {
            @unlink($dir);
            return;
        }

        foreach (scandir($dir) as $item) {
            if ($item === '.' || $item === '..') {
                continue;
            }

            $path = $dir . DIRECTORY_SEPARATOR . $item;
            if (is_dir($path)) {
                $this->deleteDirectory($path);
            } else {
                @unlink($path);
            }
        }

        @rmdir($dir);
    }

    public function asset($slug, $file)
    {
        $base = config('skymc.addons_path', env('SKYMC_ADDONS_PATH', '/var/skymc/addons'));
        $baseReal = realpath($base);
        $path = realpath($base . '/' . $slug . '/' . $file);

        if (! $baseReal || ! $path || strncmp($path, $baseReal, strlen($baseReal)) !== 0) {
            abort(404);
        }

        if (! file_exists($path)) {
            abort(404);
        }

        $mime = mime_content_type($path) ?: 'application/octet-stream';

        return Response::file($path, [
            'Content-Type' => $mime,
        ]);
    }
}
PHP

echo -e "${YELLOW}[*] Creating addons blade view...${NC}"
mkdir -p resources/views/admin/addons

cat << 'BLADE' > resources/views/admin/addons/index.blade.php
@extends('layouts.admin')

@section('title')
    Addons Manager
@endsection

@section('content-header')
    <h1>Addons Manager<small>Manage installed addons from SkyMC</small></h1>
@endsection

@section('content')
    @if(session('success'))
        <div class="alert alert-success">{{ session('success') }}</div>
    @endif

    @if(session('error'))
        <div class="alert alert-danger">{{ session('error') }}</div>
    @endif

    {{-- Marketplace box --}}
    <div class="box box-success">
        <div class="box-header with-border">
            <h3 class="box-title">SkyMC Marketplace</h3>
        </div>
        <div class="box-body">
            <p>
                Browse and purchase free or paid addons &amp; themes from the official
                <strong>SkyMC Marketplace</strong>, then install them on your VPS using a single command.
            </p>
            <p>
                After installing an addon on your VPS (via bash command), it will appear in the list below and can be enabled/disabled here.
            </p>
            <a href="https://skymc.xyz/marketplace" target="_blank" class="btn btn-success">
                <i class="fa fa-shopping-cart"></i> Open Marketplace (skymc.xyz)
            </a>
        </div>
    </div>

    {{-- Installed addons --}}
    <div class="box box-default">
        <div class="box-header with-border">
            <h3 class="box-title">Installed Addons</h3>
        </div>
        <div class="box-body table-responsive no-padding">
            <table class="table table-striped">
                <thead>
                    <tr>
                        <th style="width:60px;">ID</th>
                        <th>Name</th>
                        <th>Slug</th>
                        <th style="width:120px;">Status</th>
                        <th style="width:200px;">Actions</th>
                    </tr>
                </thead>
                <tbody>
                @forelse($addons as $addon)
                    <tr>
                        <td>{{ $addon->id }}</td>
                        <td>{{ $addon->name }}</td>
                        <td>{{ $addon->slug }}</td>
                        <td>
                            @if($addon->enabled)
                                <span class="label label-success">Enabled</span>
                            @else
                                <span class="label label-default">Disabled</span>
                            @endif
                        </td>
                        <td>
                            <form action="{{ route('admin.addons.toggle') }}" method="POST" style="display:inline-block">
                                @csrf
                                <input type="hidden" name="id" value="{{ $addon->id }}">
                                <button class="btn btn-xs btn-warning" type="submit">
                                    {{ $addon->enabled ? 'Disable' : 'Enable' }}
                                </button>
                            </form>

                            <form action="{{ route('admin.addons.delete') }}" method="POST" style="display:inline-block" onsubmit="return confirm('Delete this addon?');">
                                @csrf
                                <input type="hidden" name="id" value="{{ $addon->id }}">
                                <button class="btn btn-xs btn-danger" type="submit">
                                    Delete
                                </button>
                            </form>
                        </td>
                    </tr>
                @empty
                    <tr>
                        <td colspan="5">No addons installed yet. Install addons via SkyMC marketplace bash commands.</td>
                    </tr>
                @endforelse
                </tbody>
            </table>
        </div>
    </div>
@endsection
BLADE

echo -e "${YELLOW}[*] Patching routes/admin.php...${NC}"
ADMIN_ROUTES="routes/admin.php"
if [ ! -f "$ADMIN_ROUTES" ]; then
  echo -e "${RED}[!] routes/admin.php not found. This is not a standard Pterodactyl install.${NC}"
else
  if ! grep -q "SkyAddonController" "$ADMIN_ROUTES"; then
    sed -i "1a use App\\Http\\Controllers\\SkyAddonController;" "$ADMIN_ROUTES"
  fi

  if ! grep -q "SkyMC Addons - Admin Addons Manager" "$ADMIN_ROUTES"; then
    cat << 'PHP' >> "$ADMIN_ROUTES"

Route::prefix('/addons')->group(function () {
    Route::get('/', [SkyAddonController::class, 'index'])->name('admin.addons.index');
    Route::post('/toggle', [SkyAddonController::class, 'toggle'])->name('admin.addons.toggle');
    Route::post('/delete', [SkyAddonController::class, 'delete'])->name('admin.addons.delete');
});

Route::get('/skymc/addons/{slug}/{file}', [SkyAddonController::class, 'asset'])
    ->where(['slug' => '[A-Za-z0-9\-_]+', 'file' => '.+']);
PHP
  fi
fi

LAYOUT="resources/views/layouts/admin.blade.php"
if [ -f "$LAYOUT" ]; then
  echo -e "${YELLOW}[*] Patching admin layout...${NC}"

  if ! grep -q "SkyMC Addons" "$LAYOUT"; then
    perl -0pi -e 's#</ul>#    {{-- SkyMC Addons menu --}}\n    <li>\n        <a href="{{ route('\''admin.addons.index'\'') }}">\n            <i class="fa fa-puzzle-piece"></i> <span>SkyMC Addons</span>\n        </a>\n    </li>\n</ul>#s' "$LAYOUT" || true
  fi

  if ! grep -q "SkyMC: Inject CSS" "$LAYOUT"; then
    perl -0pi -e 's#</head>#    {{-- SkyMC: Inject CSS for enabled addons --}}\n    @php($__skyAddons = \\App\\Models\\SkyAddon::where("enabled", true)->get())\n    @foreach($__skyAddons as $__addon)\n        @php($__cssPath = "/skymc/addons/" . $__addon->slug . "/style.css")\n        <link rel="stylesheet" href="{{ url($__cssPath) }}">\n    @endforeach\n</head>#s' "$LAYOUT" || true
  fi

  if ! grep -q "SkyMC: Inject JS" "$LAYOUT"; then
    perl -0pi -e 's#</body>#    {{-- SkyMC: Inject JS for enabled addons --}}\n    @php($__skyAddonsJs = \\App\\Models\\SkyAddon::where("enabled", true)->get())\n    @foreach($__skyAddonsJs as $__addon)\n        @php($__jsPath = "/skymc/addons/" . $__addon->slug . "/script.js")\n        <script src="{{ url($__jsPath) }}"></script>\n    @endforeach\n</body>#s' "$LAYOUT" || true
  fi
else
  echo -e "${RED}[!] Admin layout not found at $LAYOUT${NC}"
fi

echo -e "${YELLOW}[*] Running migrations...${NC}"
php artisan migrate --force

echo -e "${YELLOW}[*] Clearing caches...${NC}"
php artisan view:clear || true
php artisan route:clear || true
php artisan config:clear || true
php artisan cache:clear || true

echo -e "${GREEN}[✓] SkyMC Addons installed successfully!${NC}"
echo -e "${GREEN}    - Menu: Admin » SkyMC Addons${NC}"
echo -e "${GREEN}    - Addons directory: ${SKY_DIR}/addons${NC}"
echo -e "${GREEN}    - Assets served via /skymc/addons/{slug}/{file}${NC}"
