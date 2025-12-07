#!/bin/bash
set -euo pipefail

GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
CYAN="\033[0;36m"
PURPLE="\033[0;35m"
NC="\033[0m"

clear
echo -e "${CYAN}"
echo " ███████╗██╗  ██╗██╗   ██╗███╗   ███╗ ██████╗ "
echo " ██╔════╝██║ ██╔╝╚██╗ ██╔╝████╗ ████║██╔════╝ "
echo " ███████╗█████╔╝  ╚████╔╝ ██╔████╔██║██║      "
echo " ╚════██║██╔═██╗   ╚██╔╝  ██║╚██╔╝██║██║      "
echo " ███████║██║  ██╗   ██║   ██║ ╚═╝ ██║╚██████╗ "
echo " ╚══════╝╚═╝  ╚═╝   ╚═╝   ╚═╝     ╚═╝ ╚═════╝ "
echo -e "${PURPLE}"
echo "    SkyMC Addons & Themes Manager for Pterodactyl"
echo "            Version 1.4.1-STABLE"
echo "================================================="
echo -e "${NC}"

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Run installer as root only.${NC}"
  exit 1
fi

AUTO_PANEL=$(find /var/www -maxdepth 3 -name artisan 2>/dev/null | head -n 1 | sed 's|/artisan||')

read -rp "[?] Panel path [${AUTO_PANEL:-/var/www/pterodactyl}]: " PANEL_DIR
PANEL_DIR=${PANEL_DIR:-${AUTO_PANEL:-/var/www/pterodactyl}}

read -rp "[?] SkyMC Path [/var/skymc]: " SKY_DIR
SKY_DIR=${SKY_DIR:-/var/skymc}

[ -f "$PANEL_DIR/artisan" ] || { echo -e "${RED}artisan not found.${NC}"; exit 1; }

cd "$PANEL_DIR"

mkdir -p "$SKY_DIR/addons"
chown -R www-data:www-data "$SKY_DIR"
chmod -R ug+rwX,o-rwx "$SKY_DIR"

ENV_FILE="$PANEL_DIR/.env"
grep -q '^SKYMC_ADDONS_PATH=' "$ENV_FILE" \
&& sed -i "s|^SKYMC_ADDONS_PATH=.*|SKYMC_ADDONS_PATH=${SKY_DIR}/addons|" "$ENV_FILE" \
|| echo "SKYMC_ADDONS_PATH=${SKY_DIR}/addons" >> "$ENV_FILE"

mkdir -p config app/Models app/Http/Controllers resources/views/admin/addons resources/views/partials

cat > config/skymc.php << 'PHP'
<?php
return [
    'addons_path' => env('SKYMC_ADDONS_PATH', '/var/skymc/addons'),
];
PHP

cat > app/Models/SkyAddon.php << 'PHP'
<?php
namespace App\Models;
use Illuminate\Database\Eloquent\Model;

class SkyAddon extends Model {
    protected $fillable = ['name','slug','enabled'];
    protected $casts = ['enabled'=>'boolean'];
}
PHP

MIG="database/migrations/2025_01_01_000000_create_sky_addons_table.php"
if [ ! -f "$MIG" ]; then
cat > "$MIG" << 'PHP'
<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up() {
        Schema::create('sky_addons', function(Blueprint $t){
            $t->id();
            $t->string('name');
            $t->string('slug')->unique();
            $t->boolean('enabled')->default(false);
            $t->timestamps();
        });
    }
    public function down() {
        Schema::dropIfExists('sky_addons');
    }
};
PHP
fi

cat > app/Http/Controllers/SkyAddonController.php << 'PHP'
<?php
namespace App\Http\Controllers;

use App\Models\SkyAddon;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\File;
use Illuminate\Support\Facades\Response;

class SkyAddonController extends Controller {

    public function index(){
        return view('admin.addons.index', [
            'addons' => SkyAddon::orderBy('name')->get()
        ]);
    }

    public function toggle(Request $r){
        $a = SkyAddon::findOrFail($r->id);
        $a->enabled = !$a->enabled;
        $a->save();
        return back();
    }

    public function delete(Request $r){
        $a = SkyAddon::findOrFail($r->id);
        $base = realpath(config('skymc.addons_path'));
        $dir  = realpath($base.'/'.$a->slug);

        if($dir && strpos($dir,$base)===0){
            File::deleteDirectory($dir);
        }
        $a->delete();
        return back();
    }

