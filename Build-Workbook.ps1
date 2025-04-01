param (
    [string]$workbookPath,
    [string]$basePath,
    [string]$outPath
)

function Load-YamlFile {
    param ([string]$location)
    yq eval -o=json $location | ConvertFrom-Json
}

function Load-JsonFile {
    param ([string]$location)
    Get-Content -Raw -Path $location | ConvertFrom-Json
}

function Load-Template {
    param (
        [string]$fileName,
        [string]$basePath
    )
    Load-JsonFile -location $basePath + "templates/$fileName.json"
}

function Process-Leaf {
    param (
        [PSObject]$node,
        [string]$basePath,
        [PSObject]$parent
    )

    Write-Output "Processing leaf: $node for parent type $($parent.type)"
    $child = $null

    switch ($parent.type) {
        'tabs' {
            $child = Load-Template -fileName "tab" -basePath $basePath
            $child.subTarget = $node.value
            $child.linkLabel = $node.label
            $child.cellValue = $parent.parameterName
            if ($node.default) {
                $child.style = 'primary'
            } else {
                $child.style = 'secondary'
            }
        }
        'parameters' {
            $child = Load-JsonFile -location "$basePath$node"
        }
        'visual' {
            $child = Load-JsonFile -location "$basePath$($node.item)"
            if ($node.customWidth) {
                $child.customWidth = $node.customWidth
            }
        }
    }

    return $child
}

function Enrich-ParentWithChildren {
    param (
        [PSObject]$node,
        [string]$basePath,
        [array]$children
    )

    $parent = $null

    if (-not $node.type) {
        $parent = Load-Template -fileName "main" -basePath $basePath
        $parent.parameters.workbookContent.value.items = $children
    } else {
        switch ($node.type) {
            'group' {
                $parent = Load-Template -fileName "group" -basePath $basePath
                $parent.name = $node.name
                $parent.content.items = $children
                if ($node.conditionalVisibility) {
                    $parent.conditionalVisibility = $node.conditionalVisibility[0]
                }
            }
            'tabs' {
                $parent = Load-Template -fileName "tabs" -basePath $basePath
                $parent.name = $node.name
                $parent.content.links = $children
            }
            'parameters' {
                $parent = Load-Template -fileName "parameters" -basePath $basePath
                $parent.content.parameters = $children
            }
        }
    }

    if ($node.type) {
        Write-Output "Enriched parent of type '$($node.type)': $parent with children: $children"
    } else {
        Write-Output "Enriched main parent: $parent with children: $children"
    }

    return $parent
}

function Depth-FirstTraversal {
    param (
        [PSObject]$node,
        [string]$basePath,
        [PSObject]$parent
    )

    if ($node.items) {
        $children = @()
        foreach ($item in $node.items) {
            $childResult = Depth-FirstTraversal -node $item -basePath $basePath -parent $node
            if ($childResult) {
                $children += $childResult
            }
        }
        return Enrich-ParentWithChildren -node $node -basePath $basePath -children $children
    } else {
        return Process-Leaf -node $node -basePath $basePath -parent $parent
    }
}

function Validate-Output {
    param (
        [PSObject]$output,
        [string]$schemaUrl
    )

    $schema = Invoke-RestMethod -Uri $schemaUrl

    try {
        $output | ConvertTo-Json -Depth 10 | jq -e --argjson schema $schema 'try . | .parameters.workbookContent.value | . = ($schema | .) | true' > $null
        Write-Output "JSON output is valid against the schema."
    } catch {
        throw "JSON output is invalid: $_"
    }
}

function Main {
    if ($PSCmdlet.MyInvocation.BoundParameters.Count -ne 3) {
        throw "Usage: script.ps1 <workbook_path> <base_path> <out_path>"
    }

    $schemaUrl = "https://raw.githubusercontent.com/Microsoft/Application-Insights-Workbooks/master/schema/workbook.json"

    # Load the workbook YAML
    $inputWorkbook = Load-YamlFile -location $workbookPath

    # Perform depth-first traversal
    $output = Depth-FirstTraversal -node $inputWorkbook.workbook -basePath $basePath

    # Validate the output JSON
    Validate-Output -output $output -schemaUrl $schemaUrl

    # Write the output to a file
    $output | ConvertTo-Json -Depth 10 | Out-File -FilePath $outPath -Force
}

Main
