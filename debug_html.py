#!/usr/bin/env python3
"""Debug script to check markdown library and HTML output"""

# Check HAS_MARKDOWN
try:
    import markdown
    print("✅ markdown import successful - HAS_MARKDOWN = True")
except ImportError:
    print("❌ markdown import failed - HAS_MARKDOWN = False")

# Check generated HTML
import os
if os.path.exists('docs_html/01_GETTING_STARTED.html'):
    with open('docs_html/01_GETTING_STARTED.html', 'r') as f:
        content = f.read()
    
    code_count = content.count('<pre><code')
    print(f"\n01_GETTING_STARTED.html contains {code_count} <pre><code> tags")
    
    # Check if it uses markdown or fallback
    if 'language-' in content:
        print("✅ Code blocks with 'language-' class FOUND (markdown.markdown() output)")
    else:
        print("❌ Code blocks missing language class (fallback converter used)")
        
    # Look for any code at all
    if '<code>' in content:
        print(f"Found {content.count('<code>')} total <code> tags")
    else:
        print("No <code> tags found")
        
    # Show first code block if exists
    start = content.find('<pre><code')
    if start >= 0:
        end = content.find('</code></pre>', start) + len('</code></pre>')
        snippet = content[start:end]
        print(f"\n=== First code block (truncated) ===")
        print(snippet[:500])
    else:
        print("\n❌ No <pre><code blocks found!")
        # Search for ">>>installation" or any code markers
        if '<<<CODE_BLOCK' in content:
            print("Found code block markers - converter completed but markers not replaced")
        
        # Show a section with text we know should have code
        idx = content.find('flutter create')
        if idx > 0:
            print("\nSection with 'flutter create':")
            print(content[max(0, idx-300):min(len(content), idx+500)])
