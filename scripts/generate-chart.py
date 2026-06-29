#!/usr/bin/env python3
"""Cyrene Clang — Benchmark Chart Generator
Generates SVG chart from benchmark results.
Usage: python3 generate-chart.py results.json output.svg
"""
import json
import sys
import os

def generate_svg(results, output_path):
    # Chart dimensions
    WIDTH = 800
    HEIGHT = 400
    PADDING = 60
    BAR_WIDTH = 80
    GAP = 40
    
    # Colors
    COLORS = {
        'no-lto': '#3b82f6',    # Blue
        'thin-lto': '#10b981',  # Green
        'full-lto': '#f59e0b',  # Amber
    }
    
    # Calculate chart area
    chart_width = WIDTH - 2 * PADDING
    chart_height = HEIGHT - 2 * PADDING
    
    # Find max values for scaling
    max_time = max(r['avg_time_ms'] for r in results) if results else 1
    max_size = max(r['avg_size_bytes'] for r in results) if results else 1
    
    # Scale factors
    time_scale = chart_height / (max_time * 1.1) if max_time > 0 else 1
    size_scale = chart_height / (max_size * 1.1) if max_size > 0 else 1
    
    # Start SVG
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {WIDTH} {HEIGHT}">
  <defs>
    <linearGradient id="bg" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" style="stop-color:#1e293b"/>
      <stop offset="100%" style="stop-color:#0f172a"/>
    </linearGradient>
    <filter id="shadow" x="-20%" y="-20%" width="140%" height="140%">
      <feDropShadow dx="2" dy="2" stdDeviation="3" flood-opacity="0.3"/>
    </filter>
  </defs>
  
  <!-- Background -->
  <rect width="{WIDTH}" height="{HEIGHT}" fill="url(#bg)" rx="12"/>
  
  <!-- Title -->
  <text x="{WIDTH//2}" y="30" text-anchor="middle" fill="#e2e8f0" font-family="system-ui, sans-serif" font-size="18" font-weight="bold">
    Cyrene Clang {results[0]['version'] if results else ''} Benchmark
  </text>
  
  <!-- Grid lines -->
'''
    
    # Draw horizontal grid lines
    for i in range(5):
        y = PADDING + (chart_height * i / 4)
        svg += f'  <line x1="{PADDING}" y1="{y}" x2="{WIDTH - PADDING}" y2="{y}" stroke="#334155" stroke-width="1"/>\n'
    
    # Draw bars for compile time
    n = len(results)
    if n > 0:
        group_width = chart_width // 2
        bar_spacing = group_width // (n + 1)
        
        for i, r in enumerate(results):
            # Compile time bar (left side)
            x = PADDING + bar_spacing * (i + 1) - BAR_WIDTH // 2
            bar_height = r['avg_time_ms'] * time_scale
            y = PADDING + chart_height - bar_height
            color = COLORS.get(r.get('lto', 'off'), '#64748b')
            
            svg += f'''  <g filter="url(#shadow)">
    <rect x="{x}" y="{y}" width="{BAR_WIDTH}" height="{bar_height}" fill="{color}" rx="4"/>
    <text x="{x + BAR_WIDTH//2}" y="{y - 5}" text-anchor="middle" fill="#94a3b8" font-family="system-ui, sans-serif" font-size="11">
      {r['avg_time_ms']}ms
    </text>
  </g>
'''
            
            # Label
            svg += f'  <text x="{x + BAR_WIDTH//2}" y="{PADDING + chart_height + 20}" text-anchor="middle" fill="#cbd5e1" font-family="system-ui, sans-serif" font-size="10">\n'
            svg += f'    {r["name"]}\n'
            svg += f'  </text>\n'
    
    # Legend
    legend_y = HEIGHT - 20
    legend_x = PADDING
    for i, (lto, color) in enumerate(COLORS.items()):
        if any(r.get('lto') == lto for r in results):
            svg += f'  <rect x="{legend_x}" y="{legend_y - 10}" width="12" height="12" fill="{color}" rx="2"/>\n'
            svg += f'  <text x="{legend_x + 16}" y="{legend_y}" fill="#94a3b8" font-family="system-ui, sans-serif" font-size="10">{lto}</text>\n'
            legend_x += 80
    
    # Axis labels
    svg += f'''  <text x="{WIDTH//2}" y="{HEIGHT - 5}" text-anchor="middle" fill="#64748b" font-family="system-ui, sans-serif" font-size="12">
    Compile Time (ms) — Lower is better
  </text>
'''
    
    svg += '</svg>'
    
    # Write output
    with open(output_path, 'w') as f:
        f.write(svg)
    
    print(f"Chart generated: {output_path}")

def main():
    if len(sys.argv) < 3:
        print("Usage: python3 generate-chart.py <results.json> <output.svg>")
        sys.exit(1)
    
    results_file = sys.argv[1]
    output_file = sys.argv[2]
    
    with open(results_file) as f:
        results = json.load(f)
    
    generate_svg(results, output_file)

if __name__ == '__main__':
    main()
