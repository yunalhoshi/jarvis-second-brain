# Reads every .md note in the vault folders, finds the [[links]] inside them,
# ties each note to the main node named in its "hub:" field
# and writes the result to graph.json (plus graph.js, which index.html loads).

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$folders = 'Router', 'Wiki', 'Concepts', 'Skills', 'Tools', 'Notes', 'Projects', 'Files'
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Get-FrontmatterValue($frontmatter, $key) {
    if ($frontmatter -match "(?m)^$key\s*:\s*(.+?)\s*$") { return $Matches[1] }
    return ''
}

# 1) One node per note
$nodes = @()
$byName = @{}
foreach ($folder in $folders) {
    $path = Join-Path $root $folder
    if (-not (Test-Path $path)) { continue }
    foreach ($file in Get-ChildItem -Path $path -Recurse -Filter *.md -File) {
        $text = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
        $frontmatter = ''
        if ($text -match '(?s)^---\r?\n(.*?)\r?\n---') { $frontmatter = $Matches[1] }

        $title = Get-FrontmatterValue $frontmatter 'title'
        if (-not $title) { $title = $file.BaseName }
        $tags = @((Get-FrontmatterValue $frontmatter 'tags').Trim('[', ']').Split(',') |
            ForEach-Object { $_.Trim() } | Where-Object { $_ })

        $node = [ordered]@{
            id      = $file.BaseName
            title   = $title
            group   = $folder
            type    = Get-FrontmatterValue $frontmatter 'type'
            tags    = $tags
            created = Get-FrontmatterValue $frontmatter 'created'
            hub     = Get-FrontmatterValue $frontmatter 'hub'
            isHub   = $false
            path    = $file.FullName.Substring($root.Length + 1).Replace('\', '/')
            content = $text
        }
        if (-not $byName.ContainsKey($file.BaseName)) {
            $byName[$file.BaseName] = $node
            $nodes += $node
        }
    }
}

# 2) One link per [[link]] that points to an existing note
$links = @()
$seen = @{}
$linkPattern = '\[\[([^\]\|#]+)(?:#[^\]\|]*)?(?:\|[^\]]*)?\]\]'
foreach ($node in $nodes) {
    foreach ($match in [regex]::Matches($node.content, $linkPattern)) {
        $targetName = $match.Groups[1].Value.Trim()
        if (-not $byName.ContainsKey($targetName)) { continue }
        $target = $byName[$targetName].id
        if ($target -eq $node.id) { continue }
        $key = $node.id + '|' + $target
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $links += [ordered]@{ source = $node.id; target = $target }
    }
}

# 3) Hubs: every "hub:" value becomes a main node and each note is tied to its hub.
#    A note whose file name equals the hub name (e.g. the university note) is the hub itself.
$noHub = @()
foreach ($node in @($nodes)) {
    if (-not $node.hub) { $noHub += $node.path; continue }
    if (-not $byName.ContainsKey($node.hub)) {
        $hubNode = [ordered]@{
            id = $node.hub; title = $node.hub; group = 'Hub'; type = 'hub'; tags = @()
            created = ''; hub = $node.hub; isHub = $true; path = ''; content = ''
        }
        $byName[$node.hub] = $hubNode
        $nodes += $hubNode
    }
    $hubNode = $byName[$node.hub]
    $hubNode.isHub = $true
    $hubNode.hub = $hubNode.id
    if ($hubNode.id -eq $node.id) { continue }
    $links += [ordered]@{ source = $node.id; target = $hubNode.id; hubLink = $true }
}
if ($noHub.Count) {
    Write-Host "WARNING - notes without a hub:"
    $noHub | ForEach-Object { Write-Host "  $_" }
}

# 4) Calendar: the table rows in Notes/Takvim.md feed the "this week" panel
$calendar = [ordered]@{ updated = ''; events = @() }
if ($byName.ContainsKey('Takvim')) {
    $calendarText = $byName['Takvim'].content
    if ($calendarText -match '(?m)^Son g.ncelleme:\s*(.+?)\s*$') { $calendar.updated = $Matches[1] }
    $rows = @($calendarText -split '\r?\n' | Where-Object { $_.Trim().StartsWith('|') })
    foreach ($row in ($rows | Select-Object -Skip 2)) {
        $cells = @($row.Trim().Trim('|').Split('|') | ForEach-Object { $_.Trim() })
        if ($cells.Count -lt 3) { continue }
        $calendar.events += [ordered]@{
            day   = $cells[0]
            time  = $cells[1]
            title = $cells[2]
            place = $(if ($cells.Count -gt 3) { $cells[3] } else { '' })
        }
    }
}

# 5) Save
$graph = [ordered]@{
    generated = (Get-Date).ToString('yyyy-MM-dd HH:mm')
    calendar  = $calendar
    nodes     = @($nodes)
    links     = @($links)
}
$json = $graph | ConvertTo-Json -Depth 6
[System.IO.File]::WriteAllText((Join-Path $root 'graph.json'), $json, $utf8)
[System.IO.File]::WriteAllText((Join-Path $root 'graph.js'), "window.GRAPH_DATA = $json;", $utf8)

Write-Host "$($nodes.Count) notes, $($links.Count) links -> graph.json"
