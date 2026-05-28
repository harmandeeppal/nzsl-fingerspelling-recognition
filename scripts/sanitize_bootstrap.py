import re

def sanitize_file(filepath):
    print(f"Sanitizing {filepath}...")
    with open(filepath, "r", encoding="utf-8") as f:
        text = f.read()

    replacements = {
        "\u2014": "--", # em dash
        "\u2013": "-",  # en dash
        "\u2500": "-",  # light horizontal box line
        "\u2550": "=",  # double horizontal box line
        "\u201c": "\"", # left double quote
        "\u201d": "\"", # right double quote
        "\u2018": "'",  # left single quote
        "\u2019": "'",  # right single quote
    }

    for char, replacement in replacements.items():
        text = text.replace(char, replacement)

    with open(filepath, "w", encoding="utf-8") as f:
        f.write(text)
    print("Done.")

if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1:
        sanitize_file(sys.argv[1])
    else:
        sanitize_file("bootstrap.ps1")
