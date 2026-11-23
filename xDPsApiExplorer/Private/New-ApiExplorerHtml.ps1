function New-ApiExplorerHtml {
    <#
    .SYNOPSIS
        Generates a 100% offline HTML5 interactive Native UML Box-Tree Explorer with full .NET type names.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$NodeTree,

        [Parameter(Mandatory = $true)]
        [int]$MaxDepth,

        [Parameter(Mandatory = $true)]
        [string]$RootName
    )

    $jsonPayload = $NodeTree | ConvertTo-Json -Depth 35 -Compress

    $html = @'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>xDlabs | ApiExplorer - __ROOT_NAME__</title>
<style>
    :root {
        --bg-main: #090d16;
        --bg-panel: #111827;
        --bg-card: #162032;
        --border-color: #2e3f5c;
        --accent-emerald: #10b981;
        --accent-cyan: #06b6d4;
        --accent-purple: #a855f7;
        --accent-amber: #f59e0b;
        --text-primary: #f8fafc;
        --text-secondary: #94a3b8;
        --text-muted: #64748b;
        --font-mono: 'Cascadia Code', 'Consolas', 'JetBrains Mono', monospace;
        --font-sans: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
        background-color: var(--bg-main);
        color: var(--text-primary);
        font-family: var(--font-sans);
        height: 100vh;
        width: 100vw;
        overflow: hidden;
        display: flex;
        flex-direction: column;
    }
    header {
        height: 58px;
        background: linear-gradient(90deg, #090d16 0%, #064e3b 50%, #090d16 100%);
        border-bottom: 1px solid var(--border-color);
        display: flex;
        align-items: center;
        justify-content: space-between;
        padding: 0 20px;
        z-index: 20;
        box-shadow: 0 4px 20px rgba(0,0,0,0.45);
    }
    .brand {
        display: flex;
        align-items: center;
        gap: 12px;
    }
    .brand-logo {
        background: linear-gradient(135deg, var(--accent-emerald), var(--accent-cyan));
        color: #042f2e;
        font-weight: 900;
        font-family: var(--font-mono);
        padding: 5px 10px;
        border-radius: 6px;
        font-size: 14px;
        letter-spacing: 0.5px;
    }
    .brand-title { font-size: 16px; font-weight: 700; }
    .brand-subtitle {
        font-size: 12px;
        color: #34d399;
        font-family: var(--font-mono);
        background: rgba(16, 185, 129, 0.14);
        padding: 3px 8px;
        border-radius: 4px;
        border: 1px solid rgba(16, 185, 129, 0.35);
    }
    .brand-social-link {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        width: 24px;
        height: 24px;
        border-radius: 5px;
        text-decoration: none;
        font-family: var(--font-sans);
        font-weight: 800;
        font-size: 12px;
        transition: all 0.15s;
    }
    .brand-li {
        background: #0a66c2;
        color: #ffffff;
        border: 1px solid rgba(255, 255, 255, 0.2);
    }
    .brand-li:hover {
        background: #004182;
        box-shadow: 0 0 10px rgba(10, 102, 194, 0.6);
    }
    .brand-gh {
        background: #1e293b;
        color: #f8fafc;
        border: 1px solid #475569;
    }
    .brand-gh:hover {
        background: #334155;
        border-color: var(--accent-emerald);
        color: #34d399;
    }
    .toolbar { display: flex; align-items: center; gap: 10px; }
    .root-var-group {
        display: flex;
        align-items: center;
        gap: 6px;
        background: #060911;
        border: 1px solid var(--border-color);
        padding: 4px 8px;
        border-radius: 6px;
        font-size: 11px;
        color: var(--text-secondary);
        font-family: var(--font-mono);
    }
    .root-var-group input {
        width: 90px;
        background: transparent;
        border: none;
        color: #34d399;
        font-family: var(--font-mono);
        font-size: 12px;
        font-weight: 700;
        outline: none;
    }
    .search-box { position: relative; width: 320px; display: flex; align-items: center; }
    .search-box input {
        width: 100%;
        background: #060911;
        border: 1px solid var(--border-color);
        color: var(--text-primary);
        padding: 8px 90px 8px 12px;
        border-radius: 6px;
        font-size: 13px;
        font-family: var(--font-mono);
        outline: none;
    }
    .search-box input:focus {
        border-color: var(--accent-emerald);
        box-shadow: 0 0 0 2px rgba(16, 185, 129, 0.25);
    }
    .search-nav {
        position: absolute;
        right: 6px;
        top: 50%;
        transform: translateY(-50%);
        display: flex;
        align-items: center;
        gap: 4px;
    }
    .search-count {
        font-size: 11px;
        color: var(--accent-amber);
        font-family: var(--font-mono);
        margin-right: 2px;
    }
    .nav-arrow {
        background: #1e293b;
        border: 1px solid #475569;
        color: #f8fafc;
        border-radius: 3px;
        padding: 1px 5px;
        font-size: 10px;
        cursor: pointer;
        display: none;
    }
    .nav-arrow:hover {
        background: var(--accent-amber);
        color: #090d16;
        border-color: var(--accent-amber);
    }
    .filter-toggle-label {
        display: inline-flex;
        align-items: center;
        gap: 6px;
        background: #060911;
        border: 1px solid var(--border-color);
        padding: 6px 10px;
        border-radius: 6px;
        font-size: 12px;
        font-weight: 600;
        color: #e2e8f0;
        cursor: pointer;
        user-select: none;
    }
    .filter-toggle-label:hover {
        border-color: var(--accent-emerald);
    }
    .filter-toggle-label input {
        accent-color: var(--accent-emerald);
        cursor: pointer;
    }
    .btn {
        background: var(--bg-card);
        color: var(--text-primary);
        border: 1px solid var(--border-color);
        padding: 7px 12px;
        border-radius: 6px;
        font-size: 12px;
        font-weight: 600;
        cursor: pointer;
        transition: all 0.15s;
    }
    .btn:hover { border-color: var(--accent-emerald); background: #1e293b; }
    .btn-primary {
        background: rgba(16, 185, 129, 0.18);
        border-color: var(--accent-emerald);
        color: #6ee7b7;
    }
    .workspace {
        flex: 1;
        display: flex;
        overflow: hidden;
        position: relative;
    }
    #canvas-viewport {
        flex: 1;
        height: 100%;
        position: relative;
        overflow: hidden;
        background-color: #090d16;
        background-image:
            linear-gradient(rgba(30, 41, 59, 0.35) 1px, transparent 1px),
            linear-gradient(90deg, rgba(30, 41, 59, 0.35) 1px, transparent 1px);
        background-size: 32px 32px;
        cursor: grab;
        user-select: none;
    }
    #canvas-viewport:active { cursor: grabbing; }
    #scene {
        position: absolute;
        top: 0;
        left: 0;
        transform-origin: 0 0;
    }
    #edges-svg {
        position: absolute;
        top: 0;
        left: 0;
        overflow: visible;
        pointer-events: none;
    }
    #nodes-layer {
        position: absolute;
        top: 0;
        left: 0;
    }
    /* Rich Class UML Box - widened to 380px for full VMware.Vim.* type names */
    .uml-box {
        position: absolute;
        width: 380px;
        background: #131c2e;
        border: 1.5px solid #2e3f5c;
        border-radius: 8px;
        box-shadow: 0 10px 25px rgba(0, 0, 0, 0.55);
        cursor: pointer;
        transition: border-color 0.15s, box-shadow 0.15s;
        overflow: hidden;
    }
    .uml-box:hover {
        border-color: var(--accent-emerald);
    }
    .uml-box.matched {
        border-color: var(--accent-amber);
        box-shadow: 0 0 0 3px rgba(245, 158, 11, 0.4);
    }
    .uml-box.selected {
        border: 2.5px solid #22c55e !important;
        box-shadow: 0 0 0 4px rgba(34, 197, 94, 0.45), 0 0 24px rgba(34, 197, 94, 0.55), 0 12px 30px rgba(0, 0, 0, 0.75) !important;
        z-index: 10;
    }
    .uml-box.selected .uml-head {
        background: linear-gradient(180deg, rgba(34, 197, 94, 0.32) 0%, #152b26 100%);
        border-bottom-color: #22c55e;
    }
    .uml-box.moref-box-card {
        border-left: 4px solid var(--accent-purple);
    }
    .uml-box.schema-box-card {
        border-style: dashed;
    }
    .uml-head {
        padding: 8px 10px;
        background: linear-gradient(180deg, #1e293b 0%, #152033 100%);
        border-bottom: 1px solid #2e3f5c;
    }
    .uml-head-top {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 6px;
    }
    .uml-title {
        font-family: var(--font-mono);
        font-size: 13px;
        font-weight: 700;
        color: #fff;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
    }
    .uml-stereotype {
        font-family: var(--font-mono);
        font-size: 11px;
        color: var(--accent-cyan);
        margin-top: 2px;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
    }
    .uml-badge {
        font-size: 10px;
        font-family: var(--font-mono);
        padding: 1px 6px;
        border-radius: 4px;
        font-weight: 700;
        flex-shrink: 0;
    }
    .badge-live { background: rgba(16, 185, 129, 0.2); color: #34d399; }
    .badge-moref { background: rgba(168, 85, 247, 0.25); color: #d8b4fe; }
    .badge-null { background: rgba(245, 158, 11, 0.2); color: #fbbf24; }
    .badge-depth { background: rgba(245, 158, 11, 0.22); color: #fbbf24; border: 1px solid rgba(245,158,11,0.45); padding: 1px 5px; border-radius: 4px; }
    .uml-section {
        padding: 6px 10px;
        border-bottom: 1px solid rgba(46, 63, 92, 0.5);
        font-family: var(--font-mono);
        font-size: 11px;
    }
    .uml-prop-row {
        display: flex;
        justify-content: space-between;
        gap: 8px;
        line-height: 1.45;
        color: #cbd5e1;
    }
    .uml-prop-key {
        color: #93c5fd;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
        max-width: 155px;
    }
    .uml-prop-val {
        color: #94a3b8;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
        max-width: 195px;
    }
    .uml-foot {
        padding: 5px 10px;
        background: #0d1422;
        display: flex;
        align-items: center;
        justify-content: space-between;
        font-size: 10px;
        font-family: var(--font-mono);
        color: var(--text-secondary);
    }
    .toggle-pill {
        background: #1e293b;
        border: 1px solid #475569;
        color: #f8fafc;
        padding: 2px 7px;
        border-radius: 4px;
        font-weight: 700;
        cursor: pointer;
    }
    .toggle-pill:hover {
        background: var(--accent-emerald);
        color: #022c22;
        border-color: var(--accent-emerald);
    }
    .uml-head-actions {
        display: flex;
        align-items: center;
        gap: 5px;
        flex-shrink: 0;
    }
    .uml-pin-btn {
        background: rgba(15, 23, 42, 0.85);
        border: 1px solid #475569;
        color: #94a3b8;
        border-radius: 4px;
        padding: 1px 6px;
        font-size: 10px;
        font-family: var(--font-mono);
        font-weight: 700;
        cursor: pointer;
        line-height: 1.3;
        transition: all 0.15s;
        flex-shrink: 0;
    }
    .uml-pin-btn:hover {
        border-color: var(--accent-cyan);
        color: #f8fafc;
        background: rgba(6, 182, 212, 0.18);
    }
    .uml-pin-btn.pinned {
        background: rgba(6, 182, 212, 0.28);
        border-color: var(--accent-cyan);
        color: #67e8f9;
        box-shadow: 0 0 8px rgba(6, 182, 212, 0.45);
    }
    /* Floating Pinned Boxes Dock (bottom-left of canvas) */
    .pinned-dock {
        position: absolute;
        left: 16px;
        bottom: 16px;
        z-index: 30;
        width: 310px;
        background: rgba(13, 19, 34, 0.94);
        border: 1px solid #334155;
        border-radius: 8px;
        box-shadow: 0 10px 28px rgba(0, 0, 0, 0.75);
        backdrop-filter: blur(6px);
        overflow: hidden;
        cursor: default;
    }
    .pinned-dock-header {
        display: flex;
        align-items: center;
        justify-content: space-between;
        padding: 6px 10px;
        background: linear-gradient(180deg, #1e293b 0%, #131c2e 100%);
        border-bottom: 1px solid #2e3f5c;
        font-size: 11px;
        font-weight: 700;
        color: #e2e8f0;
        font-family: var(--font-mono);
    }
    .pinned-clear-btn {
        background: transparent;
        border: 1px solid #475569;
        color: #94a3b8;
        border-radius: 4px;
        font-size: 10px;
        padding: 1px 6px;
        cursor: pointer;
        font-family: var(--font-mono);
    }
    .pinned-clear-btn:hover {
        border-color: #f43f5e;
        color: #fda4af;
    }
    .pinned-dock-list {
        padding: 6px;
        display: flex;
        flex-direction: column;
        gap: 5px;
    }
    .pinned-empty {
        font-size: 11px;
        color: #64748b;
        padding: 4px 6px;
        font-style: italic;
    }
    .pinned-card {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 6px;
        padding: 6px 8px;
        background: #131c2e;
        border: 1px solid #2e3f5c;
        border-radius: 6px;
        cursor: pointer;
        transition: all 0.15s;
    }
    .pinned-card:hover {
        border-color: var(--accent-cyan);
        background: #19253d;
    }
    .pinned-card.active-selected {
        border-color: #22c55e;
        box-shadow: 0 0 0 1px rgba(34, 197, 94, 0.45);
        background: #142824;
    }
    .pinned-card-info {
        min-width: 0;
        flex: 1;
    }
    .pinned-card-title {
        font-family: var(--font-mono);
        font-size: 11.5px;
        font-weight: 700;
        color: #f8fafc;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
    }
    .pinned-card-path {
        font-family: var(--font-mono);
        font-size: 10px;
        color: var(--accent-cyan);
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
        margin-top: 1px;
    }
    .pinned-card-remove {
        background: transparent;
        border: none;
        color: #64748b;
        font-size: 14px;
        font-weight: 700;
        cursor: pointer;
        padding: 0 4px;
        line-height: 1;
        flex-shrink: 0;
    }
    .pinned-card-remove:hover {
        color: #f43f5e;
    }
    /* Draggable Panel Resizer & Inspector */
    .panel-resizer {
        width: 6px;
        background: #1e293b;
        cursor: col-resize;
        z-index: 18;
        transition: background 0.15s;
        flex-shrink: 0;
        position: relative;
    }
    .panel-resizer:hover,
    .panel-resizer.resizing {
        background: var(--accent-emerald);
        box-shadow: 0 0 10px rgba(16, 185, 129, 0.6);
    }
    .inspector {
        width: 520px;
        min-width: 320px;
        max-width: 80vw;
        background: var(--bg-panel);
        border-left: 1px solid var(--border-color);
        display: flex;
        flex-direction: column;
        height: 100%;
        z-index: 15;
        flex-shrink: 0;
    }
    .inspector-header {
        padding: 16px;
        background: #161f33;
        border-bottom: 1px solid var(--border-color);
    }
    .inspector-title-row {
        display: flex;
        align-items: center;
        justify-content: space-between;
        margin-bottom: 6px;
    }
    .inspector-node-name {
        font-family: var(--font-mono);
        font-size: 16px;
        font-weight: 700;
        word-break: break-all;
    }
    .inspector-type {
        font-family: var(--font-mono);
        font-size: 12px;
        color: var(--accent-cyan);
        margin-bottom: 10px;
        word-break: break-all;
    }
    .copy-box {
        background: #060911;
        border: 1px solid var(--border-color);
        border-radius: 6px;
        padding: 8px 10px;
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 8px;
        margin-top: 6px;
    }
    .copy-box code {
        font-family: var(--font-mono);
        font-size: 12px;
        color: #34d399;
        word-break: break-all;
    }
    .moref-box {
        background: rgba(168, 85, 247, 0.12);
        border: 1px solid rgba(168, 85, 247, 0.45);
        border-radius: 6px;
        padding: 8px 10px;
        margin-top: 8px;
        display: none;
    }
    .inspector-tabs {
        display: flex;
        border-bottom: 1px solid var(--border-color);
        background: #0f172a;
    }
    .tab-btn {
        flex: 1;
        padding: 10px;
        text-align: center;
        font-size: 12px;
        font-weight: 600;
        color: var(--text-secondary);
        cursor: pointer;
        border-bottom: 2px solid transparent;
    }
    .tab-btn.active {
        color: var(--accent-emerald);
        border-bottom-color: var(--accent-emerald);
    }
    .inspector-content {
        flex: 1;
        overflow-y: auto;
        padding: 12px 16px;
    }
    .item-table { width: 100%; border-collapse: collapse; font-size: 12px; }
    .item-table th {
        text-align: left;
        padding: 8px 6px;
        border-bottom: 1px solid var(--border-color);
        color: var(--text-secondary);
        font-size: 11px;
        text-transform: uppercase;
    }
    .item-table td {
        padding: 8px 6px;
        border-bottom: 1px solid rgba(51, 65, 85, 0.45);
        vertical-align: top;
        font-family: var(--font-mono);
    }
    .prop-name { color: #f8fafc; font-weight: 600; }
    .prop-type { color: var(--accent-cyan); font-size: 11px; word-break: break-all; }
    .prop-val { color: #cbd5e1; word-break: break-word; font-size: 11px; }
    .prop-val.null-val { color: var(--accent-amber); font-style: italic; }
    .doc-desc {
        margin-top: 4px;
        font-family: var(--font-sans);
        font-size: 11px;
        line-height: 1.4;
        color: #94a3b8;
        background: rgba(15, 23, 42, 0.65);
        border-left: 2px solid #38bdf8;
        padding: 4px 7px;
        border-radius: 0 4px 4px 0;
    }
    .class-doc-box {
        font-family: var(--font-sans);
        font-size: 11.5px;
        line-height: 1.45;
        color: #cbd5e1;
        background: rgba(6, 182, 212, 0.08);
        border: 1px solid rgba(6, 182, 212, 0.3);
        border-left: 3px solid var(--accent-cyan);
        padding: 6px 9px;
        border-radius: 5px;
        margin-bottom: 8px;
        display: none;
    }
    body.hide-docs .doc-desc,
    body.hide-docs .class-doc-box {
        display: none !important;
    }
    .doc-exp-btn {
        display: inline-block;
        margin-left: 5px;
        color: var(--accent-emerald);
        font-family: var(--font-mono);
        font-weight: 800;
        font-size: 10.5px;
        cursor: pointer;
        background: rgba(16, 185, 129, 0.14);
        border: 1px solid rgba(16, 185, 129, 0.4);
        padding: 0 5px;
        border-radius: 3px;
        user-select: none;
    }
    .doc-exp-btn:hover {
        background: var(--accent-emerald);
        color: #022c22;
    }
    /* Highlighted search matches inside Inspector & UML Card */
    .item-table tr.search-hit-row {
        background: rgba(245, 158, 11, 0.18) !important;
        border-left: 4px solid var(--accent-amber);
    }
    .item-table tr.search-hit-row td {
        border-bottom-color: rgba(245, 158, 11, 0.45);
    }
    .match-pill {
        display: inline-block;
        background: var(--accent-amber);
        color: #090d16;
        font-size: 9px;
        font-weight: 900;
        padding: 1px 5px;
        border-radius: 3px;
        margin-left: 6px;
        vertical-align: middle;
        letter-spacing: 0.4px;
    }
    mark.hl {
        background: rgba(245, 158, 11, 0.4);
        color: #fef08a;
        padding: 0 2px;
        border-radius: 2px;
        font-weight: 700;
        text-decoration: underline;
    }
    .uml-prop-row.uml-prop-hit {
        background: rgba(245, 158, 11, 0.22);
        border-left: 3px solid var(--accent-amber);
        padding-left: 4px;
        border-radius: 3px;
    }
    .uml-prop-row.uml-prop-hit .uml-prop-key,
    .uml-prop-row.uml-prop-hit .uml-prop-val {
        color: #fde68a;
        font-weight: 700;
    }
    .mini-copy-btn {
        background: #1e293b;
        border: 1px solid #475569;
        color: #e2e8f0;
        border-radius: 4px;
        padding: 3px 7px;
        font-size: 10px;
        cursor: pointer;
    }
    .mini-copy-btn:hover { border-color: var(--accent-emerald); color: var(--accent-emerald); }
    .mini-where-btn {
        background: rgba(245, 158, 11, 0.16);
        border: 1px solid rgba(245, 158, 11, 0.55);
        color: #fbbf24;
        border-radius: 4px;
        padding: 3px 8px;
        font-size: 11px;
        font-weight: 800;
        font-family: var(--font-mono);
        cursor: pointer;
        transition: all 0.15s;
    }
    .mini-where-btn:hover {
        background: var(--accent-amber);
        color: #090d16;
        border-color: var(--accent-amber);
    }
    .mini-where-btn.active-cond {
        background: var(--accent-amber);
        color: #090d16;
        box-shadow: 0 0 8px rgba(245, 158, 11, 0.5);
    }
    .action-cell {
        display: flex;
        align-items: center;
        gap: 5px;
        white-space: nowrap;
    }
    /* Multi-condition Where-Object (?{ }) Filter Builder */
    .filter-builder {
        background: rgba(245, 158, 11, 0.08);
        border: 1px solid rgba(245, 158, 11, 0.4);
        border-radius: 6px;
        padding: 8px 10px;
        margin-top: 8px;
        display: none;
    }
    .filter-builder-header {
        display: flex;
        align-items: center;
        justify-content: space-between;
        margin-bottom: 6px;
    }
    .filter-builder-title {
        font-size: 11px;
        font-weight: 700;
        color: #fbbf24;
        font-family: var(--font-mono);
    }
    .filter-chips {
        display: flex;
        flex-wrap: wrap;
        gap: 5px;
        margin-bottom: 6px;
    }
    .filter-chip {
        background: #090d16;
        border: 1px solid #475569;
        border-radius: 4px;
        padding: 2px 6px;
        font-family: var(--font-mono);
        font-size: 10px;
        color: #e2e8f0;
        display: inline-flex;
        align-items: center;
        gap: 5px;
    }
    .filter-chip select {
        background: #1e293b;
        color: #fbbf24;
        border: 1px solid #334155;
        border-radius: 3px;
        font-family: var(--font-mono);
        font-size: 10px;
        padding: 0 2px;
        outline: none;
    }
    .filter-chip-remove {
        color: #f43f5e;
        font-weight: 800;
        cursor: pointer;
        padding: 0 2px;
    }
    .toast {
        position: fixed;
        bottom: 20px;
        right: 520px;
        background: var(--accent-emerald);
        color: #022c22;
        padding: 8px 16px;
        border-radius: 6px;
        font-weight: 700;
        font-size: 12px;
        font-family: var(--font-mono);
        opacity: 0;
        pointer-events: none;
        transition: opacity 0.2s;
        z-index: 100;
    }
    .toast.show { opacity: 1; }
</style>
</head>
<body>
<header>
    <div class="brand">
        <a href="https://xdlabs.info" target="_blank" rel="noopener noreferrer" style="text-decoration:none;" title="Visit https://xdlabs.info"><span class="brand-logo" style="cursor:pointer;">xDlabs</span></a>
        <a class="brand-social-link brand-li" href="https://www.linkedin.com/company/xdlabs/home/" target="_blank" rel="noopener noreferrer" title="xDlabs on LinkedIn">in</a>
        <a class="brand-social-link brand-gh" href="https://github.com/qlikq/xDPsApiExplorer" target="_blank" rel="noopener noreferrer" title="xDPsApiExplorer on GitHub"><svg viewBox="0 0 16 16" width="14" height="14" fill="currentColor"><path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"></path></svg></a>
        <span class="brand-title">ApiExplorer</span>
        <span class="brand-subtitle">MaxDepth: __MAX_DEPTH__</span>
    </div>
    <div class="toolbar">
        <div class="root-var-group" title="Change root PowerShell variable name on the fly">
            <span>Root Var:</span>
            <input type="text" id="rootVarInput" value="__ROOT_NAME__" />
        </div>
        <div class="search-box">
            <input type="text" id="searchInput" placeholder="Search UML attributes, methods, types..." />
            <div class="search-nav">
                <span class="search-count" id="searchCount"></span>
                <button class="nav-arrow" id="btnPrevMatch" title="Previous matched box">&#9664;</button>
                <button class="nav-arrow" id="btnNextMatch" title="Next matched box">&#9654;</button>
            </div>
        </div>
        <label class="filter-toggle-label" title="When searching, hide all UML boxes that are not on the matched path">
            <input type="checkbox" id="chkHideUnmatched" checked />
            <span>Hide Unmatched</span>
        </label>
        <label class="filter-toggle-label" title="Show/hide official Broadcom vSphere SDK documentation descriptions">
            <input type="checkbox" id="chkShowDocs" checked />
            <span>Show Docs</span>
        </label>
        <button class="btn" id="btnExpandAll">Expand All</button>
        <button class="btn" id="btnCollapseAll">Collapse</button>
        <button class="btn btn-primary" id="btnResetZoom">Center View</button>
    </div>
</header>

<div class="workspace">
    <div id="canvas-viewport">
        <div id="scene">
            <svg id="edges-svg" width="5000" height="5000"></svg>
            <div id="nodes-layer"></div>
        </div>

        <div class="pinned-dock" id="pinnedDock">
            <div class="pinned-dock-header">
                <span>&#128204; Pinned Boxes (<span id="pinnedCount">0</span>/5)</span>
                <button class="pinned-clear-btn" id="btnClearPinned" style="display:none;" title="Clear all pinned boxes">Clear</button>
            </div>
            <div class="pinned-dock-list" id="pinnedDockList"></div>
        </div>
    </div>

    <div class="panel-resizer" id="panelResizer" title="Drag left/right to resize Inspector panel"></div>

    <aside class="inspector" id="inspectorPanel">
        <div class="inspector-header">
            <div class="inspector-title-row">
                <div class="inspector-node-name" id="inspName">Select a node</div>
                <div class="uml-head-actions">
                    <button class="uml-pin-btn" id="btnPinInspectorNode" title="Pin / unpin this object in Pinned Boxes (max 5)">&#128204; Pin</button>
                    <span class="uml-badge badge-live" id="inspBadge">LIVE</span>
                </div>
            </div>
            <div class="inspector-type" id="inspType"></div>
            <div class="class-doc-box" id="inspClassDoc"></div>

            <div class="copy-box">
                <code id="inspPath">$obj</code>
                <button class="btn btn-primary" id="btnCopyMainPath" style="padding:4px 10px;font-size:11px;">Copy PS Path</button>
            </div>

            <div class="moref-box" id="inspMoRefBox">
                <div style="font-size:11px;font-weight:700;color:#d8b4fe;margin-bottom:4px;">PowerCLI ManagedObjectReference (MoRef)</div>
                <div class="copy-box" style="margin-top:4px;background:#0f172a;">
                    <code id="inspMoRefCmd" style="color:#d8b4fe;">Get-View -Id $obj</code>
                    <button class="btn" id="btnCopyMoRef" style="padding:3px 8px;font-size:11px;border-color:#a855f7;color:#f3e8ff;">Copy Get-View</button>
                </div>
            </div>

            <div class="filter-builder" id="filterBuilderBox">
                <div class="filter-builder-header">
                    <span class="filter-builder-title">?{ ... } Where-Object Filter Builder</span>
                    <div style="display:flex;gap:5px;align-items:center;">
                        <select id="filterJoinOp" style="background:#090d16;color:#fbbf24;border:1px solid #475569;border-radius:4px;font-size:10px;padding:2px 4px;font-family:var(--font-mono);">
                            <option value="-and">Join: -and</option>
                            <option value="-or">Join: -or</option>
                        </select>
                        <button class="mini-copy-btn" id="btnClearFilter" style="color:#fda4af;border-color:#f43f5e;">Clear</button>
                    </div>
                </div>
                <div class="filter-chips" id="filterChipsContainer"></div>
                <div class="copy-box" style="margin-top:4px;background:#090d16;border-color:rgba(245,158,11,0.45);">
                    <code id="filterOutputCode" style="color:#fbbf24;">$vm | ?{ }</code>
                    <button class="btn" id="btnCopyFilterCmd" style="padding:4px 10px;font-size:11px;background:rgba(245,158,11,0.2);border-color:#f59e0b;color:#fde68a;flex-shrink:0;">Copy ?{ }</button>
                </div>
            </div>
        </div>

        <div class="inspector-tabs">
            <div class="tab-btn active" id="tabProps">Properties (<span id="countProps">0</span>)</div>
            <div class="tab-btn" id="tabMethods">Methods (<span id="countMethods">0</span>)</div>
        </div>

        <div class="inspector-content" id="panelProps">
            <table class="item-table">
                <thead>
                    <tr>
                        <th>Property / Full Type</th>
                        <th>Value</th>
                        <th>Copy</th>
                    </tr>
                </thead>
                <tbody id="propsTableBody"></tbody>
            </table>
        </div>

        <div class="inspector-content" id="panelMethods" style="display:none;">
            <table class="item-table">
                <thead>
                    <tr>
                        <th>Method Signature</th>
                        <th>Return Type</th>
                        <th>Copy</th>
                    </tr>
                </thead>
                <tbody id="methodsTableBody"></tbody>
            </table>
        </div>
    </aside>
</div>

<div class="toast" id="toastMsg">Copied!</div>

<script>
const TREE_DATA = __JSON_PAYLOAD__;
const INITIAL_ROOT_NAME = "__ROOT_NAME__";
let currentRootName = INITIAL_ROOT_NAME;

const viewport = document.getElementById('canvas-viewport');
const scene = document.getElementById('scene');
const edgesSvg = document.getElementById('edges-svg');
const nodesLayer = document.getElementById('nodes-layer');

let selectedNode = null;
let userClickedNode = false;
const MAX_PINNED_NODES = 5;
let pinnedNodes = [];
let panX = 50;
let panY = 80;
let scale = 0.85;
let isDragging = false;
let startX = 0;
let startY = 0;
let whereConditions = [];
let currentSearchQuery = '';
let matchedNodesList = [];
let currentMatchIndex = 0;
let expandedDocsSet = new Set();

function getShortDocSnippet(text) {
    if (!text) return { short: '', isTruncated: false };
    const clean = String(text).trim();
    if (clean.length <= 200) return { short: clean, isTruncated: false };
    // Try to cut after 2 sentences if within reasonable length (80..240 chars)
    const sentenceRegex = /[^.!?]+[.!?]+(\s|$)/g;
    let match;
    let endIdx = 0;
    let sentences = 0;
    while ((match = sentenceRegex.exec(clean)) !== null) {
        endIdx = sentenceRegex.lastIndex;
        sentences++;
        if (sentences >= 2 || endIdx >= 180) break;
    }
    if (endIdx >= 60 && endIdx < clean.length) {
        return { short: clean.substring(0, endIdx).trim(), isTruncated: true };
    }
    return { short: clean.substring(0, 185).trim() + '...', isTruncated: true };
}

function renderExpandableDocHtml(docKey, fullText, query, prefixHtml) {
    if (!fullText) return '';
    const isExp = expandedDocsSet.has(docKey);
    const snippetInfo = getShortDocSnippet(fullText);
    const prefix = prefixHtml || '';
    if (!snippetInfo.isTruncated) {
        return prefix + highlightMatchText(fullText, query);
    }
    if (isExp) {
        return `${prefix}${highlightMatchText(fullText, query)} <span class="doc-exp-btn" onclick="toggleDocExpand('${escapeJs(docKey)}', event)" title="Collapse description">[-]</span>`;
    } else {
        return `${prefix}${highlightMatchText(snippetInfo.short, query)} <span class="doc-exp-btn" onclick="toggleDocExpand('${escapeJs(docKey)}', event)" title="Expand full description">[+]</span>`;
    }
}

function toggleDocExpand(docKey, ev) {
    if (ev) ev.stopPropagation();
    if (expandedDocsSet.has(docKey)) {
        expandedDocsSet.delete(docKey);
    } else {
        expandedDocsSet.add(docKey);
    }
    if (selectedNode) selectNode(selectedNode);
}

function getActiveSearchQuery() {
    const el = document.getElementById('searchInput');
    return el ? el.value.trim().toLowerCase() : '';
}

function isPropMatched(p, q) {
    if (!q) return false;
    return (p.Name && p.Name.toLowerCase().includes(q)) ||
           (p.Type && p.Type.toLowerCase().includes(q)) ||
           (p.Value !== null && p.Value !== undefined && String(p.Value).toLowerCase().includes(q));
}

function isMethodMatched(m, q) {
    if (!q) return false;
    return (m.Name && m.Name.toLowerCase().includes(q)) ||
           (m.Signature && m.Signature.toLowerCase().includes(q)) ||
           (m.ReturnType && m.ReturnType.toLowerCase().includes(q));
}

function highlightMatchText(str, q) {
    const safe = escapeHtml(str);
    if (!q) return safe;
    const escapedQ = escapeHtml(q).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    if (!escapedQ) return safe;
    const re = new RegExp(`(${escapedQ})`, 'gi');
    return safe.replace(re, '<mark class="hl">$1</mark>');
}

function formatRootPath(rawPath) {
    if (!rawPath) return '';
    if (rawPath === INITIAL_ROOT_NAME) return currentRootName;
    if (rawPath.startsWith(INITIAL_ROOT_NAME + '.') || rawPath.startsWith(INITIAL_ROOT_NAME + '[')) {
        return currentRootName + rawPath.substring(INITIAL_ROOT_NAME.length);
    }
    return rawPath.replace(INITIAL_ROOT_NAME, currentRootName);
}

function getRelativeDollarBarPath(rawPath) {
    if (!rawPath) return '$_';
    if (rawPath === INITIAL_ROOT_NAME) return '$_';
    if (rawPath.startsWith(INITIAL_ROOT_NAME + '.') || rawPath.startsWith(INITIAL_ROOT_NAME + '[')) {
        return '$_' + rawPath.substring(INITIAL_ROOT_NAME.length);
    }
    return '$_.' + rawPath;
}

function formatPsLiteralValue(prop) {
    if (!prop || prop.IsNull || prop.Value === '$null' || String(prop.Value).startsWith('$null')) {
        return '$null';
    }
    const t = (prop.Type || '').toLowerCase();
    const v = String(prop.Value).trim();
    if (t === 'system.boolean' || v === '$true' || v === '$false') {
        return v.startsWith('$') ? v : '$' + v.toLowerCase();
    }
    if (t.match(/^system\.(int16|int32|int64|uint16|uint32|uint64|byte|sbyte|single|double|decimal)$/) && v.match(/^-?\d+(\.\d+)?$/)) {
        return v;
    }
    return "'" + v.replace(/'/g, "''") + "'";
}

function buildWhereFilterCommand() {
    if (whereConditions.length === 0) return '';
    const joinOp = document.getElementById('filterJoinOp').value || '-and';
    const exprParts = whereConditions.map(c => `${c.relPath} ${c.op} ${c.literalVal}`);
    return `${currentRootName} | ?{ ${exprParts.join(' ' + joinOp + ' ')} }`;
}

function updateFilterBuilderUI() {
    const box = document.getElementById('filterBuilderBox');
    const chipsContainer = document.getElementById('filterChipsContainer');
    const codeEl = document.getElementById('filterOutputCode');

    if (whereConditions.length === 0) {
        box.style.display = 'none';
        return;
    }
    box.style.display = 'block';

    chipsContainer.innerHTML = whereConditions.map((c, idx) => `
        <span class="filter-chip">
            <span>${escapeHtml(c.relPath)}</span>
            <select onchange="changeWhereOp(${idx}, this.value)">
                <option value="-eq" ${c.op === '-eq' ? 'selected' : ''}>-eq</option>
                <option value="-ne" ${c.op === '-ne' ? 'selected' : ''}>-ne</option>
                <option value="-like" ${c.op === '-like' ? 'selected' : ''}>-like</option>
                <option value="-match" ${c.op === '-match' ? 'selected' : ''}>-match</option>
                <option value="-gt" ${c.op === '-gt' ? 'selected' : ''}>-gt</option>
                <option value="-lt" ${c.op === '-lt' ? 'selected' : ''}>-lt</option>
            </select>
            <span style="color:#34d399;">${escapeHtml(c.literalVal)}</span>
            <span class="filter-chip-remove" title="Remove condition" onclick="removeWhereCondition(${idx})">&times;</span>
        </span>
    `).join('');

    codeEl.textContent = buildWhereFilterCommand();
}

function toggleWhereConditionByRawPath(rawPath) {
    if (!selectedNode || !selectedNode.Properties) return;
    const prop = selectedNode.Properties.find(p => p.PsPath === rawPath);
    if (!prop) return;

    const existingIdx = whereConditions.findIndex(c => c.rawPath === prop.PsPath);
    if (existingIdx === -1) {
        whereConditions.push({
            rawPath: prop.PsPath,
            relPath: getRelativeDollarBarPath(prop.PsPath),
            op: '-eq',
            literalVal: formatPsLiteralValue(prop)
        });
    }
    updateFilterBuilderUI();
    const cmd = buildWhereFilterCommand();
    if (cmd) copyText(cmd);
    if (selectedNode) selectNode(selectedNode);
}

function changeWhereOp(idx, newOp) {
    if (whereConditions[idx]) {
        whereConditions[idx].op = newOp;
        updateFilterBuilderUI();
        const cmd = buildWhereFilterCommand();
        if (cmd) copyText(cmd);
    }
}

function removeWhereCondition(idx) {
    whereConditions.splice(idx, 1);
    updateFilterBuilderUI();
    if (selectedNode) selectNode(selectedNode);
}

// Prepare collapse state (expand depth 0 & 1 initially)
function initTreeState(node, depth, parent) {
    node._depth = depth;
    node._parent = parent || null;
    node._expanded = depth < 2;
    node._matched = false;
    node._matchedPath = false;
    (node.Children || []).forEach(c => initTreeState(c, depth + 1, node));
}
initTreeState(TREE_DATA, 0, null);

const BOX_W = 380;
const COL_GAP = 105;
const ROW_GAP = 24;

function getBoxHeight(node) {
    const rows = Math.max(1, Math.min((node.Properties || []).length, 4));
    return 90 + (rows * 19);
}

// Pure JS Hierarchical Tree Layout Algorithm
function computeLayout(rootNode) {
    let currentLeafY = 0;
    const visibleNodes = [];
    const visibleEdges = [];
    const activeQ = getActiveSearchQuery();
    const hideUnmatched = document.getElementById('chkHideUnmatched') && document.getElementById('chkHideUnmatched').checked && activeQ.length > 0;

    const selectedPathSet = new Set();
    if (selectedNode) {
        let cur = selectedNode;
        while (cur) {
            selectedPathSet.add(cur.Id);
            cur = cur._parent;
        }
    }

    function layoutRec(node, depth) {
        const boxH = getBoxHeight(node);
        node._w = BOX_W;
        node._h = boxH;
        node._x = depth * (BOX_W + COL_GAP);

        let kids = (node._expanded && node.Children) ? node.Children : [];
        if (hideUnmatched) {
            kids = kids.filter(k => k._matchedPath || selectedPathSet.has(k.Id));
        }
        if (kids.length === 0) {
            node._y = currentLeafY;
            currentLeafY += boxH + ROW_GAP;
        } else {
            const subtreeStartY = currentLeafY;
            kids.forEach(k => {
                layoutRec(k, depth + 1);
                visibleEdges.push({ source: node, target: k });
            });
            const firstChild = kids[0];
            const lastChild = kids[kids.length - 1];
            const center = (firstChild._y + (lastChild._y + lastChild._h)) / 2;
            node._y = Math.max(subtreeStartY, center - boxH / 2);
            currentLeafY = Math.max(currentLeafY, node._y + boxH + ROW_GAP);
        }
        visibleNodes.push(node);
    }

    layoutRec(rootNode, 0);
    return { visibleNodes, visibleEdges };
}

function renderScene() {
    const { visibleNodes, visibleEdges } = computeLayout(TREE_DATA);

    nodesLayer.innerHTML = '';
    edgesSvg.innerHTML = '';

    // Draw Bezier Connectors
    visibleEdges.forEach(e => {
        const sx = e.source._x + e.source._w;
        const sy = e.source._y + e.source._h / 2;
        const tx = e.target._x;
        const ty = e.target._y + e.target._h / 2;
        const mx = (sx + tx) / 2;

        const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
        path.setAttribute('d', `M ${sx} ${sy} C ${mx} ${sy}, ${mx} ${ty}, ${tx} ${ty}`);
        path.setAttribute('fill', 'none');
        path.setAttribute('stroke', e.target._matchedPath ? '#f59e0b' : '#334155');
        path.setAttribute('stroke-width', e.target._matchedPath ? '3' : '2');
        edgesSvg.appendChild(path);
    });

    // Draw Rich UML Class Boxes
    visibleNodes.forEach(node => {
        const div = document.createElement('div');
        let classes = ['uml-box'];
        if (selectedNode && selectedNode.Id === node.Id) classes.push('selected');
        if (node._matched) classes.push('matched');
        if (node.IsMoRef) classes.push('moref-box-card');
        if (node.IsSchemaOnly || node.IsNull) classes.push('schema-box-card');
        div.className = classes.join(' ');
        div.style.left = node._x + 'px';
        div.style.top = node._y + 'px';
        div.style.height = node._h + 'px';

        let badgeClass = 'badge-live';
        let badgeText = 'LIVE';
        if (node.IsMoRef) { badgeClass = 'badge-moref'; badgeText = 'MoRef'; }
        else if (node.IsSchemaOnly || node.IsNull) { badgeClass = 'badge-null'; badgeText = '$null'; }

        const activeQ = getActiveSearchQuery();
        const allProps = (node.Properties || []).slice();
        if (activeQ) {
            allProps.sort((a, b) => {
                const aHit = isPropMatched(a, activeQ) ? 1 : 0;
                const bHit = isPropMatched(b, activeQ) ? 1 : 0;
                return bHit - aHit;
            });
        }
        const previewProps = allProps.slice(0, 4);
        const propsHtml = previewProps.map(p => {
            const pHit = isPropMatched(p, activeQ);
            return `
            <div class="uml-prop-row ${pHit ? 'uml-prop-hit' : ''}">
                <span class="uml-prop-key" title="${escapeHtml(p.Name)} (+ ${escapeHtml(p.Type)})">+ ${highlightMatchText(p.Name, activeQ)}</span>
                <span class="uml-prop-val" title="${escapeHtml(p.Value)}">${highlightMatchText(p.Value, activeQ)}</span>
            </div>
            `;
        }).join('');

        const childCount = (node.Children || []).length;
        let toggleHtml = '<span>leaf</span>';
        if (childCount > 0) {
            toggleHtml = `<span class="toggle-pill" data-toggle="${node.Id}">${node._expanded ? '−' : '+'} ${childCount} nested</span>`;
        } else if (node.TruncatedByDepth) {
            toggleHtml = `<span class="badge-depth" title="Increase -MaxDepth to expand deeper objects">MaxDepth reached</span>`;
        }

        const displayTitle = node === TREE_DATA ? currentRootName : node.Name;
        const isPinned = isNodePinned(node);

        div.innerHTML = `
            <div class="uml-head">
                <div class="uml-head-top">
                    <span class="uml-title" title="${escapeHtml(displayTitle)}">${escapeHtml(displayTitle)}</span>
                    <div class="uml-head-actions">
                        <button class="uml-pin-btn ${isPinned ? 'pinned' : ''}" data-pin="${node.Id}" title="${isPinned ? 'Unpin from Pinned Boxes' : 'Pin to Pinned Boxes (max 5)'}">&#128204;</button>
                        <span class="uml-badge ${badgeClass}">${badgeText}</span>
                    </div>
                </div>
                <div class="uml-stereotype" title="[${escapeHtml(node.TypeName)}]">[${escapeHtml(node.TypeName)}]</div>
            </div>
            <div class="uml-section">
                ${propsHtml || '<div style="color:#64748b;font-style:italic;">(no scalar properties)</div>'}
            </div>
            <div class="uml-foot">
                <span>Props: ${(node.Properties || []).length} | Methods: ${(node.Methods || []).length}</span>
                ${toggleHtml}
            </div>
        `;

        div.addEventListener('click', (ev) => {
            ev.stopPropagation();
            userClickedNode = true;
            selectNode(node);
            renderScene();
            renderPinnedDock();
        });

        const pinBtn = div.querySelector('[data-pin]');
        if (pinBtn) {
            pinBtn.addEventListener('click', (ev) => {
                ev.stopPropagation();
                togglePinNode(node);
            });
        }

        const toggleBtn = div.querySelector('[data-toggle]');
        if (toggleBtn) {
            toggleBtn.addEventListener('click', (ev) => {
                ev.stopPropagation();
                node._expanded = !node._expanded;
                renderScene();
            });
        }

        nodesLayer.appendChild(div);
    });
}

function applyTransform() {
    scene.style.transform = `translate(${panX}px, ${panY}px) scale(${scale})`;
}

viewport.addEventListener('mousedown', (e) => {
    if (e.target.closest('.uml-box') || e.target.closest('.pinned-dock')) return;
    isDragging = true;
    startX = e.clientX - panX;
    startY = e.clientY - panY;
});

window.addEventListener('mousemove', (e) => {
    if (!isDragging) return;
    panX = e.clientX - startX;
    panY = e.clientY - startY;
    applyTransform();
});

window.addEventListener('mouseup', () => { isDragging = false; });

viewport.addEventListener('wheel', (e) => {
    e.preventDefault();
    const factor = e.deltaY < 0 ? 1.1 : 0.9;
    const newScale = Math.min(2.4, Math.max(0.18, scale * factor));
    const rect = viewport.getBoundingClientRect();
    const mx = e.clientX - rect.left;
    const my = e.clientY - rect.top;
    panX = mx - (mx - panX) * (newScale / scale);
    panY = my - (my - panY) * (newScale / scale);
    scale = newScale;
    applyTransform();
}, { passive: false });

function selectNode(data) {
    selectedNode = data;
    const displayTitle = data === TREE_DATA ? currentRootName : data.Name;
    document.getElementById('inspName').textContent = displayTitle;
    document.getElementById('inspType').textContent = '[' + data.TypeName + ']';
    document.getElementById('inspPath').textContent = formatRootPath(data.PsPath);

    const activeQ = getActiveSearchQuery();
    const classDocEl = document.getElementById('inspClassDoc');
    if (data.Description) {
        classDocEl.style.display = 'block';
        classDocEl.innerHTML = renderExpandableDocHtml('class_' + data.Id, data.Description, activeQ, '<strong>Broadcom SDK Docs:</strong> ');
    } else {
        classDocEl.style.display = 'none';
        classDocEl.textContent = '';
    }

    const badge = document.getElementById('inspBadge');
    if (data.IsMoRef) {
        badge.className = 'uml-badge badge-moref';
        badge.textContent = 'MoRef (' + (data.MoRefValue || 'Reference') + ')';
    } else if (data.IsSchemaOnly || data.IsNull) {
        badge.className = 'uml-badge badge-null';
        badge.textContent = '$null (Reflected .NET Schema)';
    } else {
        badge.className = 'uml-badge badge-live';
        badge.textContent = 'LIVE INSTANCE';
    }

    const inspPinBtn = document.getElementById('btnPinInspectorNode');
    if (inspPinBtn) {
        const pinned = isNodePinned(data);
        inspPinBtn.className = 'uml-pin-btn' + (pinned ? ' pinned' : '');
        inspPinBtn.innerHTML = pinned ? '&#128204; Pinned' : '&#128204; Pin';
    }
    renderPinnedDock();

    const morefBox = document.getElementById('inspMoRefBox');
    if (data.IsMoRef && data.MoRefCmd) {
        morefBox.style.display = 'block';
        document.getElementById('inspMoRefCmd').textContent = formatRootPath(data.MoRefCmd);
    } else {
        morefBox.style.display = 'none';
    }

    const rawProps = (data.Properties || []).slice();
    const rawMethods = (data.Methods || []).slice();
    document.getElementById('countProps').textContent = rawProps.length;
    document.getElementById('countMethods').textContent = rawMethods.length;

    let propMatchesCount = 0;
    let methodMatchesCount = 0;

    if (activeQ) {
        rawProps.forEach(p => { if (isPropMatched(p, activeQ)) propMatchesCount++; });
        rawMethods.forEach(m => { if (isMethodMatched(m, activeQ)) methodMatchesCount++; });

        rawProps.sort((a, b) => {
            const aHit = isPropMatched(a, activeQ) ? 1 : 0;
            const bHit = isPropMatched(b, activeQ) ? 1 : 0;
            return bHit - aHit;
        });

        rawMethods.sort((a, b) => {
            const aHit = isMethodMatched(a, activeQ) ? 1 : 0;
            const bHit = isMethodMatched(b, activeQ) ? 1 : 0;
            return bHit - aHit;
        });

        // Automatically switch tab if matches are only in Methods or in Properties
        if (propMatchesCount > 0) {
            document.getElementById('tabProps').classList.add('active');
            document.getElementById('tabMethods').classList.remove('active');
            document.getElementById('panelProps').style.display = 'block';
            document.getElementById('panelMethods').style.display = 'none';
            document.getElementById('panelProps').scrollTop = 0;
        } else if (methodMatchesCount > 0) {
            document.getElementById('tabMethods').classList.add('active');
            document.getElementById('tabProps').classList.remove('active');
            document.getElementById('panelMethods').style.display = 'block';
            document.getElementById('panelProps').style.display = 'none';
            document.getElementById('panelMethods').scrollTop = 0;
        }
    }

    document.getElementById('propsTableBody').innerHTML = rawProps.map(p => {
        const dynPath = formatRootPath(p.PsPath);
        const dynMoRef = p.MoRefCmd ? formatRootPath(p.MoRefCmd) : '';
        const isCondActive = whereConditions.some(c => c.rawPath === p.PsPath);
        const isHit = isPropMatched(p, activeQ);
        const docKey = 'prop_' + data.Id + '_' + p.Name;
        const valKey = 'val_' + data.Id + '_' + p.Name;
        return `
        <tr class="${isHit ? 'search-hit-row' : ''}">
            <td>
                <div class="prop-name">${highlightMatchText(p.Name, activeQ)}${isHit ? '<span class="match-pill">MATCH</span>' : ''}</div>
                <div class="prop-type">[${highlightMatchText(p.Type, activeQ)}]</div>
                ${p.Description ? `<div class="doc-desc">${renderExpandableDocHtml(docKey, p.Description, activeQ, '')}</div>` : ''}
            </td>
            <td>
                <div class="prop-val ${p.IsNull ? 'null-val' : ''}">${renderExpandableDocHtml(valKey, String(p.Value ?? ''), activeQ, '')}</div>
                ${p.IsMoRef && dynMoRef ? `<div style="margin-top:3px;"><button class="mini-copy-btn" onclick="copyText('${escapeJs(dynMoRef)}')">Copy Get-View</button></div>` : ''}
            </td>
            <td>
                <div class="action-cell">
                    <button class="mini-where-btn ${isCondActive ? 'active-cond' : ''}" title="Add to ?{ } Where-Object filter & copy command" onclick="toggleWhereConditionByRawPath('${escapeJs(p.PsPath)}')">?</button>
                    <button class="mini-copy-btn" onclick="copyText('${escapeJs(dynPath)}')">Copy Path</button>
                </div>
            </td>
        </tr>
        `;
    }).join('');

    document.getElementById('methodsTableBody').innerHTML = rawMethods.map(m => {
        const dynCall = formatRootPath(m.CallSnippet);
        const isHit = isMethodMatched(m, activeQ);
        const docKey = 'meth_' + data.Id + '_' + m.Name;
        return `
        <tr class="${isHit ? 'search-hit-row' : ''}">
            <td>
                <div class="prop-name" style="color:${m.IsTask ? '#fbbf24' : '#f8fafc'}">${highlightMatchText(m.Signature, activeQ)}${isHit ? '<span class="match-pill">MATCH</span>' : ''}</div>
                ${m.Description ? `<div class="doc-desc">${renderExpandableDocHtml(docKey, m.Description, activeQ, '')}</div>` : ''}
            </td>
            <td><span class="prop-type">[${highlightMatchText(m.ReturnType, activeQ)}]</span></td>
            <td><button class="mini-copy-btn" onclick="copyText('${escapeJs(dynCall)}')">Copy Call</button></td>
        </tr>
        `;
    }).join('');
}

document.getElementById('rootVarInput').addEventListener('input', (e) => {
    let val = e.target.value.trim();
    if (!val) val = '$obj';
    if (!val.startsWith('$')) val = '$' + val;
    currentRootName = val;
    updateFilterBuilderUI();
    if (selectedNode) selectNode(selectedNode);
    renderScene();
    renderPinnedDock();
});

function isNodePinned(node) {
    if (!node) return false;
    return pinnedNodes.some(n => n.Id === node.Id);
}

function togglePinNode(node) {
    if (!node) return;
    const existingIdx = pinnedNodes.findIndex(n => n.Id === node.Id);
    if (existingIdx !== -1) {
        pinnedNodes.splice(existingIdx, 1);
    } else {
        if (pinnedNodes.length >= MAX_PINNED_NODES) {
            showToast('Pinned Boxes full (max 5)! Unpin a box first.');
            return;
        }
        pinnedNodes.push(node);
    }
    if (selectedNode) selectNode(selectedNode);
    renderScene();
    renderPinnedDock();
}

function removePinnedNode(nodeId, ev) {
    if (ev) ev.stopPropagation();
    pinnedNodes = pinnedNodes.filter(n => n.Id !== nodeId);
    if (selectedNode) selectNode(selectedNode);
    renderScene();
    renderPinnedDock();
}

function jumpToPinnedNode(nodeId) {
    const node = pinnedNodes.find(n => n.Id === nodeId);
    if (!node) return;
    userClickedNode = true;
    expandAncestors(node);
    focusOnNode(node);
    renderPinnedDock();
}

function renderPinnedDock() {
    const countEl = document.getElementById('pinnedCount');
    const clearBtn = document.getElementById('btnClearPinned');
    const listEl = document.getElementById('pinnedDockList');
    if (!countEl || !listEl) return;

    countEl.textContent = String(pinnedNodes.length);
    if (clearBtn) {
        clearBtn.style.display = pinnedNodes.length > 0 ? 'inline-block' : 'none';
    }

    if (pinnedNodes.length === 0) {
        listEl.innerHTML = '<div class="pinned-empty">Click &#128204; on any box to pin it here (up to 5 items).</div>';
        return;
    }

    listEl.innerHTML = pinnedNodes.map(n => {
        const displayTitle = n === TREE_DATA ? currentRootName : n.Name;
        const dynPath = formatRootPath(n.PsPath);
        const isSelected = selectedNode && selectedNode.Id === n.Id;
        return `
        <div class="pinned-card ${isSelected ? 'active-selected' : ''}" onclick="jumpToPinnedNode('${escapeJs(n.Id)}')" title="${escapeHtml(dynPath)} &#10;[${escapeHtml(n.TypeName)}]">
            <div class="pinned-card-info">
                <div class="pinned-card-title">${escapeHtml(displayTitle)}</div>
                <div class="pinned-card-path">${escapeHtml(dynPath)}</div>
            </div>
            <button class="pinned-card-remove" title="Remove from Pinned Boxes" onclick="removePinnedNode('${escapeJs(n.Id)}', event)">&times;</button>
        </div>
        `;
    }).join('');
}

document.getElementById('btnPinInspectorNode').addEventListener('click', () => {
    if (selectedNode) togglePinNode(selectedNode);
});

document.getElementById('btnClearPinned').addEventListener('click', () => {
    pinnedNodes = [];
    if (selectedNode) selectNode(selectedNode);
    renderScene();
    renderPinnedDock();
});

document.getElementById('filterJoinOp').addEventListener('change', () => {
    updateFilterBuilderUI();
    const cmd = buildWhereFilterCommand();
    if (cmd) copyText(cmd);
});

document.getElementById('btnClearFilter').addEventListener('click', () => {
    whereConditions = [];
    updateFilterBuilderUI();
    if (selectedNode) selectNode(selectedNode);
});

document.getElementById('btnCopyFilterCmd').addEventListener('click', () => {
    const cmd = buildWhereFilterCommand();
    if (cmd) copyText(cmd);
});

function focusOnNode(node) {
    if (!node) return;
    selectNode(node);
    renderScene();
    if (node._x !== undefined && node._y !== undefined) {
        const rect = viewport.getBoundingClientRect();
        panX = (rect.width / 2) - (node._x + BOX_W / 2) * scale;
        panY = (rect.height / 2) - (node._y + (node._h || 120) / 2) * scale;
        applyTransform();
    }
}

function expandAncestors(node) {
    let p = node ? node._parent : null;
    while (p) {
        p._expanded = true;
        p = p._parent;
    }
}

function updateSearchNavUI() {
    const countEl = document.getElementById('searchCount');
    const prevBtn = document.getElementById('btnPrevMatch');
    const nextBtn = document.getElementById('btnNextMatch');

    if (matchedNodesList.length > 0) {
        countEl.textContent = `${currentMatchIndex + 1}/${matchedNodesList.length}`;
        prevBtn.style.display = matchedNodesList.length > 1 ? 'inline-block' : 'none';
        nextBtn.style.display = matchedNodesList.length > 1 ? 'inline-block' : 'none';
    } else if (getActiveSearchQuery().length > 0) {
        countEl.textContent = '0 matches';
        prevBtn.style.display = 'none';
        nextBtn.style.display = 'none';
    } else {
        countEl.textContent = '';
        prevBtn.style.display = 'none';
        nextBtn.style.display = 'none';
    }
}

function runSearchFilter(autoSelectFirst) {
    const q = getActiveSearchQuery();
    currentSearchQuery = q;
    matchedNodesList = [];
    currentMatchIndex = 0;

    function walkReset(n, d) {
        n._matched = false;
        n._matchedPath = false;
        n._propHit = false;
        n._expanded = d < 1;
        (n.Children || []).forEach(c => walkReset(c, d + 1));
    }
    walkReset(TREE_DATA, 0);

    if (q.length > 0) {
        const propMatchedNodes = [];
        const methodOnlyNodes = [];

        function searchWalk(n) {
            const nameOrTypeHit = (n.Name && n.Name.toLowerCase().includes(q)) ||
                                  (n.TypeName && n.TypeName.toLowerCase().includes(q)) ||
                                  (n.PsPath && n.PsPath.toLowerCase().includes(q));
            const propHit = (n.Properties || []).some(p => isPropMatched(p, q));
            const methodHit = (n.Methods || []).some(m => isMethodMatched(m, q));

            const hit = nameOrTypeHit || propHit || methodHit;
            let childHit = false;
            (n.Children || []).forEach(c => {
                if (searchWalk(c)) childHit = true;
            });

            if (hit) {
                n._matched = true;
                if (propHit || nameOrTypeHit) {
                    n._propHit = true;
                    propMatchedNodes.push(n);
                } else {
                    methodOnlyNodes.push(n);
                }
            }
            if (childHit) { n._expanded = true; }
            if (hit || childHit) { n._matchedPath = true; }
            return hit || childHit;
        }
        searchWalk(TREE_DATA);

        // Prioritize nodes matched by Property or Name/Type ahead of nodes matched only by Method
        matchedNodesList = propMatchedNodes.concat(methodOnlyNodes);

        if (userClickedNode && selectedNode) {
            expandAncestors(selectedNode);
            const existingIdx = matchedNodesList.indexOf(selectedNode);
            if (existingIdx !== -1) {
                currentMatchIndex = existingIdx;
            }
            updateSearchNavUI();
            focusOnNode(selectedNode);
        } else if (autoSelectFirst && matchedNodesList.length > 0) {
            currentMatchIndex = 0;
            updateSearchNavUI();
            focusOnNode(matchedNodesList[0]);
        } else {
            updateSearchNavUI();
            renderScene();
            if (selectedNode) selectNode(selectedNode);
        }
    } else {
        updateSearchNavUI();
        if (userClickedNode && selectedNode) {
            expandAncestors(selectedNode);
            focusOnNode(selectedNode);
        } else {
            selectNode(TREE_DATA);
            renderScene();
            panX = 50; panY = 80; scale = 0.85;
            applyTransform();
        }
    }
}

let prevSearchLen = 0;

document.getElementById('searchInput').addEventListener('input', () => {
    const q = getActiveSearchQuery();
    if (prevSearchLen === 0 && q.length > 0) {
        // Starting a brand new search query
        userClickedNode = false;
    }
    prevSearchLen = q.length;
    runSearchFilter(true);
});

document.getElementById('chkHideUnmatched').addEventListener('change', () => {
    renderScene();
    if (selectedNode) focusOnNode(selectedNode);
});

document.getElementById('chkShowDocs').addEventListener('change', (e) => {
    if (e.target.checked) {
        document.body.classList.remove('hide-docs');
    } else {
        document.body.classList.add('hide-docs');
    }
});

document.getElementById('btnPrevMatch').addEventListener('click', () => {
    if (matchedNodesList.length === 0) return;
    userClickedNode = true;
    currentMatchIndex = (currentMatchIndex - 1 + matchedNodesList.length) % matchedNodesList.length;
    updateSearchNavUI();
    focusOnNode(matchedNodesList[currentMatchIndex]);
});

document.getElementById('btnNextMatch').addEventListener('click', () => {
    if (matchedNodesList.length === 0) return;
    userClickedNode = true;
    currentMatchIndex = (currentMatchIndex + 1) % matchedNodesList.length;
    updateSearchNavUI();
    focusOnNode(matchedNodesList[currentMatchIndex]);
});

document.getElementById('btnExpandAll').addEventListener('click', () => {
    function exp(n) { n._expanded = true; (n.Children || []).forEach(exp); }
    exp(TREE_DATA);
    renderScene();
});

document.getElementById('btnCollapseAll').addEventListener('click', () => {
    userClickedNode = false;
    function col(n, d) { n._expanded = d < 1; (n.Children || []).forEach(c => col(c, d + 1)); }
    col(TREE_DATA, 0);
    renderScene();
});

document.getElementById('btnResetZoom').addEventListener('click', () => {
    scale = 0.85;
    if (userClickedNode && selectedNode && selectedNode !== TREE_DATA) {
        focusOnNode(selectedNode);
    } else {
        panX = 50; panY = 80;
        applyTransform();
    }
});

document.getElementById('btnCopyMainPath').addEventListener('click', () => {
    if (selectedNode) copyText(formatRootPath(selectedNode.PsPath));
});

document.getElementById('btnCopyMoRef').addEventListener('click', () => {
    if (selectedNode && selectedNode.MoRefCmd) copyText(formatRootPath(selectedNode.MoRefCmd));
});

document.getElementById('tabProps').addEventListener('click', () => {
    document.getElementById('tabProps').classList.add('active');
    document.getElementById('tabMethods').classList.remove('active');
    document.getElementById('panelProps').style.display = 'block';
    document.getElementById('panelMethods').style.display = 'none';
});

document.getElementById('tabMethods').addEventListener('click', () => {
    document.getElementById('tabMethods').classList.add('active');
    document.getElementById('tabProps').classList.remove('active');
    document.getElementById('panelMethods').style.display = 'block';
    document.getElementById('panelProps').style.display = 'none';
});

// Panel Resizer logic (drag left/right between graph and inspector)
const panelResizer = document.getElementById('panelResizer');
const inspectorPanel = document.getElementById('inspectorPanel');
let isResizingPanel = false;

panelResizer.addEventListener('mousedown', (e) => {
    e.preventDefault();
    isResizingPanel = true;
    panelResizer.classList.add('resizing');
    document.body.style.cursor = 'col-resize';
});

window.addEventListener('mousemove', (e) => {
    if (!isResizingPanel) return;
    const newWidth = Math.min(window.innerWidth * 0.8, Math.max(320, window.innerWidth - e.clientX));
    inspectorPanel.style.width = newWidth + 'px';
});

window.addEventListener('mouseup', () => {
    if (isResizingPanel) {
        isResizingPanel = false;
        panelResizer.classList.remove('resizing');
        document.body.style.cursor = '';
    }
});

function showToast(msg) {
    const toast = document.getElementById('toastMsg');
    toast.textContent = msg;
    toast.classList.add('show');
    setTimeout(() => toast.classList.remove('show'), 2000);
}

function copyText(txt) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(txt);
    } else {
        const ta = document.createElement('textarea');
        ta.value = txt;
        document.body.appendChild(ta);
        ta.select();
        document.execCommand('copy');
        document.body.removeChild(ta);
    }
    showToast('Copied: ' + txt);
}

function escapeHtml(str) {
    if (str === null || str === undefined) return '';
    return String(str).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function escapeJs(str) {
    if (!str) return '';
    return String(str).replace(/\\/g, '\\\\').replace(/'/g, "\\'");
}

selectNode(TREE_DATA);
renderScene();
renderPinnedDock();
applyTransform();
</script>
</body>
</html>
'@

    $html = $html.Replace('__ROOT_NAME__', $RootName)
    $html = $html.Replace('__MAX_DEPTH__', "$MaxDepth")
    $html = $html.Replace('__JSON_PAYLOAD__', $jsonPayload)
    return $html
}
