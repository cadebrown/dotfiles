import path from 'node:path';
import { visit } from 'unist-util-visit';

export default function remarkDocsLinks() {
  return (tree, file) => {
    const relative = file.path.split('/content/docs/')[1];
    if (!relative) return;
    let section = path.posix.basename(relative).replace(/\.mdx?$/, '').replaceAll('-', ' ');
    visit(tree, (node) => {
      if (node.type === 'heading') section = node.children.map((child) => child.value ?? '').join('');
      if (node.type === 'code' && node.lang === 'mermaid' && !node.value.includes('accTitle:')) {
        const lines = node.value.split('\n');
        lines.splice(1, 0, `  accTitle: ${section.replace(/[\n{}]/g, ' ')}`);
        node.value = lines.join('\n');
      }
      if (!['link', 'definition'].includes(node.type) || typeof node.url !== 'string') return;
      if (/^(?:[a-z]+:|#|\/\/)/i.test(node.url)) return;
      const [pathname, hash] = node.url.split('#');
      let resolved = pathname.startsWith('/') ? pathname.slice(1) : path.posix.join(path.posix.dirname(relative), pathname);
      if (resolved.startsWith('../')) {
        node.url = `https://github.com/cadebrown/dotfiles/blob/main/${resolved.replace(/^(\.\.\/)+/, '')}${hash ? `#${hash}` : ''}`;
        return;
      }
      if (!/\.mdx?$/.test(pathname)) {
        if (!pathname.startsWith('/') && /\.(json|toml|ya?ml|sh|py|txt|tmpl)$/.test(pathname)) {
          node.url = `https://github.com/cadebrown/dotfiles/blob/main/docs/${resolved}${hash ? `#${hash}` : ''}`;
        }
        return;
      }
      resolved = resolved.replace(/\.mdx?$/, '').replace(/(^|\/)README$/i, '$1index').replace(/(^|\/)index$/, '$1').replace(/^intro$/, '');
      node.url = `/${resolved}${resolved && !resolved.endsWith('/') ? '/' : ''}${hash ? `#${hash}` : ''}`;
    });
  };
}
