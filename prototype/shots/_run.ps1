# Снимает чек-лист RESTYLE-RULES.md §3 через kit scripts/shots.mjs.
# Нужны клон дизайн-кита ONE.PSIM.PrototypeKit (по умолчанию — рядом с этим репозиторием,
# иначе путь в переменной ONE_PSIM_KIT), Node и Edge, и сервер от корня репозитория:
#   npx http-server . -p 4173 -c-1
$ErrorActionPreference = "Stop"
$env:PLAYWRIGHT_CHROMIUM_CHANNEL = "msedge"
$out = $PSScriptRoot
$repo = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$kit = if ($env:ONE_PSIM_KIT) { $env:ONE_PSIM_KIT } else { Join-Path (Split-Path $repo -Parent) "ONE.PSIM.PrototypeKit" }
$url = "http://127.0.0.1:4173/prototype/index.html"
Set-Location $kit

function Shot([string]$name, [string]$theme, [string[]]$extra) {
  $init = "localStorage.setItem('im-theme','$theme')"
  $args = @(
    "scripts/shots.mjs",
    "--url=$url",
    "--init=$init",
    "--theme=$theme",
    "--out=$out\$name.png"
  ) + $extra
  Write-Host ">> $name"
  node @args
}

foreach ($t in @("dark", "light")) {
  Shot "restyled-$t" $t @()
  Shot "state-primary-hover-$t" $t @("--hover=#eventsList button[data-do=claim]", "--clip=#eventsList button[data-do=claim]", "--pad=8")
  Shot "state-primary-pressed-$t" $t @("--press=#eventsList button[data-do=claim]", "--clip=#eventsList button[data-do=claim]", "--pad=8")
  Shot "state-warn-hover-$t" $t @("--hover=#eventsList button[data-do=transfer]", "--clip=#eventsList button[data-do=transfer]", "--pad=8")
  Shot "state-warn-pressed-$t" $t @("--press=#eventsList button[data-do=transfer]", "--clip=#eventsList button[data-do=transfer]", "--pad=8")
  Shot "state-outline-hover-$t" $t @("--hover=#eventsList button[data-do=open_readonly]", "--clip=#eventsList button[data-do=open_readonly]", "--pad=8")
  Shot "state-outline-pressed-$t" $t @("--press=#eventsList button[data-do=open_readonly]", "--clip=#eventsList button[data-do=open_readonly]", "--pad=8")
  Shot "state-toggle-rest-$t" $t @("--clip=#toggleGroups", "--pad=8")
  Shot "state-toggle-hover-$t" $t @("--hover=#toggleGroups", "--clip=#toggleGroups", "--pad=8")
  Shot "state-toggle-pressed-$t" $t @("--press=#toggleGroups", "--clip=#toggleGroups", "--pad=8")
  Shot "state-theme-hover-$t" $t @("--hover=#themeToggle", "--clip=#themeToggle", "--pad=8")
  Shot "state-card-hover-$t" $t @("--hover=#eventsList .event", "--clip=#eventsList .event", "--pad=8")
  Shot "state-card-hover-btn-$t" $t @("--hover=#eventsList .event .btn.primary", "--clip=#eventsList .event", "--pad=8")
  Shot "state-brand-$t" $t @("--clip=.brand", "--pad=8")
  Shot "state-badge-foreign-$t" $t @("--clip=.badge.foreign", "--pad=10")
  Shot "state-seg-$t" $t @("--clip=.seg", "--pad=8")
  Shot "state-select-open-$t" $t @("--click=#eventFilter", "--clip=#eventFilter", "--pad=8", "--below=220")
  Shot "state-dialog-transfer-$t" $t @("--click=#eventsList button[data-do=transfer]", "--clip=.modal-card", "--pad=12")
}
