import { visit, SKIP } from 'unist-util-visit';

export default function rehypeDiagramFrames() {
  return (tree) => visit(tree, 'element', (node, index, parent) => {
    if (node.tagName !== 'svg' || !String(node.properties?.id ?? '').startsWith('mermaid-') || !parent || index === undefined) return;
    const viewBox = String(node.properties.viewBox ?? '').split(/\s+/).map(Number);
    const width = Number.isFinite(viewBox[2]) ? viewBox[2] : 640;
    parent.children[index] = {
      type: 'element', tagName: 'div',
      properties: { className: ['diagram-frame'], tabIndex: 0, role: 'region', ariaLabel: 'Diagram; scroll horizontally to inspect wide figures', style: `--diagram-min-width:${width}px` },
      children: [node],
    };
    parent.children.splice(index + 1, 0, { type: 'element', tagName: 'p', properties: { className: ['diagram-hint'] }, children: [{ type: 'text', value: 'Wide diagrams scroll horizontally. Focus the figure to use arrow keys.' }] });
    return [SKIP, index + 2];
  });
}