    public function asset($slug,$file){
        $allowed = ['css','js','png','jpg','webp','svg'];
        $ext = strtolower(pathinfo($file,PATHINFO_EXTENSION));
        if(!in_array($ext,$allowed)) abort(403);

        $base = realpath(config('skymc.addons_path'));
        $path = realpath($base.'/'.$slug.'/'.$file);
        if(!$path || strpos($path,$base)!==0) abort(404);

        return Response::file($path);
    }
}
PHP

cat > resources/views/admin/addons/index.blade.php << 'BLADE'
@extends('layouts.admin')
@section('title','SkyMC Addons')

@section('content')
<div class="box box-primary">
  <div class="box-header"><h3>SkyMC Addons</h3></div>
  <div class="box-body table-responsive">
    <table class="table table-striped">
      <thead>
        <tr>
          <th>ID</th><th>Name</th><th>Slug</th><th>Status</th><th>Actions</th>
        </tr>
      </thead>
      <tbody>
        @foreach($addons as $a)
        <tr>
          <td>{{ $a->id }}</td>
          <td>{{ $a->name }}</td>
          <td>{{ $a->slug }}</td>
          <td>{{ $a->enabled ? 'Enabled':'Disabled' }}</td>
          <td style="display:flex;gap:5px">
            <form method="POST" action="{{ route('admin.addons.toggle') }}">
              @csrf
              <input type="hidden" name="id" value="{{ $a->id }}">
              <button class="btn btn-xs btn-warning">Toggle</button>
            </form>

            <form method="POST" action="{{ route('admin.addons.delete') }}" onsubmit="return confirm('Delete this addon?')">
              @csrf
              <input type="hidden" name="id" value="{{ $a->id }}">
              <button class="btn btn-xs btn-danger">Delete</button>
            </form>
          </td>
        </tr>
        @endforeach
      </tbody>
    </table>
  </div>
</div>
@endsection
BLADE

cat > resources/views/partials/skymc_assets.blade.php << 'BLADE'
@php use App\Models\SkyAddon; $addons=SkyAddon::where('enabled',1)->get(); @endphp
@foreach($addons as $a)
<link rel="stylesheet" href="{{ route('admin.addons.asset',['slug'=>$a->slug,'file'=>'style.css']) }}">
<script src="{{ route('admin.addons.asset',['slug'=>$a->slug,'file'=>'script.js']) }}" defer></script>
@endforeach
BLADE

ROUTES="routes/admin.php"
if ! grep -q "SkyAddonController" "$ROUTES" 2>/dev/null; then
  sed -i "/<?php/a use App\\\\Http\\\\Controllers\\\\SkyAddonController;" "$ROUTES"
  cat >> "$ROUTES" << 'PHP'

Route::prefix('addons')->group(function(){
    Route::get('/',[SkyAddonController::class,'index'])->name('admin.addons.index');
    Route::post('/toggle',[SkyAddonController::class,'toggle'])->name('admin.addons.toggle');
    Route::post('/delete',[SkyAddonController::class,'delete'])->name('admin.addons.delete');
    Route::get('/asset/{slug}/{file}',[SkyAddonController::class,'asset'])->where('file','.*')->name('admin.addons.asset');
});
PHP
fi

if [ -f "resources/views/layouts/admin.blade.php" ]; then
  grep -q "skymc_assets" resources/views/layouts/admin.blade.php || \
  sed -i "/<\/head>/i @include('partials.skymc_assets')" resources/views/layouts/admin.blade.php
fi

php artisan migrate --force

php << 'PHP'
<?php
require 'vendor/autoload.php';
$app=require 'bootstrap/app.php';
$kernel=$app->make(Illuminate\Contracts\Console\Kernel::class);
$kernel->bootstrap();
$dir=config('skymc.addons_path');
foreach(scandir($dir) as $a){
 if($a==='.'||$a==='..')continue;
 if(is_dir($dir.'/'.$a)){
  \App\Models\SkyAddon::firstOrCreate(
    ['slug'=>$a],
    ['name'=>ucfirst($a),'enabled'=>0]
  );
 }
}
PHP

php artisan optimize:clear

echo -e "${GREEN}[✓] SkyMC Installed Successfully${NC}"
echo -e "${CYAN}Visit: /admin/addons${NC}"
