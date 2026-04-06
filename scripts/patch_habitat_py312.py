"""
Patch habitat-lab v0.2.4 for Python 3.12 compatibility.

Python 3.12 enforces that mutable default values in dataclasses must use
field(default_factory=...) instead of direct instantiation.

Usage: python patch_habitat_py312.py
"""
import re
import sys
import site
import os
import glob

def find_habitat_configs():
    """Find all default_structured_configs.py files (habitat and habitat_baselines)."""
    targets = [
        os.path.join("habitat", "config", "default_structured_configs.py"),
        os.path.join("habitat_baselines", "config", "default_structured_configs.py"),
    ]
    found = []
    search_dirs = site.getsitepackages() + [site.getusersitepackages()]
    for sp in search_dirs:
        for target in targets:
            path = os.path.join(sp, target)
            if os.path.exists(path):
                found.append(path)
    # Try common conda paths
    for target in targets:
        for p in glob.glob(f"/opt/conda/envs/*/lib/python*/site-packages/{target}"):
            if p not in found:
                found.append(p)
    return found

def patch_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    # Check if already patched
    if 'default_factory' in content and '# PATCHED' in content:
        print(f"[SKIP] {filepath} already patched")
        return

    original = content

    # Add field import if not present
    if 'from dataclasses import field' not in content:
        content = content.replace(
            'from dataclasses import dataclass',
            'from dataclasses import dataclass, field'
        )

    # Pattern: replace `name: Type = SomeConfig()` with `name: Type = field(default_factory=SomeConfig)`
    # But NOT lines like `height: int = SimulatorSensorConfig().width` (attribute access)
    pattern = r'^(\s+)(\w+):\s+(\w+)\s*=\s*(\w+Config)\(\)\s*$'

    def replacer(match):
        indent = match.group(1)
        name = match.group(2)
        type_hint = match.group(3)
        factory = match.group(4)
        return f"{indent}{name}: {type_hint} = field(default_factory={factory})"

    content = re.sub(pattern, replacer, content, flags=re.MULTILINE)

    # Handle dict defaults like `{"rgb_sensor": PyrobotRGBSensorConfig(), ...}`
    # Replace the whole dict default with a default_factory lambda
    # Find lines with dict containing Config() instances
    dict_pattern = r'^(\s+)(\w+):\s*Dict\[str,\s*(\w+)\]\s*=\s*(\{[^}]+\})\s*$'

    def dict_replacer(match):
        indent = match.group(1)
        name = match.group(2)
        type_hint = match.group(3)
        dict_val = match.group(4)
        return f'{indent}{name}: Dict[str, {type_hint}] = field(default_factory=lambda: {dict_val})'

    content = re.sub(dict_pattern, dict_replacer, content, flags=re.MULTILINE)

    # Add patch marker
    content = content.replace(
        'from dataclasses import dataclass, field',
        'from dataclasses import dataclass, field  # PATCHED for Python 3.12'
    )

    if content != original:
        with open(filepath, 'w') as f:
            f.write(content)
        print(f"[PATCHED] {filepath}")
    else:
        print(f"[NO CHANGE] {filepath}")

if __name__ == "__main__":
    filepaths = find_habitat_configs()
    if not filepaths:
        print("[ERROR] Could not find any habitat config files")
        sys.exit(1)
    for filepath in filepaths:
        patch_file(filepath)
