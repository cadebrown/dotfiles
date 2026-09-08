import {createServer} from 'node:http';
import {readFile} from 'node:fs/promises';

const root = new URL('./', import.meta.url);
const files = new Map([
  ['/', 'index.html'],
  ['/index.html', 'index.html'],
  ['/app.js', 'app.js'],
  ['/style.css', 'style.css'],
  ['/favicon.svg', 'favicon.svg']
]);
const types = {'index.html': 'text/html; charset=utf-8', 'app.js': 'text/javascript; charset=utf-8', 'style.css': 'text/css; charset=utf-8', 'favicon.svg': 'image/svg+xml'};
const port = Number(process.env.PORT || 4318);

createServer(async (request, response) => {
  const file = files.get(new URL(request.url, 'http://localhost').pathname);
  if (!file) return response.writeHead(404).end('Not found');
  try {
    response.writeHead(200, {'content-type': types[file], 'cache-control': 'no-store'});
    response.end(await readFile(new URL(file, root)));
  } catch {
    response.writeHead(500).end('Unable to load application');
  }
}).listen(port, '127.0.0.1', () => process.stdout.write(`Mission Control: http://127.0.0.1:${port}\n`));
