import yaml
import json
import sys
import requests
from jsonschema import validate, ValidationError
import os


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


def load_template(file_name):
    return load_json_file(os.path.join(os.path.dirname(__file__), 'templates', f'{file_name}.json'))


def process_leaf(node, base_path, parent):
    """Process leaf nodes based on parent type and node attributes."""
    print(f'Processing leaf: {node} for parent type {parent["type"]}')
    child = None

    if parent['type'] == 'tabs':
        child = load_template('tab')
        child.update({
            'subTarget': node['value'],
            'linkLabel': node['label'],
            'cellValue': parent['parameterName'],
            'style': 'primary' if node.get('default') else 'secondary'
        })
    elif parent['type'] == 'parameters':
        child = load_json_file(os.path.join(base_path, node))
    elif node['type'] == 'visual':
        child = load_json_file(os.path.join(base_path, node['item']))
        if 'customWidth' in node:
            child['customWidth'] = node['customWidth']

    return child


def enrich_parent_with_children(node, children):
    """Enrich parent nodes with their processed children."""
    parent = None

    if not isinstance(node, dict):
        return parent

    node_type = node.get('type')
    if not node_type:
        parent = load_template('main')
        parent['parameters']['workbookContent']['value']['items'] = children
    elif node_type == 'group':
        parent = load_template('group')
        parent.update({
            'name': node['name'],
            'content': {'items': children}
        })
        if 'conditionalVisibility' in node:
            parent['conditionalVisibility'] = node['conditionalVisibility'][0]
    elif node_type == 'tabs':
        parent = load_template('tabs')
        parent.update({
            'name': node['name'],
            'content': {'links': children}
        })
    elif node_type == 'parameters':
        parent = load_template('parameters')
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
            return enrich_parent_with_children(node, children)
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
    if len(sys.argv) < 4 or len(sys.argv) > 5:
        raise Exception("Usage: script.py <workbook_path> <base_path> <out_file> <validate_against_schema>(optional "
                        "default 0)")

    validate_against_schema = False

    if len(sys.argv) == 4:
        workbook_path, base_path, out_path = sys.argv[1:4]
    else:
        workbook_path, base_path, out_path = sys.argv[1:4]
        validate_against_schema = sys.argv[4].lower() == '1'

    # Load the workbook YAML
    input_workbook = load_yaml_file(workbook_path)
    output = depth_first_traversal(input_workbook['workbook'], base_path)

    # Validate the output JSON
    if validate_against_schema:
        schema_url = 'https://raw.githubusercontent.com/Microsoft/Application-Insights-Workbooks/master/schema/workbook.json'
        validate_output(output, schema_url)

    # Write the output to a file
    with open(out_path, 'w') as outf:
        outf.write(json.dumps(output, indent=2))


if __name__ == '__main__':
    main()
