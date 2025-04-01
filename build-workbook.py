import yaml
import json
import sys
import requests
from jsonschema import validate, ValidationError


def load_yaml_file(location):
    try:
        with open(location, 'r') as stream:
            return yaml.safe_load(stream)
    except Exception as e:
        raise Exception(f"Error loading YAML file {location}: {e}")


def load_json_file(location):
    try:
        with open(location, 'r') as file:
            return json.load(file)
    except Exception as e:
        raise Exception(f"Error loading JSON file {location}: {e}")


def load_template(file_name, base_path):
    return load_json_file(f"{base_path}templates/{file_name}.json")


def process_leaf(node, base_path, parent):
    """Process leaf nodes based on parent type and node attributes."""
    print(f'Processing leaf: {node} for parent type {parent["type"]}')
    child = None

    if parent['type'] == 'tabs':
        child = load_template('tab', base_path)
        child.update({
            'subTarget': node['value'],
            'linkLabel': node['label'],
            'cellValue': parent['parameterName'],
            'style': 'primary' if node.get('default') else 'secondary'
        })
    elif parent['type'] == 'parameters':
        child = load_json_file(f"{base_path}{node}")
    elif node['type'] == 'visual':
        child = load_json_file(f"{base_path}{node['item']}")
        if 'customWidth' in node:
            child['customWidth'] = node['customWidth']

    return child


def enrich_parent_with_children(node, base_path, children):
    """Enrich parent nodes with their processed children."""
    parent = None

    if not isinstance(node, dict):
        return parent

    node_type = node.get('type')
    if not node_type:
        parent = load_template('main', base_path)
        parent['parameters']['workbookContent']['value']['items'] = children
    elif node_type == 'group':
        parent = load_template('group', base_path)
        parent.update({
            'name': node['name'],
            'content': {'items': children}
        })
        if 'conditionalVisibility' in node:
            parent['conditionalVisibility'] = node['conditionalVisibility'][0]
    elif node_type == 'tabs':
        parent = load_template('tabs', base_path)
        parent.update({
            'name': node['name'],
            'content': {'links': children}
        })
    elif node_type == 'parameters':
        parent = load_template('parameters', base_path)
        parent['content']['parameters'] = children

    if node_type:
        print(f'Enriched parent of type "{node_type}": {parent} with children: {children}')
    else:
        print(f'Enriched main parent: {parent} with children: {children}')

    return parent


def depth_first_traversal(node, base_path, parent=None):
    """Perform depth-first traversal to process nodes."""
    if isinstance(node, dict):
        children = [depth_first_traversal(item, base_path, node) for item in node.get('items', []) if item]
        if children:
            return enrich_parent_with_children(node, base_path, children)
    return process_leaf(node, base_path, parent)


def validate_output(output, schema_url):
    """Validate the JSON output against the provided schema."""
    response = requests.get(schema_url)
    schema = response.json()

    try:
        validate(instance=output['parameters']['workbookContent']['value'], schema=schema)
        print("JSON output is valid against the schema.")
    except ValidationError as e:
        raise Exception(f"JSON output is invalid: {e.message}")


def main():
    """Main function to load workbook, process and validate."""
    if len(sys.argv) != 4:
        raise Exception("Usage: script.py <workbook_path> <base_path> <out_path>")

    workbook_path, base_path, out_path = sys.argv[1:4]
    schema_url = 'https://raw.githubusercontent.com/Microsoft/Application-Insights-Workbooks/master/schema/workbook.json'

    # Load the workbook YAML
    input_workbook = load_yaml_file(workbook_path)
    output = depth_first_traversal(input_workbook['workbook'], base_path)

    # Validate the output JSON
    validate_output(output, schema_url)

    # Write the output to a file
    with open(out_path, 'w') as outf:
        json.dump(output, outf, indent=2)


if __name__ == '__main__':
    main()
