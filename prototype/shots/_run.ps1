# Снимает чек-лист RESTYLE-RULES.md §3 через kit scripts/shots.mjs.
$ErrorActionPreference = "Stop"
$env:PLAYWRIGHT_CHROMIUM_CHANNEL = "msedge"
$kit = "c:\Users\dmitriy.gorbanev\YandexDisk\Documents\Work\Obsidian\Repos\ONE.PSIM.PrototypeKit"
$out = "c:\Users\dmitriy.gorbanev\YandexDisk\Documents\Work\Obsidian\Repos\IM\prototype\shots"
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
  Shot "state-warn-hover-$t" $t @("--hover=#eventsList button[data-do=escalate]", "--clip=#eventsList button[data-do=escalate]", "--pad=8")
  Shot "state-warn-pressed-$t" $t @("--press=#eventsList button[data-do=escalate]", "--clip=#eventsList button[data-do=escalate]", "--pad=8")
  Shot "state-outline-hover-$t" $t @("--hover=#eventsList button[data-do=viewForeign]", "--clip=#eventsList button[data-do=viewForeign]", "--pad=8")
  Shot "state-outline-pressed-$t" $t @("--press=#eventsList button[data-do=viewForeign]", "--clip=#eventsList button[data-do=viewForeign]", "--pad=8")
  Shot "state-redirect-hover-$t" $t @("--hover=#eventsList button[data-do=redirect]", "--clip=#eventsList button[data-do=redirect]", "--pad=8")
  Shot "state-redirect-pressed-$t" $t @("--press=#eventsList button[data-do=redirect]", "--clip=#eventsList button[data-do=redirect]", "--pad=8")
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
  Shot "state-dialog-esc-$t" $t @("--click=#eventsList button[data-do=escalate]", "--clip=.modal-card", "--pad=12")
}
