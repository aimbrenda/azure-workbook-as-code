#!/bin/bash

# Function to load YAML file
load_yaml_file() {
    local location=$1
    yq eval -o=json "$location"
}

# Function to load JSON file
load_json_file() {
    local location=$1
    cat "$location" | jq .
}

# Function to load template files
load_template() {
    local file_name=$1
    local base_path=$2
    load_json_file "${base_path}templates/${file_name}.json"
}

# Function to process leaf nodes
process_leaf() {
    local node=$1
    local base_path=$2
    local parent=$3

    echo "Processing leaf: $node for parent type $parent"

    if [[ "$parent" == "tabs" ]]; then
        child=$(load_template "tab" "$base_path")
        child=$(echo "$child" | jq --arg subTarget "$node" --arg linkLabel "$node" --arg cellValue "$parent" \
            '.subTarget = $subTarget | .linkLabel = $linkLabel | .cellValue = $cellValue | .style = "secondary"')
    
    elif [[ "$parent" == "parameters" ]]; then
        child=$(load_json_file "$base_path$node")
    
    elif [[ "$node" == "visual" ]]; then
        child=$(load_json_file "$base_path${node['item']}")
        if [[ -n "$node['customWidth']" ]]; then
            child=$(echo "$child" | jq --arg customWidth "$node['customWidth']" '.customWidth = $customWidth')
        fi
    fi

    echo "$child"
}

# Function to enrich parent nodes with their processed children
enrich_parent_with_children() {
    local node=$1
    local base_path=$2
    local children=$3

    if [[ -z "$node['type']" ]]; then
        parent=$(load_template "main" "$base_path")
        parent=$(echo "$parent" | jq --argjson children "$children" '.parameters.workbookContent.value.items = $children')
    else
        case "$node['type']" in
            group)
                parent=$(load_template "group" "$base_path")
                parent=$(echo "$parent" | jq --arg name "$node['name']" --argjson children "$children" \
                    '.name = $name | .content.items = $children')
                if [[ -n "$node['conditionalVisibility']" ]]; then
                    parent=$(echo "$parent" | jq --argjson conditionalVisibility "$node['conditionalVisibility'][0]" \
                        '.conditionalVisibility = $conditionalVisibility')
                fi
                ;;
            tabs)
                parent=$(load_template "tabs" "$base_path")
                parent=$(echo "$parent" | jq --arg name "$node['name']" --argjson children "$children" \
                    '.name = $name | .content.links = $children')
                ;;
            parameters)
                parent=$(load_template "parameters" "$base_path")
                parent=$(echo "$parent" | jq --argjson children "$children" '.content.parameters = $children')
                ;;
        esac
    fi

    echo "$parent"
}

# Function to perform depth-first traversal to process nodes
depth_first_traversal() {
    local node=$1
    local base_path=$2
    local parent=$3

    if [ -n "$node['items']" ]; then
        local children=()
        for item in "${node['items']}"; do
            local child_result
            child_result=$(depth_first_traversal "$item" "$base_path" "$node")
            if [ -n "$child_result" ]; then
                children+=("$child_result")
            fi
        done
        echo "$(enrich_parent_with_children "$node" "$base_path" "${children[@]}")"
    else
        echo "$(process_leaf "$node" "$base_path" "$parent")"
    fi
}

# Function to validate the JSON output against the provided schema
validate_output() {
    local output=$1
    local schema_url=$2

    local schema
    schema=$(curl -s "$schema_url")

    echo "$output" | jq . | jq -e --argjson schema "$schema" 'try . | . | .parameters.workbookContent.value | . = ($schema | .) | true' > /dev/null
    if [ $? -eq 0 ]; then
        echo "JSON output is valid against the schema."
    else
        echo "JSON output is invalid."
        exit 1
    fi
}

# Main function to load workbook, process and validate
main() {
    if [ $# -ne 3 ]; then
        echo "Usage: $0 <workbook_path> <base_path> <out_path>"
        exit 1
    fi

    local workbook_path=$1
    local base_path=$2
    local out_path=$3
    local schema_url="https://raw.githubusercontent.com/Microsoft/Application-Insights-Workbooks/master/schema/workbook.json"

    # Load the workbook YAML
    local input_workbook
    input_workbook=$(load_yaml_file "$workbook_path")

    # Perform depth-first traversal
    local output
    output=$(depth_first_traversal "$input_workbook" "$base_path")

    # Validate the output JSON
    validate_output "$output" "$schema_url"

    # Write the output to a file
    echo "$output" | jq '.' > "$out_path"
}

main "$@"
