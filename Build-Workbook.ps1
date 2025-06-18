# Requires -Modules powershell-yaml

param(
    [Parameter(Mandatory=$true)][string]$workbookPath,
    [Parameter(Mandatory=$true)][string]$basePath,
    [Parameter(Mandatory=$true)][string]$outFile
)

function Load-YamlFile($location) {
    try {
        return ConvertFrom-Yaml (Get-Content $location -Raw)
    } catch {
        throw "Error loading YAML file ${location}: $_"
    }
}

function Load-JsonFile($location) {
    try {
        return Get-Content $location -Raw | ConvertFrom-Json
    } catch {
        throw "Error loading JSON file ${location}: $_"
    }
}

function Load-Template($fileName) {
    $templatePath = "templates\$fileName.json"
    return Load-JsonFile $templatePath
}

function Process-Leaf($node, $basePath, $parent) {
    Write-Host "Processing leaf: $node for parent type $($parent.type)"
    $child = $null

    if ($parent.type -eq "tabs") {
        $child = Load-Template "tab"
        $child.subTarget = $node.value
        $child.linkLabel = $node.label
        $child.cellValue = $parent.parameterName
        $child.style = if ($node.default) { "primary" } else { "secondary" }
    } elseif ($parent.type -eq "parameters") {
        $child = Load-JsonFile (Join-Path $basePath $node)
    } elseif ($node.type -eq "visual") {
        $child = Load-JsonFile (Join-Path $basePath $node.item)
        if ($node.ContainsKey("customWidth")) {
            $w = $node.customWidth
            $child | Add-Member -NotePropertyName "customWidth" -NotePropertyValue $w
        }
    }
    return $child
}

function Enrich-ParentWithChildren($node, $children) {
    $parent = $null
    if (-not ($node -is [hashtable])) { return $parent }
    $nodeType = $node.type
    if (-not $nodeType) {
        $parent = Load-Template "main"
        $parent.parameters.workbookContent.value.items = $children
    } elseif ($nodeType -eq "group") {
        $parent = Load-Template "group"
        $parent.name = $node.name
        $parent.content = @{ items = $children }
        if ($node.conditionalVisibility) {
            $parent.conditionalVisibility = $node.conditionalVisibility[0]
        }
    } elseif ($nodeType -eq "tabs") {
        $parent = Load-Template "tabs"
        $parent.name = $node.name
        $parent.content = @{ links = $children }
    } elseif ($nodeType -eq "parameters") {
        $parent = Load-Template "parameters"
        $parent.content.parameters = $children
    }
    if ($nodeType) {
        Write-Host "Enriched parent of type '$nodeType': $parent with children: $children"
    } else {
        Write-Host "Enriched main parent: $parent with children: $children"
    }
    return $parent
}

function Depth-First-Traversal($node, $basePath, $parent = $null) {
    if ($node -is [hashtable]) {
        $children = @()
        if ($node.items) {
            foreach ($item in $node.items) {
                if ($item) {
                    Write-Host "Visiting item: $item"
                    $children += Depth-First-Traversal $item $basePath $node
                }
            }
        }
        if ($children.Count -gt 0) {
            return Enrich-ParentWithChildren $node $children
        }
    }
    return Process-Leaf $node $basePath $parent
}


# Main logic
$inputWorkbook = Load-YamlFile $workbookPath
$output = Depth-First-Traversal $inputWorkbook.workbook $basePath

$output | ConvertTo-Json -Depth 20 -Compress| Set-Content $outFile